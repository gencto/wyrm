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

/// Parts of a word of a field name that say its value is a secret: a word
/// that starts or ends with one (`authpass`, `privkey`, `accesskey`,
/// `apitoken`), unless it is one of [`MASK_NOT`]. This is the second net of
/// [`mask_config`], never its only guard: there, what is not on the list of
/// fields to show is masked whatever its name.
const MASK_PARTS: &[&str] = &[
    "pass",
    "pwd",
    "psk",
    "pin",
    "sas",
    "key",
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
const MASK_WORDS: &[&str] = &["sig", "dsn", "auth", "jwt", "otp"];

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
    "keys",
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

/// `true` for a field name that says its value is a secret.
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

/// A URL (`scheme://…`) with what may hold a secret masked whole: its
/// userinfo (`scheme://***@host…`: a user and password, or a user or token
/// alone) and all of its query and fragment (`?***`, `#***`). The userinfo
/// ends at the last `@` of the authority; a password with `/`, `?`, `#` or
/// `@` in it (not escaped) hides where the authority ends, so when a `:`
/// stands before the last `@` of the whole text, that `@` is taken. `None`
/// when nothing was masked.
fn mask_url(s: &str) -> Option<String> {
    let scheme = s.find("://")? + 3;
    let rest = &s[scheme..];
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let at = match rest.rfind('@') {
        Some(last) if rest[..last].contains(':') => Some(last),
        _ => rest[..end].rfind('@'),
    };
    let (user, tail) = match at {
        Some(at) => (MASK, &rest[at..]),
        None => ("", rest),
    };
    let (kept, cut) = match tail.find(['?', '#']) {
        Some(q) => (&tail[..q], Some(&tail[q..q + 1])),
        None => (tail, None),
    };
    if at.is_none() && cut.is_none() {
        return None;
    }
    let mut out = format!("{}{user}{kept}", &s[..scheme]);
    if let Some(mark) = cut {
        out.push_str(mark);
        out.push_str(MASK);
    }
    Some(out)
}

/// Does the key path `path` match `pattern` (`a.b.c`, `*` for any one key)?
fn path_matches(path: &[&str], pattern: &str) -> bool {
    let mut n = 0;
    for part in pattern.split('.') {
        match path.get(n) {
            Some(key) if part == "*" || part == *key => n += 1,
            _ => return false,
        }
    }
    n == path.len()
}

/// A configuration as JSON for the `config` section of a backup (ADR 0048
/// §3.2): a copy for people to read, never restored. **Masked by default,
/// shown by list.** A text is kept only when its key path (map keys from
/// the top, joined by `.`; the entries of an array have the array's path)
/// matches an entry of `shown` (`*` for any one key): the fields known to
/// hold no secret. Every other text is replaced by the mask, whole: every
/// text under a link's `params`, under a section this broker does not know,
/// free text. Nothing is parsed for `name=value` pieces.
///
/// A second net under the list, never the only guard: a shown text that is a
/// URL has its userinfo and its whole query and fragment masked
/// ([`mask_url`]); a PEM private key is masked wherever it is; and a value
/// that is a number or a shown text under a name that says secret
/// ([`masked_name`]) is masked. Other numbers, and every flag, are kept.
pub fn mask_config(v: &mut serde_json::Value, shown: &[&str]) {
    fn walk<'a>(v: &'a mut serde_json::Value, path: &mut Vec<&'a str>, shown: &[&str]) {
        let named_secret = path.last().is_some_and(|k| masked_name(k));
        match v {
            serde_json::Value::Object(m) => {
                for (k, v) in m.iter_mut() {
                    path.push(k.as_str());
                    walk(v, path, shown);
                    path.pop();
                }
            }
            serde_json::Value::Array(a) => a.iter_mut().for_each(|v| walk(v, path, shown)),
            serde_json::Value::String(s) => {
                let listed = shown.iter().any(|p| path_matches(path, p));
                if !listed || named_secret || s.contains("PRIVATE KEY-----") {
                    *s = MASK.into();
                } else if let Some(masked) = mask_url(s) {
                    *s = masked;
                }
            }
            // a flag is no secret, whatever its name (`export_secrets`)
            serde_json::Value::Null | serde_json::Value::Bool(_) => {}
            other => {
                if named_secret {
                    *other = serde_json::Value::String(MASK.into());
                }
            }
        }
    }
    walk(v, &mut Vec::new(), shown);
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

    /// The fields a test configuration shows.
    const SHOWN: &[&str] = &[
        "site",
        "admin_keys",
        "listen",
        "gateway.listen",
        "gateway.mcp.public_url",
        "packages.repository",
        "links.*.driver",
        "peers.upstream.site",
        "peers.upstream.endpoint",
        "peers.upstream.key",
    ];

    #[test]
    fn a_config_copy_has_no_secret_in_clear() {
        let mut v = serde_json::json!({
            "site": "plant",
            "admin_keys": ["aa".repeat(32)],
            "gateway": { "tls_key": "/etc/wyrm/gw.key", "listen": "0.0.0.0:8445" },
            "uplink": { "upstreams": [{ "name": "x", "password": "hunter2", "url": "mqtts://b" }] },
            "links": { "plc": { "driver": "modbus", "params": {
                "api_token": { "v": "t0k" }, "psk": "bb".repeat(16), "points": 8, "pin": 4711,
            } } },
            "peers": { "upstream": [{ "site": "c", "key": "-----BEGIN PRIVATE KEY-----x" }] },
            "note": "-----BEGIN EC PRIVATE KEY-----\nabc",
        });
        mask_config(&mut v, SHOWN);
        let text = v.to_string();
        for secret in [
            "hunter2",
            "t0k",
            "/etc/wyrm/gw.key",
            "PRIVATE KEY",
            &"bb".repeat(16),
            "mqtts",
            "4711",
        ] {
            assert!(!text.contains(secret), "{secret} in {text}");
        }
        // what is on the list stays: the site, the listener, the public keys
        assert_eq!(v["site"], "plant");
        assert_eq!(v["gateway"]["listen"], "0.0.0.0:8445");
        assert_eq!(v["admin_keys"][0], "aa".repeat(32));
        assert_eq!(v["links"]["plc"]["driver"], "modbus");
        assert_eq!(v["peers"]["upstream"][0]["site"], "c");
        // names stay (they are the map's keys), numbers too
        assert_eq!(v["uplink"]["upstreams"][0]["name"], MASK);
        assert_eq!(v["uplink"]["upstreams"][0]["password"], MASK);
        assert_eq!(v["links"]["plc"]["params"]["points"], 8);
        // a number under a name that says secret; a listed field under one
        assert_eq!(v["links"]["plc"]["params"]["pin"], MASK);
        assert_eq!(v["peers"]["upstream"][0]["key"], MASK);
        assert!(secret_name("Passphrase") && secret_name("state_key") && !secret_name("keep_days"));
    }

    /// Automated review of the first two masks (a list of names to hide
    /// keeps leaking): the copy is masked by default. Whatever a text
    /// outside the list of fields to show holds, in whatever form, it is
    /// not in the copy.
    #[test]
    fn a_config_copy_shows_only_what_is_on_the_list() {
        let secrets = [
            ("note", "Password = hunter2a"),
            ("conninfo", "host=db.example user=wyrm password=hunter2b"),
            ("privkey", "hunter2c"),
            ("accesskey", "hunter2d"),
            ("PRIVKEY", "hunter2e"),
            ("unknown_field", "hunter2f"),
            ("community", "hunter2g"),
            ("url", "postgres://wyrm:hunter2h@db.example/hist"),
            ("sasText", "SharedAccessSignature sr=x&sig=hunter2i"),
            ("x", "Server=db;Pwd=hunter2j"),
        ];
        let params: serde_json::Map<String, serde_json::Value> = secrets
            .iter()
            .map(|(k, v)| ((*k).to_owned(), serde_json::Value::from(*v)))
            .collect();
        let mut v = serde_json::json!({
            "site": "plant",
            "links": { "l1": { "driver": "snmp", "params": params.clone() } },
            // a section this broker does not know, a secret list, nested maps
            "future_section": { "a": { "b": ["hunter2k", { "c": "hunter2l" }] } },
            "secrets": { "l1": { "password": "hunter2m" } },
            "uplink": { "upstreams": [params] },
        });
        mask_config(&mut v, SHOWN);
        let text = v.to_string();
        assert!(!text.contains("hunter2"), "{text}");
        assert!(!text.contains("db.example"), "{text}");
        // every text of the params is the mask, whole; its names stay
        let p = v["links"]["l1"]["params"].as_object().unwrap();
        assert_eq!(p.len(), secrets.len());
        assert!(p.values().all(|v| v == MASK), "{p:?}");
        assert_eq!(v["site"], "plant");
        assert_eq!(v["links"]["l1"]["driver"], "snmp");
        // nothing is shown without a list
        let mut all = serde_json::json!({ "site": "plant", "n": 1, "on": true, "none": null });
        mask_config(&mut all, &[]);
        assert_eq!(
            all,
            serde_json::json!({ "site": MASK, "n": 1, "on": true, "none": null })
        );
        // a path is matched whole: no prefix, no suffix
        assert!(path_matches(&["links", "l1", "driver"], "links.*.driver"));
        assert!(!path_matches(
            &["links", "l1", "params", "driver"],
            "links.*.driver"
        ));
        assert!(!path_matches(&["links", "l1"], "links.*.driver"));
        assert!(!path_matches(&["x", "site"], "site"));
    }

    /// The second net: names that say secret, in camel case or written as
    /// one word, and the short list of words that only look like one.
    #[test]
    fn names_that_say_secret() {
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
            "privkey",
            "accesskey",
            "PRIVKEY",
            "community",
            "auth_pass",
            "sas",
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
        // the lint of an install keeps its own, narrower list
        assert!(!secret_name("community"));
    }

    /// A shown text that is a URL: the userinfo and the whole query and
    /// fragment are masked.
    #[test]
    fn a_shown_url_has_no_userinfo_and_no_query() {
        let masked = |text: &str| {
            let mut v = serde_json::json!({ "packages": { "repository": text } });
            mask_config(&mut v, SHOWN);
            v["packages"]["repository"].as_str().unwrap().to_owned()
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
        // the query and the fragment go whole, whatever their names are
        assert_eq!(
            masked("https://acct.blob.core.windows.net/c?sv=2022-11-02&sr=c&sig=AbC%2Fd%3D"),
            "https://acct.blob.core.windows.net/c?***"
        );
        assert_eq!(
            masked("https://api.example/v1?page=2#access_token=zzz"),
            "https://api.example/v1?***"
        );
        assert_eq!(masked("https://h/x#frag"), "https://h/x#***");
        assert_eq!(
            masked("https://u:p@h/x?password=pw&q=1"),
            "https://***@h/x?***"
        );
        // nothing to mask: as it is
        for url in [
            "https://repo.example/index.json",
            "https://host:8445/links/index.json",
            "official",
        ] {
            assert_eq!(masked(url), url);
        }
        // a PEM key in a shown field
        assert_eq!(masked("-----BEGIN PRIVATE KEY-----\nabc"), MASK);
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
