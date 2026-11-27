//! What the device takes of a configuration: the rules of its scripts, so that an assembler
//! never writes a region the device refuses.
//!
//! The device applies a region whole or not at all, and some of what it refuses is refused
//! late: a site its data partition script does not take stops the broker only after the
//! region is applied and wiped. Each rule here is the one of a script of the package
//! (`packaging/openwrt/wyrmd/files/usr/libexec/wyrm/`), named beside it; the tests of this
//! crate read the scripts and compare (`a_rule_is_the_one_of_the_device`).

use crate::names::members;
use crate::ImageError;

/// The broker's `data_dir` on a board: the data partition is mounted there (`DATA=` of
/// `run.sh` and of `data-part.sh`). The configuration names it in its outermost object.
pub const DATA_DIR: &str = "/srv/wyrm";
/// The longest site name a device takes (`SITE_MAX` of `site.sh`).
pub const SITE_MAX: usize = 64;
/// The most NTP servers a device takes (`NTP_MAX` of `first-boot.sh`).
pub const NTP_MAX: usize = 16;

/// The characters of a site name besides ASCII letters and digits (`SITE_CHARS` of
/// `site.sh`). It is a part of key expressions and of file names on the device.
pub(crate) const SITE_EXTRA: &str = "_.-";
/// The same for the name of a time zone (`TZ_CHARS` of `first-boot.sh`).
pub(crate) const TZ_EXTRA: &str = "_+/-";
/// The same for an NTP server: a host name or an address, IPv6 without brackets
/// (`NTP_CHARS` of `first-boot.sh`).
pub(crate) const NTP_EXTRA: &str = ".:_-";

fn made_of(text: &str, extra: &str) -> bool {
    text.chars()
        .all(|c| c.is_ascii_alphanumeric() || extra.contains(c))
}

/// A site name the device takes (`site.sh`): 1 to [`SITE_MAX`] characters of
/// `A-Z a-z 0-9 _ . -`, not starting with `.`. The broker takes every such name
/// (`wyrm_core::keyspace::validate_segment`).
pub fn plain_site(site: &str) -> bool {
    !site.is_empty()
        && site.len() <= SITE_MAX
        && !site.starts_with('.')
        && made_of(site, SITE_EXTRA)
}

/// The file `timezone` as `first-boot.sh` takes it: one line, its newline optional, a name of
/// `A-Z a-z 0-9 _ + / -` that does not start with `/` and holds no `..`.
fn timezone(text: &str) -> bool {
    let name = text.strip_suffix('\n').unwrap_or(text);
    !name.is_empty() && !name.starts_with('/') && !name.contains("..") && made_of(name, TZ_EXTRA)
}

/// The file `ntp` as `first-boot.sh` takes it: at most [`NTP_MAX`] lines (the last newline
/// optional, an empty file is no server), each a name of `A-Z a-z 0-9 . : _ -` that does
/// not start with `-`. An empty line is refused.
fn ntp(text: &str) -> bool {
    if text.is_empty() {
        return true;
    }
    let lines: Vec<&str> = text
        .strip_suffix('\n')
        .unwrap_or(text)
        .split('\n')
        .collect();
    lines.len() <= NTP_MAX
        && lines
            .iter()
            .all(|line| !line.is_empty() && !line.starts_with('-') && made_of(line, NTP_EXTRA))
}

/// The site of a `wyrmd.json5` as the device reads it: the one member `site` of the
/// outermost object, a string without an escape (`site.sh`). `None` when there is none, when
/// there are two (the broker refuses a key twice), or when its value is no such string.
pub fn site_of(wyrmd_json5: &str) -> Option<String> {
    match members(wyrmd_json5, "site").as_slice() {
        [Some(site)] => Some(site.clone()),
        _ => None,
    }
}

