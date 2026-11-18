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

const README: SpecFile = spec_file!("README.md", "Spec overview");
const KEYSPACE: SpecFile = spec_file!("01-keyspace.md", "01 Key space");
const META: SpecFile = spec_file!("02-meta.md", "02 ~meta");
const VAL: SpecFile = spec_file!("03-val.md", "03 ~val");
const ATTACHMENT: SpecFile = spec_file!("04-attachment.md", "04 Attachment and ptok");
const METHODS: SpecFile = spec_file!("05-methods.md", "05 Methods");
const FLOW_DEF: SpecFile = spec_file!("06-flow-def.md", "06 Flow definition");
const TABLES: SpecFile = spec_file!("tables.json", "Code tables");
const CHANGELOG: SpecFile = spec_file!("CHANGELOG.md", "Spec changelog");

/// Every file, in the order of [`Section::ALL`].
pub const FILES: &[SpecFile] = &[
    README, KEYSPACE, META, VAL, ATTACHMENT, METHODS, FLOW_DEF, TABLES, CHANGELOG,
];

pub const URI_PREFIX: &str = "wy://spec/";

pub fn uri(f: &SpecFile) -> String {
    format!("{URI_PREFIX}{}", f.file)
}

wyrm_core::name_enum! {
    /// A section of the spec: one file of [`FILES`], in the same order. The name is the
    /// file's stem in lower case.
    pub enum Section as "spec section" without codec {
        Readme => "readme",
        Keyspace => "01-keyspace",
        Meta => "02-meta",
        Val => "03-val",
        Attachment => "04-attachment",
        Methods => "05-methods",
        FlowDef => "06-flow-def",
        Tables => "tables",
        Changelog => "changelog",
    }
}

impl Section {
    /// The section a person or a model named. People write a section five ways, so the
    /// other four are brought to the name here, in this one place: the file
    /// (`01-keyspace.md`, any case), its resource URI (`wy://spec/01-keyspace.md`), the
    /// number alone (`01`) and the word alone (`keyspace`). Anything else is `None`.
    pub fn parse(text: &str) -> Option<Self> {
        let t = text
            .trim()
            .trim_start_matches(URI_PREFIX)
            .to_ascii_lowercase();
        let stem = t
            .strip_suffix(".md")
            .or_else(|| t.strip_suffix(".json"))
            .unwrap_or(&t);
        Self::from_name(stem).or_else(|| {
            Self::ALL.iter().copied().find(|s| {
                s.name()
                    .split_once('-')
                    .is_some_and(|(number, word)| stem == number || stem == word)
            })
        })
    }

    /// The file of this section.
    pub fn file(self) -> &'static SpecFile {
        match self {
            Section::Readme => &README,
            Section::Keyspace => &KEYSPACE,
            Section::Meta => &META,
            Section::Val => &VAL,
            Section::Attachment => &ATTACHMENT,
            Section::Methods => &METHODS,
            Section::FlowDef => &FLOW_DEF,
            Section::Tables => &TABLES,
            Section::Changelog => &CHANGELOG,
        }
    }
}

/// The file a text names ([`Section::parse`]).
pub fn find(section: &str) -> Option<&'static SpecFile> {
    Section::parse(section).map(Section::file)
}

/// The `section` argument of the `spec` tool: a [`Section`] in any of the forms
/// [`Section::parse`] takes, or nothing (left out, `null` or empty) for the list. A text
/// that names no section is refused where the arguments are decoded, with the names.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SectionArg(pub Option<Section>);

impl<'de> serde::Deserialize<'de> for SectionArg {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let text = <Option<String> as serde::Deserialize>::deserialize(d)?;
        match text.as_deref().map(str::trim).filter(|t| !t.is_empty()) {
            None => Ok(SectionArg(None)),
            Some(t) => Section::parse(t)
                .map(|s| SectionArg(Some(s)))
                .ok_or_else(|| {
                    serde::de::Error::custom(format!(
                        "no spec section {t:?} (one of {})",
                        Section::NAMES.join(", ")
                    ))
                }),
        }
    }
}

impl schemars::JsonSchema for SectionArg {
    fn schema_name() -> std::borrow::Cow<'static, str> {
        "SpecSection".into()
    }

    fn json_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
        // on the wire it is an optional text; the names are in the description, because
        // the number alone and the word alone are taken too
        let mut schema = <Option<String> as schemars::JsonSchema>::json_schema(generator);
        schema.insert(
            "description".to_owned(),
            format!(
                "A spec section: {}; also the number alone (01) or the word alone \
                 (keyspace). Empty or left out: the list.",
                Section::NAMES.join(", ")
            )
            .into(),
        );
        schema
    }
}

/// The arguments of the `spec` tool (both servers).
#[derive(serde::Deserialize, schemars::JsonSchema)]
pub struct SpecParams {
    #[serde(default)]
    pub section: SectionArg,
}

/// The MIME type of a spec file.
pub fn mime(file: &str) -> &'static str {
    if file.ends_with(".json") {
        "application/json"
    } else {
        "text/markdown"
    }
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
        assert_eq!(find("README.md").map(|f| f.file), Some("README.md"));
        assert_eq!(find("Tables.JSON").map(|f| f.file), Some("tables.json"));
        assert_eq!(find(" 06 ").map(|f| f.file), Some("06-flow-def.md"));
        assert!(find("99").is_none());
        assert!(find("").is_none());
        assert!(find("01-").is_none());
        assert!(find("key").is_none());
        assert!(FILES.iter().all(|f| !f.text.is_empty()));
    }

    #[test]
    fn sections_and_files_are_the_same_list() {
        assert_eq!(Section::ALL.len(), FILES.len());
        for (s, f) in Section::ALL.iter().zip(FILES) {
            assert_eq!(s.file().file, f.file);
            let stem = f.file.rsplit_once('.').map_or(f.file, |(a, _)| a);
            assert_eq!(s.name(), stem.to_ascii_lowercase());
        }
    }

    #[test]
    fn the_argument_is_decoded_once() {
        let arg =
            |j: serde_json::Value| serde_json::from_value::<SpecParams>(j).map(|p| p.section.0);
        assert_eq!(arg(serde_json::json!({})).unwrap(), None);
        assert_eq!(arg(serde_json::json!({ "section": null })).unwrap(), None);
        assert_eq!(arg(serde_json::json!({ "section": " " })).unwrap(), None);
        assert_eq!(
            arg(serde_json::json!({ "section": "04" })).unwrap(),
            Some(Section::Attachment)
        );
        assert_eq!(
            arg(serde_json::json!({ "section": "wy://spec/tables.json" })).unwrap(),
            Some(Section::Tables)
        );
        let e = arg(serde_json::json!({ "section": "99" }))
            .unwrap_err()
            .to_string();
        assert!(
            e.contains("no spec section \"99\"") && e.contains("01-keyspace"),
            "{e}"
        );
        assert!(arg(serde_json::json!({ "section": 4 })).is_err());
    }
}
