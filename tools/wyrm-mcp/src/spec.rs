//! The normative spec (`spec/*.md`, `spec/tables.json`), embedded at build
//! time. Served by the `spec` tool and as resources `wy://spec/<file>`.

pub struct SpecFile {
    pub file: &'static str,
    pub title: &'static str,
    pub text: &'static str,
}

macro_rules! spec_file {
    ($file:literal, $title:literal) => {
        SpecFile {
            file: $file,
            title: $title,
            text: include_str!(concat!("../../../spec/", $file)),
        }
    };
}

pub const FILES: &[SpecFile] = &[
    spec_file!("README.md", "Spec overview"),
    spec_file!("01-keyspace.md", "01 Key space"),
    spec_file!("02-meta.md", "02 ~meta"),
    spec_file!("03-val.md", "03 ~val"),
    spec_file!("04-attachment.md", "04 Attachment and ptok"),
    spec_file!("05-methods.md", "05 Methods"),
    spec_file!("06-flow-def.md", "06 Flow definition"),
    spec_file!("tables.json", "Code tables"),
    spec_file!("CHANGELOG.md", "Spec changelog"),
];

pub const URI_PREFIX: &str = "wy://spec/";

pub fn uri(f: &SpecFile) -> String {
    format!("{URI_PREFIX}{}", f.file)
}

/// `"01"`, `"keyspace"`, `"01-keyspace"`, `"01-keyspace.md"`, `"readme"`,
/// `"tables"` or a `wy://spec/…` URI → that file.
pub fn find(section: &str) -> Option<&'static SpecFile> {
    let s = section
        .trim()
        .trim_start_matches(URI_PREFIX)
        .to_ascii_lowercase();
    let stem = |f: &str| {
        f.rsplit_once('.')
            .map(|(a, _)| a)
            .unwrap_or(f)
            .to_ascii_lowercase()
    };
    FILES.iter().find(|f| {
        let st = stem(f.file);
        let (num, name) = st.split_once('-').unwrap_or((&st, &st));
        f.file.eq_ignore_ascii_case(&s) || st == s || num == s || name == s
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lookup() {
        for q in [
            "01",
            "keyspace",
            "01-keyspace",
            "01-keyspace.md",
            "wy://spec/01-keyspace.md",
        ] {
            assert_eq!(find(q).map(|f| f.file), Some("01-keyspace.md"), "{q}");
        }
        assert_eq!(find("readme").map(|f| f.file), Some("README.md"));
        assert_eq!(find("tables").map(|f| f.file), Some("tables.json"));
        assert_eq!(find("flow-def").map(|f| f.file), Some("06-flow-def.md"));
        assert!(find("99").is_none());
        assert!(FILES.iter().all(|f| !f.text.is_empty()));
    }
}