/// What the device refuses of these files, first the earliest rule: the site
/// ([`ImageError::Site`]), `data_dir` ([`ImageError::DataDir`]), `timezone`
/// ([`ImageError::Timezone`]) and `ntp` ([`ImageError::Ntp`]).
pub(crate) fn check(
    wyrmd_json5: &str,
    timezone_file: Option<&str>,
    ntp_file: Option<&str>,
) -> Result<(), ImageError> {
    if !site_of(wyrmd_json5).is_some_and(|site| plain_site(&site)) {
        return Err(ImageError::Site);
    }
    if members(wyrmd_json5, "data_dir").as_slice() != [Some(DATA_DIR.to_owned())] {
        return Err(ImageError::DataDir);
    }
    if timezone_file.is_some_and(|text| !timezone(text)) {
        return Err(ImageError::Timezone);
    }
    if ntp_file.is_some_and(|text| !ntp(text)) {
        return Err(ImageError::Ntp);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(
        clippy::unwrap_used,
        reason = "test code: a failed step fails the test"
    )]

    use super::*;

    /// The rules here and in the device's scripts are one: each script line that holds a
    /// rule is compared with the constants of this crate.
    #[test]
    fn a_rule_is_the_one_of_the_device() {
        const LIB: &str = "../../packaging/openwrt/wyrmd/files/usr/libexec/wyrm";
        let script = |name: &str| {
            std::fs::read_to_string(format!("{}/{LIB}/{name}", env!("CARGO_MANIFEST_DIR"))).unwrap()
        };
        let has = |text: &str, line: &str| text.lines().any(|l| l.trim() == line);
        let site = script("site.sh");
        assert!(has(&site, &format!("SITE_MAX={SITE_MAX}")));
        assert!(has(&site, &format!("SITE_CHARS='A-Za-z0-9{SITE_EXTRA}'")));
        assert!(has(&site, "'' | .* | *[!$SITE_CHARS]*) return 1 ;;"));
        assert!(has(&site, "[ \"${#1}\" -le \"$SITE_MAX\" ]"));
        let first = script("first-boot.sh");
        assert!(has(&first, &format!("TZ_CHARS='A-Za-z0-9{TZ_EXTRA}'")));
        assert!(has(&first, &format!("NTP_CHARS='A-Za-z0-9{NTP_EXTRA}'")));
        assert!(has(&first, &format!("NTP_MAX={NTP_MAX}")));
        assert!(first.contains("'' | /* | *..* | *[!$TZ_CHARS]*) refuse"));
        assert!(first.contains("'' | -* | *[!$NTP_CHARS]*) refuse"));
        assert!(first.contains("$SITE_SH \"$files/wyrmd.json5\" > /dev/null ||"));
        for name in ["run.sh", "data-part.sh"] {
            let text = script(name);
            let data = text.lines().find_map(|l| {
                l.strip_prefix("DATA=")
                    .map(|v| v.trim_start_matches("${WYRM_DATA:-").trim_end_matches('}'))
            });
            assert_eq!(data, Some(DATA_DIR), "{name}");
        }
        let data_part = script("data-part.sh");
        assert!(has(&data_part, "$SITE_SH --name \"$1\""));
    }

    #[test]
    fn a_site_is_a_plain_name() {
        for good in [
            "plant",
            "Plant-2",
            "a",
            "a.b",
            "-x",
            "_",
            "x.",
            &"s".repeat(SITE_MAX),
        ] {
            assert!(plain_site(good), "{good:?}");
        }
        for bad in [
            "",
            ".x",
            ".",
            "..",
            "a/b",
            "a b",
            "a;b",
            "~x",
            "ü",
            "a\n",
            &"s".repeat(SITE_MAX + 1),
        ] {
            assert!(!plain_site(bad), "{bad:?}");
        }
    }

    #[test]
    fn the_site_is_the_one_member_of_the_outermost_object() {
        let site = |text: &str| site_of(text);
        assert_eq!(site("{ site: \"plant\" }").as_deref(), Some("plant"));
        assert_eq!(site("{ 'site': 'plant' }").as_deref(), Some("plant"));
        assert_eq!(
            site("{ upstream: { site: \"central\" }, site: \"edge\" }").as_deref(),
            Some("edge")
        );
        assert_eq!(
            site("{\n // site: \"x\"\n /* site: \"y\" */ note: \"site: 'z'\", site: \"plant\" }")
                .as_deref(),
            Some("plant")
        );
        for none in [
            "{ }",
            "{ upstream: { site: \"central\" } }",
            "{ site: 12 }",
            "{ site: \"pl\\u0061nt\" }",
            "[ { site: \"x\" } ]",
            "site: \"x\"",
            "{ site: \"a\", site: \"b\" }",
            "{ site: { name: \"x\" } }",
        ] {
            assert_eq!(site(none), None, "{none}");
        }
    }

    #[test]
    fn timezone_and_ntp_follow_the_device() {
        for good in [
            "Europe/Kyiv",
            "Europe/Kyiv\n",
            "UTC",
            "Etc/GMT+2",
            "America/Port-au-Prince",
        ] {
            assert!(timezone(good), "{good:?}");
        }
        for bad in [
            "",
            "\n",
            "Europe/Kyiv extra",
            "/etc/passwd",
            "../x",
            "Europe/Kyiv\n\n",
            "a\nb",
        ] {
            assert!(!timezone(bad), "{bad:?}");
        }
        let many = |n: usize| {
            (0..n)
                .map(|i| format!("ntp{i}.example\n"))
                .collect::<String>()
        };
        for good in [
            "",
            "pool.ntp.org",
            "a.example\nb.example\n",
            "2001:db8::1\n",
            &many(NTP_MAX),
        ] {
            assert!(ntp(good), "{good:?}");
        }
        for bad in [
            "\n",
            "pool.ntp.org;\n",
            "[2001:db8::1]\n",
            "a.example\n\nb.example\n",
            "-x\n",
            "a b\n",
            &many(NTP_MAX + 1),
        ] {
            assert!(!ntp(bad), "{bad:?}");
        }
    }
}
