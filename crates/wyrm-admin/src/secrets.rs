//! SecretStore (wiki "Захист даних"): link secrets (device passwords, DLMS
//! keys) encrypted at rest, never in the tree, `~def` or logs.
//!
//! `secrets.bin` = `"WYSS1" || nonce(12) || ChaCha20-Poly1305(cbor)`, key in
//! `secrets.key` (0600). The key file is the root of trust here; binding it
//! to a TPM or OS keyring is a later step.

use crate::secret::{load_or_create_key, write_private, Error};
use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, CHACHA20_POLY1305, NONCE_LEN};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use wyrm_core::Value;
use zeroize::Zeroizing;

const MAGIC: &[u8; 5] = b"WYSS1";

type Db = BTreeMap<String, BTreeMap<String, Zeroizing<Vec<u8>>>>;

pub struct SecretStore {
    path: PathBuf,
    key: LessSafeKey,
    db: Mutex<Db>,
}

fn encode(db: &Db) -> Zeroizing<Vec<u8>> {
    let v = Value::Map(
        db.iter()
            .map(|(link, m)| {
                (
                    link.clone(),
                    Value::Map(
                        m.iter()
                            .map(|(k, s)| (k.clone(), Value::Bytes(s.to_vec())))
                            .collect(),
                    ),
                )
            })
            .collect(),
    );
    Zeroizing::new(wyrm_core::codec::to_vec(&v).unwrap_or_default())
}

fn decode(b: &[u8]) -> Result<Db, Error> {
    let Value::Map(links) = wyrm_core::codec::from_slice::<Value>(b)? else {
        return Err("secrets: bad layout".into());
    };
    let mut db = Db::new();
    for (link, v) in links {
        let Value::Map(m) = v else { continue };
        let entry = db.entry(link).or_default();
        for (k, s) in m {
            if let Value::Bytes(bytes) = s {
                entry.insert(k, Zeroizing::new(bytes));
            }
        }
    }
    Ok(db)
}

