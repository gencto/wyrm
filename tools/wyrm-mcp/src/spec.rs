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
    /// The number and the word of a numbered section (`01` and `keyspace` of
    /// `01-keyspace`); `None` for `readme`, `tables` and `changelog`.
    fn short_forms(self) -> Option<(&'static str, &'static str)> {
        self.name().split_once('-')
    }

    /// The section a person or a model named. A section is written five ways, and the
    /// other four are brought to the name here, in this one place: the number alone
    /// (`01`), the word alone (`keyspace`), its file (`01-keyspace.md`) and its resource
    /// URI (`wy://spec/01-keyspace.md`); letters in either case. The file is the
    /// section's own file: `readme.json` and `tables.md` name nothing. Anything else is
    /// `None`.
    pub fn parse(text: &str) -> Option<Self> {
        let t = text
            .trim()
            .trim_start_matches(URI_PREFIX)
            .to_ascii_lowercase();
        Self::from_name(&t).or_else(|| {
            Self::ALL.iter().copied().find(|s| {
                s.file().file.eq_ignore_ascii_case(&t)
                    || s.short_forms()
                        .is_some_and(|(number, word)| t == number || t == word)
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

    fn json_schema(_: &mut schemars::SchemaGenerator) -> schemars::Schema {
        // a closed set in the schema too: the names, then the short forms of the numbered
        // sections; `null` (or leaving it out) asks for the list
        let mut values: Vec<serde_json::Value> =
            Section::NAMES.iter().map(|n| (*n).into()).collect();
        for (number, word) in Section::ALL.iter().filter_map(|s| s.short_forms()) {
            values.push(number.into());
            values.push(word.into());
        }
        values.push(serde_json::Value::Null);
        schemars::json_schema!({
            "enum": values,
            "description": "A spec section by its name (01-keyspace), its number (01) or \
                its word (keyspace). Left out or null: the list of sections.",
        })
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
        // a file is the section's own file, not any stem with any suffix
        assert!(find("readme.json").is_none());
        assert!(find("tables.md").is_none());
        assert!(find("01-keyspace.json").is_none());
        assert!(find("01.md").is_none());
        assert_eq!(find("TABLES.JSON").map(|f| f.file), Some("tables.json"));
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
    fn the_schema_is_an_enum_of_what_the_decoder_takes() {
        let schema = schemars::schema_for!(SpecParams);
        let json = serde_json::to_value(&schema).unwrap();
        let found = json
            .pointer("/properties/section/enum")
            .or_else(|| json.pointer("/$defs/SpecSection/enum"))
            .and_then(|e| e.as_array())
            .expect("an enum")
            .clone();
        // 9 names, number and word of the six numbered sections, null
        assert_eq!(found.len(), 9 + 12 + 1, "{found:?}");
        assert!(found.contains(&serde_json::Value::Null));
        for name in Section::NAMES {
            assert!(found.contains(&(*name).into()), "{name}");
        }
        for v in found.iter().filter_map(|v| v.as_str()) {
            assert!(
                Section::parse(v).is_some(),
                "{v}: in the schema, not decoded"
            );
        }
        assert!(json.pointer("/properties/section/type").is_none());
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
