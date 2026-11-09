//! Who may talk to a bot (ADR 0039). Deny by default; a chat account becomes a user only by
//! pairing: an operator invites a named user (level, keys), the link shows a one-time code once,
//! the person sends `/start <code>` to the bot in a private chat, and the bot binds that
//! account's numeric id. Codes are kept as SHA-256, expire, are single use, and wrong ones are
//! counted per account. Every command then runs within three bounds at once: the user's own
//! level and keys, the rights of the operator who invited or last edited it (ADR 0029), and the
//! link's grants (checked by the host).

use sha2::{Digest, Sha256};

/// A pairing code lives this long.
pub const CODE_TTL_US: u64 = 15 * 60 * 1_000_000;
/// Wrong codes an account may send before it is ignored for [`LOCKOUT_US`].
pub const MAX_BAD_CODES: u32 = 5;
pub const LOCKOUT_US: u64 = 60 * 60 * 1_000_000;
/// An unknown account hears "not authorized" at most this often.
pub const NAG_EVERY_US: u64 = 60 * 60 * 1_000_000;

/// Crockford base32: no I, L, O, U.
const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
pub const CODE_LEN: usize = 10;

/// A code of [`CODE_LEN`] characters (50 bits) from `random` (at least 7 bytes), shown as
/// `XXXXX-XXXXX`.
pub fn new_code(random: &[u8]) -> Option<String> {
    if random.len() < 7 {
        return None;
    }
    let mut bits: u64 = 0;
    for b in &random[..7] {
        bits = (bits << 8) | u64::from(*b);
    }
    let mut out = String::with_capacity(CODE_LEN + 1);
    for i in 0..CODE_LEN {
        if i == 5 {
            out.push('-');
        }
        let idx = ((bits >> (5 * (CODE_LEN - 1 - i))) & 31) as usize;
        out.push(ALPHABET[idx] as char);
    }
    Some(out)
}

/// The code as typed, read leniently: case, dashes and spaces do not matter, O is 0, I and L are 1.
pub fn normalize(code: &str) -> String {
    code.chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
        .map(|c| match c.to_ascii_uppercase() {
            'O' => '0',
            'I' | 'L' => '1',
            c => c,
        })
        .collect()
}

pub fn hash_code(code: &str) -> String {
    let d = Sha256::digest(normalize(code).as_bytes());
    d.iter().map(|b| format!("{b:02x}")).collect()
}

/// Constant-time comparison of two hashes.
pub fn same(a: &str, b: &str) -> bool {
    a.len() == b.len()
        && a.bytes()
            .zip(b.bytes())
            .fold(0u8, |acc, (x, y)| acc | (x ^ y))
            == 0
}

/// A command sent to a bot: `/name args` or `/name@bot args`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Command {
    pub name: String,
    pub args: String,
}

/// The command in `text`, or `None` for plain text and commands to another bot (`/x@other`).
pub fn parse_command(text: &str, bot_username: Option<&str>) -> Option<Command> {
    let text = text.trim();
    let rest = text.strip_prefix('/')?;
    let (head, args) = match rest.split_once(char::is_whitespace) {
        Some((h, a)) => (h, a.trim()),
        None => (rest, ""),
    };
    let (name, to) = match head.split_once('@') {
        Some((n, b)) => (n, Some(b)),
        None => (head, None),
    };
    if let (Some(to), Some(me)) = (to, bot_username) {
        if !to.eq_ignore_ascii_case(me) {
            return None;
        }
    }
    if name.is_empty()
        || name.len() > 32
        || !name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
    {
        return None;
    }
    Some(Command {
        name: name.to_ascii_lowercase(),
        args: args.to_owned(),
    })
}

/// A command's key as typed: full (`wy/<site>/…`) or below the site (`downstream/plc/t1`).
pub fn full_key(arg: &str, site: Option<&str>) -> Result<String, String> {
    let arg = arg.trim().trim_matches('/');
    let key = if arg.starts_with("wy/") {
        arg.to_owned()
    } else {
        let site = site.ok_or("a full key, wy/<site>/…")?;
        format!("wy/{site}/{arg}")
    };
    crate::model::check_key(&key)?;
    Ok(key)
}