impl SecretStore {
    pub fn open(dir: &Path) -> Result<Self, Error> {
        let raw_key = load_or_create_key(&dir.join("secrets.key"))?;
        let key = LessSafeKey::new(
            UnboundKey::new(&CHACHA20_POLY1305, &raw_key).map_err(|_| "secrets: bad key")?,
        );
        let path = dir.join("secrets.bin");
        let db = match std::fs::read(&path) {
            // Only a missing file is an empty store: any other error would
            // drop every secret at the next save.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Db::new(),
            Err(e) => return Err(format!("secrets.bin: {e}").into()),
            Ok(data) => {
                if data.len() < MAGIC.len() + NONCE_LEN || &data[..MAGIC.len()] != MAGIC {
                    return Err("secrets.bin: not a WYRM secret store".into());
                }
                let nonce =
                    Nonce::try_assume_unique_for_key(&data[MAGIC.len()..MAGIC.len() + NONCE_LEN])
                        .map_err(|_| "secrets.bin: bad nonce")?;
                let mut sealed = Zeroizing::new(data[MAGIC.len() + NONCE_LEN..].to_vec());
                let plain = key
                    .open_in_place(nonce, Aad::from(MAGIC), &mut sealed)
                    .map_err(|_| "secrets.bin: cannot decrypt (wrong key or tampered)")?;
                decode(plain)?
            }
        };
        Ok(Self {
            path,
            key,
            db: Mutex::new(db),
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Db> {
        self.db.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn save(&self, db: &Db) -> Result<(), Error> {
        let mut nonce = [0u8; NONCE_LEN];
        getrandom::fill(&mut nonce).map_err(|e| format!("no randomness: {e}"))?;
        let mut buf = encode(db);
        self.key
            .seal_in_place_append_tag(
                Nonce::assume_unique_for_key(nonce),
                Aad::from(MAGIC),
                &mut *buf,
            )
            .map_err(|_| "secrets: seal failed")?;
        let mut out = MAGIC.to_vec();
        out.extend(nonce);
        out.extend(buf.iter());
        write_private(&self.path, &out)?;
        Ok(())
    }

    /// Saves one secret; when the store cannot be saved it is as before (no secret only in
    /// memory: a key lost at the next start would leave sealed data unreadable).
    pub fn set(&self, link: &str, name: &str, value: &[u8]) -> Result<(), Error> {
        let mut db = self.lock();
        let entry = db.entry(link.to_owned()).or_default();
        let old = entry.insert(name.to_owned(), Zeroizing::new(value.to_vec()));
        let saved = self.save(&db);
        if saved.is_err() {
            let entry = db.entry(link.to_owned()).or_default();
            match old {
                Some(v) => {
                    entry.insert(name.to_owned(), v);
                }
                None => {
                    entry.remove(name);
                    if entry.is_empty() {
                        db.remove(link);
                    }
                }
            }
        }
        saved
    }

    /// `true` if it existed.
    pub fn remove(&self, link: &str, name: &str) -> Result<bool, Error> {
        let mut db = self.lock();
        let had = db.get_mut(link).and_then(|m| m.remove(name)).is_some();
        if had {
            self.save(&db)?;
        }
        Ok(had)
    }

    pub fn drop_link(&self, link: &str) -> Result<(), Error> {
        let mut db = self.lock();
        if db.remove(link).is_some() {
            self.save(&db)?;
        }
        Ok(())
    }

    /// Where the secrets a restore replaces are kept until it is committed.
    /// No link has this name (an id never starts with `.`).
    fn stash_name(link: &str) -> String {
        format!(".restoring/{link}")
    }

    /// Set the secrets `new` of `link` and keep what the link had before
    /// beside them, in one save: a restore that does not reach its end
    /// takes them back with [`Self::unstash`] (ADR 0048 §3.5). The store is
    /// as before when it cannot be saved.
    pub fn replace_stashed(
        &self,
        link: &str,
        new: &BTreeMap<String, Zeroizing<Vec<u8>>>,
    ) -> Result<(), Error> {
        let mut db = self.lock();
        let before = db.clone();
        let old = db.get(link).cloned().unwrap_or_default();
        db.insert(Self::stash_name(link), old);
        let entry = db.entry(link.to_owned()).or_default();
        for (name, v) in new {
            entry.insert(name.clone(), v.clone());
        }
        if entry.is_empty() {
            db.remove(link);
        }
        let saved = self.save(&db);
        if saved.is_err() {
            *db = before;
        }
        saved
    }

    /// End a [`Self::replace_stashed`] of `link`: `restore` puts the
    /// secrets it had before back, else they are forgotten. `false`: nothing
    /// was kept.
    pub fn unstash(&self, link: &str, restore: bool) -> Result<bool, Error> {
        let mut db = self.lock();
        let before = db.clone();
        let Some(old) = db.remove(&Self::stash_name(link)) else {
            return Ok(false);
        };
        if restore {
            if old.is_empty() {
                db.remove(link);
            } else {
                db.insert(link.to_owned(), old);
            }
        }
        match self.save(&db) {
            Ok(()) => Ok(true),
            Err(e) => {
                *db = before;
                Err(e)
            }
        }
    }

    /// Names only (shown in the tree).
    pub fn names(&self, link: &str) -> Vec<String> {
        self.lock()
            .get(link)
            .map(|m| m.keys().cloned().collect())
            .unwrap_or_default()
    }

    /// The secrets of one link, for delivery over a protected channel.
    pub fn for_link(&self, link: &str) -> BTreeMap<String, Zeroizing<Vec<u8>>> {
        self.lock().get(link).cloned().unwrap_or_default()
    }
}

/// Names that say a value is a secret.
const WORDS: &[&str] = &[
    "password",
    "passwd",
    "passphrase",
    "secret",
    "token",
    "private_key",
    "api_key",
    "apikey",
    "credential",
    "key_pem",
];

/// `true` for a field name that says its value is a secret.
pub fn secret_name(name: &str) -> bool {
    let lk = name.to_ascii_lowercase();
    WORDS.iter().any(|w| lk.contains(w)) || lk == "key" || lk.ends_with("_key")
}

/// What stands for a masked secret.
pub const MASK: &str = "***";

/// Parts of a word of a field name that say its value is a secret in a
/// configuration copy: a word that starts or ends with one is masked
/// (`authpass`, `passwd`, `dbpassword`, `apitoken`), unless it is one of
/// [`MASK_NOT`]. Wider than the lint of an install on purpose: a name masked
/// for nothing costs a reader one value of a copy that is never restored; a
/// name missed leaves a secret in a file that travels.
const MASK_PARTS: &[&str] = &[
    "pass",
    "pwd",
    "psk",
    "pin",
    "sas",
    "secret",
    "token",
    "credential",
    "community",
    "signature",
    "bearer",
    "cookie",
    "authorization",
];

/// Whole words that are masked.
const MASK_WORDS: &[&str] = &["key", "sig", "dsn", "auth", "cert", "jwt", "otp"];

/// Words that start or end with a part of [`MASK_PARTS`] and name no
/// secret. Everything else that matches is masked.
const MASK_NOT: &[&str] = &[
    "passes",
    "passed",
    "passing",
    "passive",
    "passthrough",
    "bypass",
    "compass",
    "ping",
    "pings",
    "pinned",
    "pinning",
    "pinout",
    "spin",
];

/// The words of a field name, lower case: split at what is no letter or
/// digit and where a lower case letter or a digit is followed by an upper
/// case one (`authPass`, `apiKey`, `dbPassword`).
fn name_words(name: &str) -> Vec<String> {
    let mut words = vec![String::new()];
    let mut prev_lower = false;
    for c in name.chars() {
        if !c.is_ascii_alphanumeric() {
            words.push(String::new());
            prev_lower = false;
            continue;
        }
        if c.is_ascii_uppercase() && prev_lower {
            words.push(String::new());
        }
        prev_lower = c.is_ascii_lowercase() || c.is_ascii_digit();
        if let Some(w) = words.last_mut() {
            w.push(c.to_ascii_lowercase());
        }
    }
    words.retain(|w| !w.is_empty());
    words
}

/// `true` for a field name whose value [`mask_config`] masks.
pub fn masked_name(name: &str) -> bool {
    let words = name_words(name);
    // the lint's names, also for a name written in camel case
    if secret_name(name) || secret_name(&words.join("_")) {
        return true;
    }
    let joined = words.concat();
    if joined.contains("connectionstring") || joined.contains("connstr") {
        return true;
    }
    words.iter().any(|w| {
        MASK_WORDS.contains(&w.as_str())
            || (!MASK_NOT.contains(&w.as_str())
                && MASK_PARTS
                    .iter()
                    .any(|p| w.starts_with(p) || w.ends_with(p)))
    })
}

/// A URL with its whole userinfo masked (`scheme://***@host…`): a user and
/// password, or a user or token alone. The userinfo ends at the last `@`
/// of the authority. A password with `/`, `?`, `#` or `@` in it (not
/// escaped) hides where the authority ends, so when a `:` stands before
/// the last `@` of the whole text, that `@` is taken. This may mask a host
/// and a path with an `@` further on: the copy is for people, and what is
/// masked for nothing costs nothing. `None` when the text has no userinfo.
fn mask_userinfo(s: &str) -> Option<String> {
    let scheme = s.find("://")? + 3;
    let rest = &s[scheme..];
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let at = match rest.rfind('@') {
        // `user:password@`: the password may hold `/`, `?`, `#` or `@`
        Some(last) if rest[..last].contains(':') => last,
        _ => rest[..end].rfind('@')?,
    };
    Some(format!("{}{MASK}{}", &s[..scheme], &rest[at..]))
}

/// `name=value` pairs of a text (a URL's query and fragment, a SAS token, a
/// connection string: pairs parted by `&`, `;`, `?` or `#`; the name is the
/// last word before the `=`, the value goes to the next of them, spaces too)
/// with the value masked where the name says it is a secret
/// ([`masked_name`]: `sig`, `token`, `password`, `key`, `Pwd`,
/// `SharedAccessKey`, …). `None` when nothing was masked.
fn mask_pairs(s: &str) -> Option<String> {
    let sep = |c: char| matches!(c, '&' | ';' | '?' | '#');
    let mut out = String::with_capacity(s.len());
    let mut changed = false;
    let mut rest = s;
    loop {
        let end = rest.find(sep).unwrap_or(rest.len());
        let piece = &rest[..end];
        match piece.split_once('=') {
            Some((name, value))
                if !value.is_empty()
                    && value != MASK
                    && masked_name(name.rsplit(char::is_whitespace).next().unwrap_or(name)) =>
            {
                out.push_str(name);
                out.push('=');
                out.push_str(MASK);
                changed = true;
            }
            _ => out.push_str(piece),
        }
        match rest[end..].chars().next() {
            Some(c) => {
                out.push(c);
                rest = &rest[end + c.len_utf8()..];
            }
            None => break,
        }
    }
    changed.then_some(out)
}

/// A text of a configuration with the secrets inside it masked: the
/// userinfo of a URL and the secret pairs of a query, a SAS token or a
/// connection string.
fn mask_text(s: &str) -> Option<String> {
    let url = mask_userinfo(s);
    let pairs = mask_pairs(url.as_deref().unwrap_or(s));
    pairs.or(url)
}

/// A configuration as JSON with every secret masked, for the `config`
/// section of a backup (ADR 0048 §3.2): the value of a field named like a
/// secret ([`masked_name`]; whatever its type), a PEM private key, the
/// userinfo of a URL, the secret pairs of a query, SAS token or connection
/// string, and a long hex string wherever it is, except under `admin_keys`
/// (public keys). The names are the only guide here: the
/// configuration holds bootstrap params, and what a driver declares as
/// `secret` is entered at runtime and sealed, never written to this file.
pub fn mask_config(v: &mut serde_json::Value) {
    fn walk(v: &mut serde_json::Value, public: bool) {
        match v {
            serde_json::Value::Object(m) => {
                for (k, v) in m.iter_mut() {
                    if masked_name(k) {
                        *v = serde_json::Value::String(MASK.into());
                    } else {
                        walk(v, k == "admin_keys");
                    }
                }
            }
            serde_json::Value::Array(a) => a.iter_mut().for_each(|v| walk(v, public)),
            serde_json::Value::String(s) => {
                let hex = s.len() >= 32 && s.chars().all(|c| c.is_ascii_hexdigit());
                if s.contains("PRIVATE KEY-----") || (hex && !public) {
                    *s = MASK.into();
                } else if let Some(masked) = mask_text(s) {
                    *s = masked;
                }
            }
            _ => {}
        }
    }
    walk(v, false);
}

/// Lint at install (wiki: "params ... looks like a password/key → move to
/// secrets"): keys named like secrets, or long hex strings.
pub fn lint_params(v: &Value, path: &str) -> Result<(), String> {
    match v {
        Value::Map(m) => {
            for (k, v) in m {
                let p = format!("{path}.{k}");
                if secret_name(k) {
                    return Err(format!(
                        "{p}: looks like a secret; use links/<id>/~act/set_secret"
                    ));
                }
                lint_params(v, &p)?;
            }
        }
        Value::Array(a) => {
            for (i, v) in a.iter().enumerate() {
                lint_params(v, &format!("{path}[{i}]"))?;
            }
        }
        Value::Str(s) if s.contains("PRIVATE KEY-----") => {
            return Err(format!(
                "{path}: a PEM private key; enter it in the link's add/edit action or use links/<id>/~act/set_secret"
            ));
        }
        Value::Str(s) if s.len() >= 32 && s.chars().all(|c| c.is_ascii_hexdigit()) => {
            return Err(format!(
                "{path}: looks like a key (long hex); use links/<id>/~act/set_secret"
            ));
        }
        _ => {}
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-secrets-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn a_config_copy_has_no_secret_in_clear() {
        let mut v = serde_json::json!({
            "site": "plant",
            "admin_keys": ["aa".repeat(32)],
            "gateway": { "tls_key": "/etc/wyrm/gw.key", "listen": "0.0.0.0:8445" },
            "uplink": { "upstreams": [{ "name": "x", "password": "hunter2", "url": "mqtts://b" }] },
            "links": { "plc": { "params": { "api_token": { "v": "t0k" }, "psk": "bb".repeat(16) } } },
            "peers": { "upstream": [{ "site": "c", "key": "-----BEGIN PRIVATE KEY-----x" }] },
            "note": "-----BEGIN EC PRIVATE KEY-----\nabc",
        });
        mask_config(&mut v);
        let text = v.to_string();
        for secret in [
            "hunter2",
            "t0k",
            "/etc/wyrm/gw.key",
            "PRIVATE KEY",
            &"bb".repeat(16),
        ] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
        // what is not a secret stays: the site, the listener, the public keys
        assert_eq!(v["site"], "plant");
        assert_eq!(v["gateway"]["listen"], "0.0.0.0:8445");
        assert_eq!(v["admin_keys"][0], "aa".repeat(32));
        assert_eq!(v["uplink"]["upstreams"][0]["password"], MASK);
        assert!(secret_name("Passphrase") && secret_name("state_key") && !secret_name("keep_days"));
    }

    /// Review of PR 72: names a link's params use for secrets that the lint
    /// of an install does not know, and a password inside a URL.
    #[test]
    fn a_config_copy_masks_the_names_links_use_for_secrets() {
        let mut v = serde_json::json!({
            "links": {
                "snmp": { "params": {
                    "community": "c0mmunity",
                    "auth_pass": "authpass1",
                    "priv_pass": "privpass1",
                    "port": 161,
                    "pinned": true,
                    "ping_s": 5,
                    "passes": 3,
                } },
                "azure": { "params": { "sas": "SharedAccessSignature sr=x", "hub": "h" } },
                "s3": { "params": { "secret_key": "s3cr3tkey", "access_key": "AKIAEXAMPLE" } },
                "db": { "params": {
                    "url": "postgres://wyrm:pgpass1@db.example:5432/hist?sslmode=require",
                    "plain_url": "https://broker.example:8445/mcp",
                    "connection_string": "Server=x;Pwd=cs-pass",
                    "pin": "4711",
                } },
            },
        });
        mask_config(&mut v);
        let text = v.to_string();
        for secret in [
            "c0mmunity",
            "authpass1",
            "privpass1",
            "SharedAccessSignature",
            "s3cr3tkey",
            "AKIAEXAMPLE",
            "pgpass1",
            "cs-pass",
            "4711",
        ] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
        let p = &v["links"]["snmp"]["params"];
        assert_eq!(
            (&p["port"], &p["pinned"], &p["ping_s"]),
            (&161.into(), &true.into(), &5.into())
        );
        assert_eq!(p["passes"], 3, "a word, not a part of one");
        assert_eq!(v["links"]["azure"]["params"]["hub"], "h");
        let db = &v["links"]["db"]["params"];
        assert_eq!(
            db["url"],
            "postgres://***@db.example:5432/hist?sslmode=require"
        );
        assert_eq!(db["plain_url"], "https://broker.example:8445/mcp");
        // the lint of an install keeps its own, narrower list
        assert!(!secret_name("community") && masked_name("community"));
    }

    /// Automated review of the mask: names in camel case or written as one
    /// word, a URL with a token alone or a password with `/` and `#` in it,
    /// and the secret parts of a query or a SAS token.
    #[test]
    fn a_config_copy_masks_joined_names_and_what_is_inside_a_text() {
        for name in [
            "authPass",
            "apiKey",
            "privpass",
            "dbPassword",
            "AuthPass",
            "authpass",
            "privPass",
            "clientSecret",
            "accessToken",
            "apitoken",
            "SharedAccessKey",
            "AccountKey",
            "tlsKey",
            "sasToken",
            "pinCode",
            "userPwd",
            "sig",
            "x-api-key",
            "connStr",
            "connectionString",
            "mqttPassword",
            "PSK",
            "passwd2",
        ] {
            assert!(masked_name(name), "{name}");
        }
        for name in [
            "passes",
            "pinned",
            "ping_s",
            "pingMs",
            "bypass",
            "keep_days",
            "port",
            "host",
            "site",
            "listen",
            "url",
            "rate_hz",
            "admin_keys",
            "max_mb",
            "points",
        ] {
            assert!(!masked_name(name), "{name}");
        }
        assert_eq!(name_words("dbPassword2Hash"), ["db", "password2", "hash"]);
        assert_eq!(name_words("x-API_key"), ["x", "api", "key"]);

        let masked = |text: &str| {
            let mut v = serde_json::json!({ "v": text });
            mask_config(&mut v);
            v["v"].as_str().unwrap().to_owned()
        };
        // a token alone, a user alone, a user and a password
        assert_eq!(
            masked("https://t0ken123@host/path"),
            "https://***@host/path"
        );
        assert_eq!(
            masked("mqtts://user@broker:8883"),
            "mqtts://***@broker:8883"
        );
        assert_eq!(masked("amqp://u:pw@h:5672/vh"), "amqp://***@h:5672/vh");
        // a password with `/`, `?`, `#` and `@` in it
        for url in [
            "postgres://wyrm:pa/ss#1@db.example:5432/hist",
            "postgres://wyrm:pa?ss@db.example:5432/hist",
            "postgres://wyrm:p@ss/w#rd@db.example:5432/hist",
        ] {
            assert_eq!(masked(url), "postgres://***@db.example:5432/hist", "{url}");
        }
        // no userinfo: as it is
        for url in [
            "https://broker.example:8445/mcp",
            "https://host/users/list",
            "tcp/127.0.0.1:7447",
            "quic/central.example:7448",
        ] {
            assert_eq!(masked(url), url);
        }
        // the secret parts of a query, of a fragment and of a SAS token
        assert_eq!(
            masked("https://acct.blob.core.windows.net/c?sv=2022-11-02&se=2027-01-01&sr=c&sp=rw&sig=AbC%2Fd%3D"),
            "https://acct.blob.core.windows.net/c?sv=2022-11-02&se=2027-01-01&sr=c&sp=rw&sig=***"
        );
        assert_eq!(
            masked("https://api.example/v1?token=t0k&page=2&api_key=k3y#access_token=zzz"),
            "https://api.example/v1?token=***&page=2&api_key=***#access_token=***"
        );
        assert_eq!(
            masked("SharedAccessSignature sr=hub.example&sig=s1g&se=1790000000&skn=owner"),
            "SharedAccessSignature sr=hub.example&sig=***&se=1790000000&skn=owner"
        );
        assert_eq!(
            masked("HostName=h.example;SharedAccessKeyName=owner;SharedAccessKey=abc="),
            "HostName=h.example;SharedAccessKeyName=***;SharedAccessKey=***"
        );
        assert_eq!(
            masked("Server=db;User Id=wyrm;Password=p w;Pwd=x"),
            "Server=db;User Id=wyrm;Password=***;Pwd=***"
        );
        // both in one text
        assert_eq!(
            masked("https://u:p@h/x?password=pw&q=1"),
            "https://***@h/x?password=***&q=1"
        );
        assert_eq!(
            masked("a plain note, no secret = none"),
            "a plain note, no secret = none"
        );
    }

    /// Review ADM-7: only a missing file is an empty store.
    #[test]
    fn an_unreadable_store_fails_the_open() {
        let d = dir("unreadable");
        assert!(SecretStore::open(&d).is_ok(), "missing = empty");
        std::fs::create_dir_all(d.join("secrets.bin")).unwrap();
        assert!(SecretStore::open(&d).is_err());
    }

    #[test]
    fn roundtrip_encrypted_at_rest() {
        let d = dir("rt");
        let s = SecretStore::open(&d).unwrap();
        s.set("dlms", "ek", b"0011223344").unwrap();
        s.set("dlms", "ak", b"secret-ak").unwrap();
        drop(s);
        let raw = std::fs::read(d.join("secrets.bin")).unwrap();
        assert!(
            !raw.windows(9).any(|w| w == b"secret-ak"),
            "not plaintext on disk"
        );
        let s = SecretStore::open(&d).unwrap();
        assert_eq!(s.names("dlms"), ["ak", "ek"]);
        assert_eq!(&**s.for_link("dlms").get("ak").unwrap(), b"secret-ak");
        assert!(s.remove("dlms", "ak").unwrap());
        // tampering is detected
        let mut raw = std::fs::read(d.join("secrets.bin")).unwrap();
        let last = raw.len() - 1;
        raw[last] ^= 1;
        std::fs::write(d.join("secrets.bin"), raw).unwrap();
        assert!(SecretStore::open(&d).is_err());
    }

    #[test]
    fn params_lint() {
        let ok = Value::Map(BTreeMap::from([("host".into(), Value::from("10.0.0.1"))]));
        assert!(lint_params(&ok, "params").is_ok());
        for bad in ["password", "api_key", "dlms_key", "Secret", "key_pem"] {
            let v = Value::Map(BTreeMap::from([(bad.to_owned(), Value::from("x"))]));
            assert!(lint_params(&v, "params").is_err(), "{bad}");
        }
        let hex = Value::Map(BTreeMap::from([(
            "x".into(),
            Value::from("00112233445566778899aabbccddeeff"),
        )]));
        assert!(lint_params(&hex, "params").is_err());
        let pem = Value::Map(BTreeMap::from([(
            "client".into(),
            Value::from("-----BEGIN PRIVATE KEY-----\nMC4\n-----END PRIVATE KEY-----\n"),
        )]));
        assert!(lint_params(&pem, "params").is_err());
        // certificates are public
        let cert = Value::Map(BTreeMap::from([(
            "ca_pem".into(),
            Value::from("-----BEGIN CERTIFICATE-----\nMC4\n-----END CERTIFICATE-----\n"),
        )]));
        assert!(lint_params(&cert, "params").is_ok());
    }
}
