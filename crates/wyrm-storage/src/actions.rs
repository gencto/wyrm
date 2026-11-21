//! The arguments of the storage actions: one struct per action declares its
//! parameters (`~meta`) and decodes them (`wyrm_core::args`, typing audit
//! 2026-11-15 T3). A handler takes its struct; no handler reads a name from
//! the arguments map.

use wyrm_core::meta::{ActionResult, GROUP_EDIT, GROUP_NEW};
use wyrm_core::{ActionMeta, Perm, TypeCode, Value};
use wyrm_link_sdk::Args;

wyrm_core::name_enum! {
    /// The type of a value node (`add_value`, an import's `$type`), in the
    /// order a UI offers them. Its names are those of [`TypeCode`].
    pub enum ValueType as "value type" without codec {
        String => "string",
        Number => "number",
        Bool => "bool",
        Array => "array",
        Map => "map",
        Binary => "binary",
        Dynamic => "dynamic",
    }
}

impl ValueType {
    /// The type code a value node of this type has in `~meta`.
    pub const fn code(self) -> TypeCode {
        match self {
            Self::String => TypeCode::String,
            Self::Number => TypeCode::Number,
            Self::Bool => TypeCode::Bool,
            Self::Array => TypeCode::Array,
            Self::Map => TypeCode::Map,
            Self::Binary => TypeCode::Binary,
            Self::Dynamic => TypeCode::Dynamic,
        }
    }
}

wyrm_core::name_enum! {
    /// The editor a value node asks of a UI (`add_value`, an import's
    /// `@editor`); the first means none, and none is stored.
    pub enum ValueEditor as "value editor" without codec {
        None => "none",
        Textarea => "textarea",
        Date => "date",
    }
}

impl ValueEditor {
    /// The name kept with the node (`attr.editor`), or `None` for none.
    pub fn stored(self) -> Option<String> {
        match self {
            Self::None => None,
            other => Some(other.name().to_owned()),
        }
    }
}

/// `<folder> ▸ add_node`.
#[derive(Args)]
pub(crate) struct AddNode {
    pub name: String,
}

/// `<folder> ▸ add_value`. Choices travel as text, as every action's.
#[derive(Args)]
pub(crate) struct AddValue {
    pub name: String,
    #[param(name = "type", choice)]
    pub ty: ValueType,
    #[param(choice)]
    pub editor: Option<ValueEditor>,
}

/// `storage ▸ publish`: the folders and the `dynamic` value at `path` that are
/// missing are made, then the value is set.
#[derive(Args)]
pub(crate) struct Publish {
    #[param(placeholder = "folder/value")]
    pub path: String,
    pub value: Value,
}

/// `<folder> ▸ import`: `data` or `file`; a file parameter lets the gateway
/// take JSON larger than a WebSocket frame (`POST /api/invoke`, ADR 0011).
#[derive(Args)]
pub(crate) struct Import {
    #[param(editor = "textarea", desc = "JSON from Export")]
    pub data: Option<String>,
    #[param(editor = "file", desc = "A JSON file from Export, instead of data")]
    pub file: Option<Vec<u8>>,
}

/// `<node> ▸ delete`.
#[derive(Args)]
pub(crate) struct Delete {
    /// A folder with children goes only with `recursive: true`.
    #[param(absent = false)]
    pub recursive: bool,
}

/// `<node> ▸ rename`.
#[derive(Args)]
pub(crate) struct Rename {
    pub name: String,
}

/// `<node> ▸ duplicate`.
#[derive(Args)]
pub(crate) struct Duplicate {
    pub name: String,
}

/// Every storage action is at `write`.
fn act(a: ActionMeta, display: &str) -> ActionMeta {
    a.level(Perm::Write).display(display)
}

pub(crate) fn add_node() -> ActionMeta {
    act(AddNode::action(), "Add node").group(GROUP_NEW)
}

pub(crate) fn add_value() -> ActionMeta {
    act(AddValue::action(), "Add value").group(GROUP_NEW)
}

pub(crate) fn publish() -> ActionMeta {
    act(Publish::action(), "Publish")
}

pub(crate) fn export() -> ActionMeta {
    act(<()>::action(), "Export").result(ActionResult::Type(TypeCode::String))
}

pub(crate) fn import() -> ActionMeta {
    act(Import::action(), "Import")
}

pub(crate) fn delete() -> ActionMeta {
    act(Delete::action(), "Delete").group(GROUP_EDIT)
}

pub(crate) fn rename() -> ActionMeta {
    act(Rename::action(), "Rename").group(GROUP_EDIT)
}

