//! Names people read (ADR 0042, spec 02 0.2.28).
//!
//! A key (`add_device`, `timeout_ms`) is a wire name: it is a key segment or
//! an `args` name and never changes for style. What a person sees is the
//! `display` of the action or parameter. This module holds the one rule for
//! both sides: [`humanize`] derives a `display` from a key (the responder
//! SDK fills a missing `display` with it, a client does the same for a
//! responder that sent none), and [`check`] says whether a text follows the
//! style, so tests can hold every link to it.
//!
//! The style: sentence case, short, no trailing dot, acronyms upper case
//! (`URL`, `ID`), units in brackets at the end (`Timeout (ms)`).

use crate::meta::ActionMeta;

/// Key tokens that are not written as plain lower-case words: acronyms and
/// names. A text may use each written form anywhere.
pub const WORDS: &[(&str, &str)] = &[
    ("acl", "ACL"),
    ("aes", "AES"),
    ("ahu", "AHU"),
    ("apdu", "APDU"),
    ("api", "API"),
    ("aws", "AWS"),
    ("azure", "Azure"),
    ("bacnet", "BACnet"),
    ("bbmd", "BBMD"),
    ("ca", "CA"),
    ("cbor", "CBOR"),
    ("cel", "CEL"),
    ("cpu", "CPU"),
    ("crc", "CRC"),
    ("csr", "CSR"),
    ("csv", "CSV"),
    ("db", "DB"),
    ("dns", "DNS"),
    ("dql", "DQL"),
    ("dsa", "DSA"),
    ("fc", "FC"),
    ("gzip", "gzip"),
    ("hmac", "HMAC"),
    ("html", "HTML"),
    ("http", "HTTP"),
    ("https", "HTTPS"),
    ("id", "ID"),
    ("ids", "IDs"),
    ("io", "I/O"),
    ("iot", "IoT"),
    ("ip", "IP"),
    ("json", "JSON"),
    ("jwt", "JWT"),
    ("llm", "LLM"),
    ("mac", "MAC"),
    ("mcp", "MCP"),
    ("modbus", "Modbus"),
    ("mqtt", "MQTT"),
    ("mtls", "mTLS"),
    ("oauth", "OAuth"),
    ("oid", "OID"),
    ("oids", "OIDs"),
    ("opcua", "OPC UA"),
    ("pdu", "PDU"),
    ("pem", "PEM"),
    ("pki", "PKI"),
    ("plc", "PLC"),
    ("qos", "QoS"),
    ("rtu", "RTU"),
    ("s3", "S3"),
    ("s7", "S7"),
    ("sas", "SAS"),
    ("sha", "SHA"),
    ("slack", "Slack"),
    ("snmp", "SNMP"),
    ("sparkplug", "Sparkplug"),
    ("sql", "SQL"),
    ("ssh", "SSH"),
    ("ssl", "SSL"),
    ("tcp", "TCP"),
    ("telegram", "Telegram"),
    ("tls", "TLS"),
    ("ttl", "TTL"),
    ("udp", "UDP"),
    ("uri", "URI"),
    ("url", "URL"),
    ("urls", "URLs"),
    ("usb", "USB"),
    ("utc", "UTC"),
    ("uuid", "UUID"),
    ("wasm", "WASM"),
    ("wyrm", "WYRM"),
    ("xml", "XML"),
    ("zenoh", "Zenoh"),
    ("zip", "ZIP"),
];

/// A last key token that is a unit: written in brackets (`timeout_ms` →
/// `Timeout (ms)`).
pub const UNITS: &[(&str, &str)] = &[
    ("ms", "ms"),
    ("us", "µs"),
    ("s", "s"),
    ("hz", "Hz"),
    ("kb", "kB"),
    ("kib", "KiB"),
    ("mb", "MB"),
    ("mib", "MiB"),
    ("pct", "%"),
    ("days", "days"),
];

/// Capitalised words a text may hold after its first word besides
/// [`WORDS`]: names of products and companies. Add a name here when a link
/// needs one.
pub const NAMES: &[&str] = &[
    "Amazon",
    "Git",
    "Google",
    "Markdown",
    "Microsoft",
    "Prometheus",
    "Siemens",
    "Studio",
    "Unicode",
];

/// Names of several words, kept as written wherever they stand
/// (`Use Socket Mode` stays, `Write Mode` does not).
pub const PHRASES: &[&str] = &[
    "Block Kit",
    "Bot API",
    "Google Drive",
    "IoT Core",
    "IoT Hub",
    "Socket Mode",
];

fn written(token: &str) -> Option<&'static str> {
    WORDS.iter().find(|(k, _)| *k == token).map(|(_, w)| *w)
}

fn upper_first(s: &str) -> String {
    let mut c = s.chars();
    match c.next() {
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        None => String::new(),
    }
}