/// A value typed in a chat: a number, `true`/`false`, `null`, or text (quotes optional).
pub fn typed_value(s: &str) -> wyrm_core::Value {
    use wyrm_core::Value;
    let s = s.trim();
    match s {
        "true" => return Value::Bool(true),
        "false" => return Value::Bool(false),
        "null" => return Value::Null,
        _ => {}
    }
    if let Ok(i) = s.parse::<i64>() {
        return Value::Int(i);
    }
    if let Ok(f) = s.parse::<f64>() {
        if f.is_finite() {
            return Value::Float(f);
        }
    }
    let unq = s
        .strip_prefix('"')
        .and_then(|x| x.strip_suffix('"'))
        .unwrap_or(s);
    Value::Str(unq.to_owned())
}

/// Commands per minute per account: a token bucket.
#[derive(Debug, Clone, Copy)]
pub struct Bucket {
    tokens: f64,
    at_us: u64,
}

impl Bucket {
    pub fn new(per_min: u64, now: u64) -> Self {
        Self {
            tokens: per_min as f64,
            at_us: now,
        }
    }

    /// One command now; `false` when the account is over its rate.
    pub fn take(&mut self, per_min: u64, now: u64) -> bool {
        let cap = per_min as f64;
        let dt = now.saturating_sub(self.at_us) as f64 / 60_000_000.0;
        self.tokens = (self.tokens + dt * cap).min(cap);
        self.at_us = now;
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_are_typed_leniently_and_hashed() {
        let c = new_code(&[0xde, 0xad, 0xbe, 0xef, 0x01, 0x02, 0x03]).unwrap();
        assert_eq!(c.len(), CODE_LEN + 1);
        assert_eq!(&c[5..6], "-");
        assert!(c.chars().all(|x| x == '-' || ALPHABET.contains(&(x as u8))));
        assert_eq!(
            hash_code(&c),
            hash_code(&c.to_lowercase().replace('-', " "))
        );
        assert_eq!(normalize("o1l-i"), "0111");
        assert!(new_code(&[1, 2]).is_none());
        assert!(same(&hash_code("A"), &hash_code("a")));
        assert!(!same(&hash_code("A"), &hash_code("B")));
    }

    #[test]
    fn commands_are_parsed() {
        assert_eq!(
            parse_command("/get downstream/plc/t1", Some("plant_bot")),
            Some(Command {
                name: "get".into(),
                args: "downstream/plc/t1".into()
            })
        );
        assert_eq!(
            parse_command("/Help@Plant_Bot", Some("plant_bot"))
                .unwrap()
                .name,
            "help"
        );
        assert_eq!(parse_command("/help@other_bot", Some("plant_bot")), None);
        assert_eq!(parse_command("hello", None), None);
        assert_eq!(parse_command("/", None), None);
    }

    #[test]
    fn keys_and_values_from_a_chat() {
        assert_eq!(
            full_key("downstream/plc/t1", Some("s")).unwrap(),
            "wy/s/downstream/plc/t1"
        );
        assert_eq!(
            full_key("wy/edge/downstream/x", Some("s")).unwrap(),
            "wy/edge/downstream/x"
        );
        assert!(full_key("downstream/**", Some("s")).is_err());
        assert!(full_key("downstream/../sys", Some("s")).is_err());
        use wyrm_core::Value;
        assert_eq!(typed_value("42"), Value::Int(42));
        assert_eq!(typed_value("2.5"), Value::Float(2.5));
        assert_eq!(typed_value("true"), Value::Bool(true));
        assert_eq!(typed_value("\"on\""), Value::Str("on".into()));
        assert_eq!(typed_value("NaN"), Value::Str("NaN".into()));
    }

    #[test]
    fn the_bucket_refills() {
        let mut b = Bucket::new(2, 0);
        assert!(b.take(2, 0));
        assert!(b.take(2, 0));
        assert!(!b.take(2, 0));
        assert!(b.take(2, 30_000_000));
    }
}