pub(crate) fn duplicate() -> ActionMeta {
    act(Duplicate::action(), "Duplicate").group(GROUP_EDIT)
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::meta::{Editor, ParamMeta};

    // `~meta` of every action as it was written out by hand before the structs
    // (2026-11-22): the structs must declare the same parameters.
    fn old_act(display: &str) -> ActionMeta {
        ActionMeta::new().level(Perm::Write).display(display)
    }

    fn old_name() -> ParamMeta {
        ParamMeta::of(TypeCode::String).required(true)
    }

    const OLD_TYPES: [TypeCode; 7] = [
        TypeCode::String,
        TypeCode::Number,
        TypeCode::Bool,
        TypeCode::Array,
        TypeCode::Map,
        TypeCode::Binary,
        TypeCode::Dynamic,
    ];

    fn old() -> Vec<(&'static str, ActionMeta)> {
        vec![
            (
                "add_node",
                old_act("Add node")
                    .group(GROUP_NEW)
                    .param("name", old_name()),
            ),
            (
                "add_value",
                old_act("Add value")
                    .group(GROUP_NEW)
                    .param("name", old_name())
                    .param(
                        "type",
                        ParamMeta::of(TypeCode::String)
                            .enum_values(OLD_TYPES.iter().map(|t| t.name()))
                            .required(true),
                    )
                    .param(
                        "editor",
                        ParamMeta::of(TypeCode::String).enum_values(["none", "textarea", "date"]),
                    ),
            ),
            (
                "publish",
                old_act("Publish")
                    .param("path", old_name().placeholder("folder/value"))
                    .param("value", ParamMeta::of(TypeCode::Dynamic).required(true)),
            ),
            (
                "export",
                old_act("Export").result(ActionResult::Type(TypeCode::String)),
            ),
            (
                "import",
                old_act("Import")
                    .param(
                        "data",
                        ParamMeta::of(TypeCode::String)
                            .editor(Editor::Textarea)
                            .description("JSON from Export"),
                    )
                    .param(
                        "file",
                        ParamMeta::of(TypeCode::Binary)
                            .editor(Editor::File)
                            .description("A JSON file from Export, instead of data"),
                    ),
            ),
            (
                "delete",
                old_act("Delete")
                    .group(GROUP_EDIT)
                    .param("recursive", ParamMeta::of(TypeCode::Bool)),
            ),
            (
                "rename",
                old_act("Rename")
                    .group(GROUP_EDIT)
                    .param("name", old_name()),
            ),
            (
                "duplicate",
                old_act("Duplicate")
                    .group(GROUP_EDIT)
                    .param("name", old_name()),
            ),
        ]
    }

    #[test]
    fn meta_of_every_action_is_as_before() {
        let new = [
            ("add_node", add_node()),
            ("add_value", add_value()),
            ("publish", publish()),
            ("export", export()),
            ("import", import()),
            ("delete", delete()),
            ("rename", rename()),
            ("duplicate", duplicate()),
        ];
        for ((name, was), (n, now)) in old().into_iter().zip(new) {
            assert_eq!(name, n);
            assert_eq!(was, now, "~meta of {name}");
            // and the same bytes on the wire
            assert_eq!(
                wyrm_core::codec::to_vec(&was).unwrap(),
                wyrm_core::codec::to_vec(&now).unwrap(),
                "{name}"
            );
        }
    }

    #[test]
    fn value_types_are_type_codes_by_name() {
        for t in ValueType::ALL {
            assert_eq!(t.code().name(), t.name());
        }
        let codes: Vec<TypeCode> = ValueType::ALL.iter().map(|t| t.code()).collect();
        assert_eq!(codes, OLD_TYPES);
    }

    fn map(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    #[test]
    fn arguments_decode_or_name_the_field() {
        let a = AddValue::decode(map(&[
            ("name", Value::from("t")),
            ("type", Value::from("number")),
            ("editor", Value::from("none")),
        ]))
        .unwrap();
        assert_eq!(
            (a.ty, a.editor),
            (ValueType::Number, Some(ValueEditor::None))
        );
        assert_eq!(ValueEditor::None.stored(), None);
        assert_eq!(ValueEditor::Date.stored().as_deref(), Some("date"));
        // a type outside the set is refused with its field's name
        let e = AddValue::decode(map(&[
            ("name", Value::from("t")),
            ("type", Value::from("enum")),
        ]))
        .err()
        .unwrap();
        assert!(e.to_string().starts_with("type"), "{e}");
        // `recursive` is false when absent, and a wrong type is no false
        assert!(!Delete::decode(map(&[])).unwrap().recursive);
        assert!(Delete::decode(map(&[("recursive", Value::from("yes"))])).is_err());
        // a dynamic value is any value, a present `null` too; an absent one is refused
        let p = Publish::decode(map(&[
            ("path", Value::from("a/b")),
            ("value", Value::from(3u64)),
        ]))
        .unwrap();
        assert_eq!(p.value, Value::from(3u64));
        let p =
            Publish::decode(map(&[("path", Value::from("a/b")), ("value", Value::Null)])).unwrap();
        assert_eq!(p.value, Value::Null);
        let e = Publish::decode(map(&[("path", Value::from("a/b"))]))
            .err()
            .unwrap();
        assert_eq!(e.to_string(), "value: required");
        // the text beside it still reads null as absent
        let e = Publish::decode(map(&[("path", Value::Null), ("value", Value::Null)]))
            .err()
            .unwrap();
        assert_eq!(e.to_string(), "path: required");
        // export takes nothing
        assert!(<()>::decode(map(&[("x", Value::from(1u64))])).is_err());
    }
}