/// The name for people of a key: `add_device` → `Add device`, `unit_id` →
/// `Unit ID`, `timeout_ms` → `Timeout (ms)`, `base_url` → `Base URL`.
///
/// Tokens are split at `_`, `-`, `.` and spaces, written in lower case
/// except [`WORDS`], the first one capitalised; a last token of [`UNITS`]
/// (after at least one other) goes into brackets. An empty key gives an
/// empty text.
pub fn humanize(key: &str) -> String {
    let mut tokens: Vec<String> = key
        .split(|c: char| matches!(c, '_' | '-' | '.') || c.is_whitespace())
        .filter(|t| !t.is_empty())
        .map(str::to_lowercase)
        .collect();
    let unit = match tokens.last() {
        Some(last) if tokens.len() > 1 => UNITS.iter().find(|(k, _)| k == last).map(|(_, u)| *u),
        _ => None,
    };
    if unit.is_some() {
        tokens.pop();
    }
    let mut out = String::new();
    for (i, t) in tokens.iter().enumerate() {
        if i > 0 {
            out.push(' ');
        }
        match written(t) {
            Some(w) => out.push_str(w),
            None if i == 0 => out.push_str(&upper_first(t)),
            None => out.push_str(t),
        }
    }
    if let Some(u) = unit {
        out.push_str(" (");
        out.push_str(u);
        out.push(')');
    }
    out
}

/// A capitalised plain word (`Device`): one upper-case letter, then only
/// lower-case ones.
fn capitalised(word: &str) -> bool {
    let mut c = word.chars();
    c.next().is_some_and(|f| f.is_uppercase())
        && c.clone().next().is_some()
        && c.all(|x| x.is_lowercase())
}

fn known(word: &str) -> bool {
    NAMES.contains(&word) || WORDS.iter().any(|(_, w)| *w == word)
}

/// `word` without the punctuation around it.
fn bare(word: &str) -> &str {
    word.trim_matches(|c: char| !c.is_alphanumeric())
}

/// A phrase in sentence case: every capitalised plain word after the first
/// goes to lower case unless it is a name ([`WORDS`], [`NAMES`],
/// [`PHRASES`]); text in brackets stays (`Add IP Connection` → `Add IP
/// connection`).
pub fn sentence(text: &str) -> String {
    let words: Vec<&str> = text.split(' ').collect();
    // Words that belong to a phrase name stay as written.
    let mut kept = vec![false; words.len()];
    for phrase in PHRASES {
        let n = phrase.split(' ').count();
        for i in 0..words.len().saturating_sub(n - 1) {
            let joined = words[i..i + n]
                .iter()
                .map(|w| bare(w))
                .collect::<Vec<_>>()
                .join(" ");
            if joined == *phrase {
                kept[i..i + n].iter_mut().for_each(|k| *k = true);
            }
        }
    }
    let mut depth = 0usize;
    let mut first = true;
    words
        .iter()
        .enumerate()
        .map(|(i, w)| {
            let inside = depth > 0 || w.starts_with('(');
            depth += w.matches('(').count();
            depth = depth.saturating_sub(w.matches(')').count());
            let b = bare(w);
            let was_first = first;
            first = first && b.is_empty();
            if inside || was_first || kept[i] || !capitalised(b) || known(b) {
                (*w).to_owned()
            } else {
                w.replacen(b, &b.to_lowercase(), 1)
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// Whether `text` follows the style of a `display`; the error says what is
/// wrong.
pub fn check(text: &str) -> Result<(), String> {
    let bad = |why: &str| Err(format!("display {text:?}: {why}"));
    if text.is_empty() || text != text.trim() {
        return bad("empty or with spaces around it");
    }
    if text.contains('_') {
        return bad("holds `_` (a key, not a name)");
    }
    if text.ends_with('.') && !text.ends_with("...") {
        return bad("ends with a dot");
    }
    if text.chars().next().is_some_and(|c| c.is_lowercase())
        && !WORDS
            .iter()
            .any(|(_, w)| text.split(' ').next() == Some(*w))
    {
        return bad("starts with a lower-case letter");
    }
    if let Some(w) = text.split(' ').map(bare).find(|w| {
        let low = w.to_lowercase();
        WORDS.iter().any(|(k, form)| *k == low && form != w)
    }) {
        return bad(&format!(
            "writes {w:?} in another case than wyrm_core::display::WORDS"
        ));
    }
    if sentence(text) != text {
        return bad(&format!(
            "not in sentence case (expected {:?}; a name goes to wyrm_core::display::NAMES)",
            sentence(text)
        ));
    }
    Ok(())
}

/// Fill what `action` leaves out: its own `display` from `name` and each
/// parameter's from its key. What is set stays.
pub fn fill(name: &str, action: &mut ActionMeta) {
    if action.display.is_none() {
        action.display = Some(humanize(name));
    }
    for (key, p) in &mut action.params {
        if p.display.is_none() {
            p.display = Some(humanize(key));
        }
    }
}

/// Every `display` of `action` (given or derived) that breaks the style.
pub fn lint(name: &str, action: &ActionMeta) -> Vec<String> {
    let mut a = action.clone();
    fill(name, &mut a);
    let mut out = Vec::new();
    if let Err(e) = check(a.display.as_deref().unwrap_or_default()) {
        out.push(format!("action `{name}`: {e}"));
    }
    for (key, p) in &a.params {
        if let Err(e) = check(p.display.as_deref().unwrap_or_default()) {
            out.push(format!("action `{name}`, parameter `{key}`: {e}"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::meta::{ParamMeta, TypeCode};

    #[test]
    fn humanize_keys() {
        for (key, want) in [
            ("add_device", "Add device"),
            ("remove", "Remove"),
            ("read_registers", "Read registers"),
            ("set_password", "Set password"),
            ("unit_id", "Unit ID"),
            ("id", "ID"),
            ("base_url", "Base URL"),
            ("url", "URL"),
            ("add_mqtt", "Add MQTT"),
            ("ca", "CA"),
            ("skip_tls_check", "Skip TLS check"),
            ("import_dsa", "Import DSA"),
            ("timeout_ms", "Timeout (ms)"),
            ("poll_rate_s", "Poll rate (s)"),
            ("max_hz", "Max (Hz)"),
            ("store_mb", "Store (MB)"),
            ("retention_days", "Retention (days)"),
            ("per_chat_us", "Per chat (µs)"),
            ("ms", "Ms"),
            ("s", "S"),
            ("qos", "QoS"),
            ("add_ip_connection", "Add IP connection"),
            ("get-log", "Get log"),
            ("a_ab", "A ab"),
            ("ADD_Device", "Add device"),
            ("__x__", "X"),
            ("", ""),
        ] {
            assert_eq!(humanize(key), want, "{key}");
        }
    }

    #[test]
    fn humanized_keys_pass_the_check() {
        for key in [
            "add_device",
            "unit_id",
            "timeout_ms",
            "mtls",
            "gzip",
            "a_ab",
        ] {
            assert_eq!(check(&humanize(key)), Ok(()), "{key}");
        }
    }

    #[test]
    fn sentence_case() {
        for (text, want) in [
            ("Add Device", "Add device"),
            ("Add IP Connection", "Add IP connection"),
            ("Rescan For Serial Ports", "Rescan for serial ports"),
            ("Slave ID", "Slave ID"),
            ("Client Key (PEM)", "Client key (PEM)"),
            ("Max Upload (MiB)", "Max upload (MiB)"),
            ("Rate Limit (requests/s)", "Rate limit (requests/s)"),
            ("Import from DSA", "Import from DSA"),
            ("Add Modbus Device", "Add Modbus device"),
            ("Use ReadPropertyMultiple", "Use ReadPropertyMultiple"),
            ("Who-Is", "Who-Is"),
            ("Install Link ▸", "Install link ▸"),
            ("Unsubscribe and Purge", "Unsubscribe and purge"),
            ("Write Mode", "Write mode"),
            ("Use Socket Mode", "Use Socket Mode"),
            ("Add AWS IoT Core", "Add AWS IoT Core"),
            ("Scale (Linear, Then Offset)", "Scale (Linear, Then Offset)"),
        ] {
            assert_eq!(sentence(text), want, "{text}");
        }
    }

    #[test]
    fn check_refuses_what_breaks_the_style() {
        for good in [
            "Add device",
            "Timeout (ms)",
            "Slave ID",
            "URL",
            "mTLS",
            "SNMP v3",
            "...",
            "Send to Slack",
        ] {
            assert_eq!(check(good), Ok(()), "{good}");
        }
        for bad in [
            "",
            " Add device",
            "add_device",
            "Add_device",
            "Add device.",
            "Base Url",
            "Unit id",
            "add device",
            "Add Device",
            "Poll Rate (s)",
        ] {
            assert!(check(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn fill_keeps_what_is_set() {
        let mut a = ActionMeta::new()
            .param("unit_id", ParamMeta::of(TypeCode::Number))
            .param(
                "host",
                ParamMeta::of(TypeCode::String).display("Host or address"),
            );
        fill("add_device", &mut a);
        assert_eq!(a.display.as_deref(), Some("Add device"));
        assert_eq!(a.params["unit_id"].display.as_deref(), Some("Unit ID"));
        assert_eq!(a.params["host"].display.as_deref(), Some("Host or address"));
        let mut b = ActionMeta::new().display("Restart now");
        fill("restart", &mut b);
        assert_eq!(b.display.as_deref(), Some("Restart now"));
    }

    #[test]
    fn lint_names_the_text() {
        let a = ActionMeta::new()
            .display("Add Device")
            .param("x", ParamMeta::of(TypeCode::Number).display("poll_rate"));
        let found = lint("add_device", &a);
        assert_eq!(found.len(), 2, "{found:?}");
        assert!(found[0].contains("Add Device"));
        assert!(found[1].contains("parameter `x`"));
        assert!(lint("add_device", &ActionMeta::new()).is_empty());
    }
}
