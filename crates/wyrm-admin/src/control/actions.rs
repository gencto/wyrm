//! The arguments of the `sys` actions of `control.rs`: one struct per action
//! declares its parameters (`~meta`) and decodes them (`wyrm_core::args`,
//! typing audit 2026-11-15 T3). A handler takes its struct; no handler reads
//! a name from the arguments map.

use super::updates::UpdateOpts;
use crate::logs::LogLevel;
use crate::registry::Mode;
use std::collections::BTreeMap;
use wyrm_core::{Perm, Value};
use wyrm_link_sdk::{Args, Secret, SecretBytes};

/// `links ▸ install`.
#[derive(Args)]
pub(super) struct Install {
    #[param(display = "Link ID")]
    pub id: String,
    /// One of the drivers this broker hosts (the form lists them), or
    /// `pkg:<name>`.
    #[param(display = "Driver")]
    pub driver: String,
    #[param(choice, display = "Mode")]
    pub mode: Option<Mode>,
    #[param(display = "Params")]
    pub params: Option<BTreeMap<String, Value>>,
}

/// The id of the link an "Install Link ▸" action makes.
#[derive(Args)]
pub(super) struct NewLink {
    #[param(display = "Name", desc = "Id of the new link", trim)]
    pub name: String,
}

/// `links ▸ install_zip`.
#[derive(Args)]
pub(super) struct InstallZip {
    #[param(flatten)]
    pub link: NewLink,
    #[param(
        display = "ZIP file",
        editor = "file",
        desc = "Link package: a zip with wyrm-link.json"
    )]
    pub zip: Vec<u8>,
    #[param(flatten)]
    pub opts: UpdateOpts,
}

/// `links ▸ install_wasm`.
#[derive(Args)]
pub(super) struct InstallWasm {
    #[param(flatten)]
    pub link: NewLink,
    #[param(
        display = "Component",
        editor = "file",
        desc = "A wyrm:link/driver component (.wasm)"
    )]
    pub wasm: Vec<u8>,
    #[param(flatten)]
    pub opts: UpdateOpts,
}

/// `links ▸ install_url`.
#[derive(Args)]
pub(super) struct InstallUrl {
    #[param(flatten)]
    pub link: NewLink,
    #[param(display = "URL", placeholder = "https://example.com/link.zip", trim)]
    pub url: String,
    #[param(flatten)]
    pub opts: UpdateOpts,
}

/// `links ▸ install_git`.
#[derive(Args)]
pub(super) struct InstallGit {
    #[param(flatten)]
    pub link: NewLink,
    #[param(
        display = "URL",
        placeholder = "https://git.example.com/link.git",
        trim
    )]
    pub url: String,
    #[param(
        name = "ref",
        display = "Ref",
        placeholder = "branch or tag",
        trim,
        absent = String::new()
    )]
    pub git_ref: String,
    #[param(flatten)]
    pub opts: UpdateOpts,
}

/// `links ▸ install_repo`.
#[derive(Args)]
pub(super) struct InstallRepo {
    #[param(flatten)]
    pub link: NewLink,
    /// A package of the repository index (the form lists them, or says why
    /// there is none).
    #[param(display = "Package")]
    pub package: String,
    #[param(flatten)]
    pub opts: UpdateOpts,
}

/// `links/<id> ▸ start`.
#[derive(Args)]
pub(super) struct Start {
    #[param(
        display = "Start a held link",
        desc = "A link is held when a rollback over a change of the store format \
                did not restore its data: true starts it as it is",
        absent = false
    )]
    pub force: bool,
}

/// `links/<id> ▸ update`.
#[derive(Args)]
pub(super) struct UpdateParams {
    pub params: BTreeMap<String, Value>,
}

/// `links/<id> ▸ rollback`.
#[derive(Args)]
pub(super) struct Rollback {
    #[param(display = "Revision")]
    pub rev: u32,
}

/// `links/<id> ▸ set_secret`.
#[derive(Args)]
pub(super) struct SetSecret {
    #[param(display = "Name")]
    pub name: String,
    #[param(display = "Value", secret)]
    pub value: SecretBytes,
}

/// `links/<id> ▸ delete_secret`.
#[derive(Args)]
pub(super) struct DeleteSecret {
    #[param(display = "Name")]
    pub name: String,
}

/// `links/<id> ▸ hello`: the link's handshake.
#[derive(Args)]
pub(super) struct Hello {
    pub token: SecretBytes,
}

wyrm_core::name_enum! {
    /// What a link may be granted as a requester (`links/<id> ▸ grant`):
    /// never `config`.
    pub(super) enum GrantLevel as "grant level" without codec {
        /// Removes the grant.
        None => "none",
        List => "list",
        Read => "read",
        Write => "write",
    }
}

impl GrantLevel {
    pub fn perm(self) -> Perm {
        match self {
            GrantLevel::None => Perm::None,
            GrantLevel::List => Perm::List,
            GrantLevel::Read => Perm::Read,
            GrantLevel::Write => Perm::Write,
        }
    }
}

/// `links/<id> ▸ grant`.
#[derive(Args)]
pub(super) struct Grant {
    #[param(
        display = "Path",
        placeholder = "wy/{site}/downstream/<link>",
        desc = "A node of another link (its subtree), or wy/{site}/dataflows",
        trim
    )]
    pub path: String,
    #[param(choice, display = "Level", desc = "none removes the grant")]
    pub level: GrantLevel,
}

/// `links/<id> ▸ get_log {lines, level, filter}`.
#[derive(Args)]
pub(super) struct GetLog {
    #[param(display = "Lines", placeholder = "200 (at most 2000)")]
    pub lines: Option<usize>,
    #[param(
        choice,
        reversed,
        nonempty,
        display = "Level",
        desc = "This level and more severe"
    )]
    pub level: Option<LogLevel>,
    #[param(
        display = "Filter",
        placeholder = "text in the target or message",
        absent = String::new()
    )]
    pub filter: String,
}

impl GetLog {
    /// Lines asked for: 200, at least 1, at most 2000.
    pub fn lines(&self) -> usize {
        self.lines.unwrap_or(200).clamp(1, 2000)
    }

    /// The least severe level wanted: every level when none is named.
    pub fn level(&self) -> tracing::Level {
        self.level.map_or(tracing::Level::TRACE, LogLevel::tracing)
    }
}

/// `sys ▸ get_log`: the broker's log, or the lines of one embedded link.
#[derive(Args)]
pub(super) struct GetBrokerLog {
    #[param(flatten)]
    pub log: GetLog,
    #[param(display = "Link", placeholder = "lines of one embedded link", nonempty)]
    pub link: Option<String>,
}

/// `sys ▸ update_permissions`.
#[derive(Args)]
pub(super) struct UpdatePermissions {
    #[param(display = "Role", nonempty)]
    pub role: String,
    #[param(display = "Path", placeholder = "wy/{site}/downstream/**", nonempty)]
    pub path: String,
    #[param(choice, display = "Level")]
    pub level: Perm,
}

/// `sys ▸ enroll`: a downstream broker asks for its certificate.
#[derive(Args)]
pub(super) struct Enroll {
    #[param(trim)]
    pub site: String,
    pub csr: String,
    pub token: Option<Secret>,
    /// Sites it relays from further down.
    pub via: Option<Vec<String>>,
}

/// `tokens ▸ add`.
#[derive(Args)]
pub(super) struct AddToken {
    #[param(
        display = "Count",
        placeholder = "1",
        desc = "Admissions it allows; 0: no limit",
        max = 1_000_000
    )]
    pub count: Option<u32>,
    #[param(
        display = "Hours",
        placeholder = "24",
        desc = "Valid for this long; 0: never expires",
        min = 0.0,
        max = 87_600.0
    )]
    pub hours: Option<f64>,
}

/// `audit ▸ tail`.
#[derive(Args)]
pub(super) struct AuditTail {
    #[param(display = "Records")]
    pub n: Option<usize>,
}

/// `profiles ▸ put`.
#[derive(Args)]
pub(super) struct PutProfile {
    #[param(display = "Name")]
    pub name: String,
    /// CBOR `ProfileDef`: a picked file, larger than a frame for big models.
    #[param(display = "Profile", editor = "file")]
    pub profile: Vec<u8>,
}

/// `profiles ▸ remove`.
#[derive(Args)]
pub(super) struct RemoveProfile {
    #[param(display = "Name")]
    pub name: String,
}

pub(super) const VIA_ABOUT: &str =
    "Downstream brokers: sites that broker relays from further down (a chain); \
     it may serve their keys, and our upstream may read them.";

/// Authorize of a quarantined link or broker (DSA
/// Authorize): `group` (a gateway role that gets `write` on the link), `name`
/// (display name), driver and params; `via` and `key` for a downstream broker.
#[derive(Args, Default)]
pub(super) struct Approve {
    /// A role of the user gateway (the form lists them).
    #[param(display = "Group", trim, nonempty)]
    pub group: Option<String>,
    #[param(display = "Name", placeholder = "display name", trim, nonempty)]
    pub name: Option<String>,
    #[param(display = "Driver")]
    pub driver: Option<String>,
    #[param(display = "Params")]
    pub params: Option<BTreeMap<String, Value>>,
    #[param(display = "Via", placeholder = "plant, cell", desc = VIA_ABOUT)]
    pub via: Option<String>,
    #[param(
        display = "Key",
        desc = "Downstream brokers: the SHA-256 of its key you compared",
        trim
    )]
    pub key: Option<String>,
}

/// `quarantine ▸ authorize`: [`Approve`] of the CN the form's list names.
#[derive(Args)]
pub(super) struct Authorize {
    #[param(display = "DsId", placeholder = "nothing in quarantine")]
    pub dsid: String,
    #[param(flatten)]
    pub how: Approve,
}

/// `quarantine/<site> ▸ approve` of a downstream broker: the sites it relays,
/// and the key it was reviewed with.
#[derive(Args)]
pub(super) struct ApproveBroker {
    #[param(
        display = "Key",
        desc = "SHA-256 of its key: the same as its sys/upstream/<this site>/key",
        trim
    )]
    pub key: Option<String>,
    #[param(display = "Via", placeholder = "plant, cell", desc = VIA_ABOUT)]
    pub via: Option<String>,
}

impl From<ApproveBroker> for Approve {
    fn from(b: ApproveBroker) -> Self {
        Approve {
            key: b.key,
            via: b.via,
            ..Approve::default()
        }
    }
}

/// `quarantine ▸ deauthorize`.
#[derive(Args)]
pub(super) struct Deauthorize {
    #[param(display = "Link", placeholder = "nothing connected downstream")]
    pub link: String,
}

/// `upstream ▸ add`.
#[derive(Args)]
pub(super) struct AddUpstream {
    #[param(display = "Name", desc = "Site name of that broker", trim, nonempty)]
    pub name: String,
    #[param(
        display = "URL",
        placeholder = "quic/central.example:7450",
        desc = "Its enrollment endpoint (peers.enroll there)",
        trim,
        nonempty
    )]
    pub url: String,
    #[param(
        display = "CA certificate",
        editor = "textarea",
        desc = "PEM of that site's CA (its data_dir/pki/ca.pem)",
        trim,
        nonempty
    )]
    pub ca: String,
    #[param(
        display = "Token",
        secret,
        desc = "From its sys/tokens, if it gave one: admitted at once",
        nonempty
    )]
    pub token: Option<Secret>,
    #[param(display = "Enabled", absent = true)]
    pub enabled: bool,
    #[param(
        display = "Allow config",
        desc = "Its users may run config actions here (sys and links), as far as their own grants go",
        absent = false
    )]
    pub allow_config: bool,
}

/// Every `Args` struct of this file with the parameter name it declares twice,
/// if any (audit of #136: a name that comes again through `flatten`). The list
/// is checked against the file: a struct that is not on it fails the test.
#[cfg(test)]
pub(crate) fn arg_structs() -> Vec<(&'static str, Option<&'static str>)> {
    use wyrm_core::args::repeated_param;
    let list = vec![
        (stringify!(Install), repeated_param::<Install>()),
        (stringify!(NewLink), repeated_param::<NewLink>()),
        (stringify!(InstallZip), repeated_param::<InstallZip>()),
        (stringify!(InstallWasm), repeated_param::<InstallWasm>()),
        (stringify!(InstallUrl), repeated_param::<InstallUrl>()),
        (stringify!(InstallGit), repeated_param::<InstallGit>()),
        (stringify!(InstallRepo), repeated_param::<InstallRepo>()),
        (stringify!(Start), repeated_param::<Start>()),
        (stringify!(UpdateParams), repeated_param::<UpdateParams>()),
        (stringify!(Rollback), repeated_param::<Rollback>()),
        (stringify!(SetSecret), repeated_param::<SetSecret>()),
        (stringify!(DeleteSecret), repeated_param::<DeleteSecret>()),
        (stringify!(Hello), repeated_param::<Hello>()),
        (stringify!(Grant), repeated_param::<Grant>()),
        (stringify!(GetLog), repeated_param::<GetLog>()),
        (stringify!(GetBrokerLog), repeated_param::<GetBrokerLog>()),
        (
            stringify!(UpdatePermissions),
            repeated_param::<UpdatePermissions>(),
        ),
        (stringify!(Enroll), repeated_param::<Enroll>()),
        (stringify!(AddToken), repeated_param::<AddToken>()),
        (stringify!(AuditTail), repeated_param::<AuditTail>()),
        (stringify!(PutProfile), repeated_param::<PutProfile>()),
        (stringify!(RemoveProfile), repeated_param::<RemoveProfile>()),
        (stringify!(Approve), repeated_param::<Approve>()),
        (stringify!(Authorize), repeated_param::<Authorize>()),
        (stringify!(ApproveBroker), repeated_param::<ApproveBroker>()),
        (stringify!(Deauthorize), repeated_param::<Deauthorize>()),
        (stringify!(AddUpstream), repeated_param::<AddUpstream>()),
    ];
    let derives = include_str!("actions.rs")
        .matches(concat!("#[derive(", "Args"))
        .count();
    assert_eq!(
        list.len(),
        derives,
        "control/actions.rs: list every Args struct"
    );
    list
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::args::Fault;
    use wyrm_core::value::IntError;

    fn args(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    /// The field and fault of a refused call.
    fn refused<A: Args>(kv: &[(&str, Value)]) -> (String, Fault) {
        match A::decode(args(kv)) {
            Ok(_) => (String::new(), Fault::Missing),
            Err(e) => (e.field, e.fault),
        }
    }

    /// Typing audit T3: where the hand reader took more than the action declared, the
    /// declaration is what is read now.
    #[test]
    fn a_reader_takes_what_the_action_declares() {
        // `set_secret.value` is binary; the reader also took a text
        assert_eq!(
            refused::<SetSecret>(&[("name", "k".into()), ("value", "text".into())]),
            ("value".to_owned(), Fault::Type("bytes"))
        );
        let a = SetSecret::decode(args(&[
            ("name", "k".into()),
            ("value", Value::Bytes(vec![1, 2])),
        ]))
        .unwrap();
        assert_eq!(a.value.0.expose(), [1, 2]);
        // `grant.level` lists none, list, read, write; the reader took every level
        let grant = |level: &str| {
            Grant::decode(args(&[
                ("path", " wy/s/x ".into()),
                ("level", level.into()),
            ]))
            .map(|g| (g.path, g.level.perm()))
        };
        assert_eq!(grant("write"), Ok(("wy/s/x".to_owned(), Perm::Write)));
        assert_eq!(grant("none"), Ok(("wy/s/x".to_owned(), Perm::None)));
        assert_eq!(grant("config").unwrap_err().field, "level");
        // `enroll.via` is a list of site names; an item that was no text was dropped
        assert_eq!(
            refused::<Enroll>(&[
                ("site", "plant".into()),
                ("csr", "x".into()),
                ("via", Value::Array(vec!["cell".into(), Value::UInt(1)])),
            ]),
            (
                "via".to_owned(),
                Fault::Item {
                    index: 1,
                    fault: Box::new(Fault::Type("text"))
                }
            )
        );
        // a link's mode is a name of the set: any other text was "mode", now it says which
        assert!(matches!(
            refused::<Install>(&[
                ("id", "a".into()),
                ("driver", "mock".into()),
                ("mode", "remote".into())
            ]),
            (f, Fault::Name(_)) if f == "mode"
        ));
        // `hello.token` is binary and required; another type was an empty token
        assert_eq!(
            refused::<Hello>(&[("token", "t".into())]),
            ("token".to_owned(), Fault::Type("bytes"))
        );
        assert_eq!(refused::<Hello>(&[]), ("token".to_owned(), Fault::Missing));
    }

    #[test]
    fn numbers_are_whole_and_bounded() {
        let token = |kv: &[(&str, Value)]| AddToken::decode(args(kv)).map(|a| (a.count, a.hours));
        assert_eq!(token(&[]), Ok((None, None)));
        assert_eq!(
            token(&[("count", Value::Float(3.0)), ("hours", Value::UInt(1))]),
            Ok((Some(3), Some(1.0)))
        );
        // 0 means "no limit": a fraction is never read as 0
        assert_eq!(
            refused::<AddToken>(&[("count", Value::Float(0.5))]),
            ("count".to_owned(), Fault::Int(IntError::Fractional))
        );
        for (field, bad) in [
            ("count", Value::Int(-1)),
            ("count", Value::UInt(1_000_001)),
            ("hours", Value::Float(-1.0)),
            ("hours", Value::UInt(87_601)),
            ("hours", Value::Float(f64::INFINITY)),
        ] {
            let (f, fault) = refused::<AddToken>(&[(field, bad.clone())]);
            assert_eq!(f, field, "{bad:?}");
            assert!(
                matches!(
                    fault,
                    Fault::Int(_) | Fault::Above(..) | Fault::Below(..) | Fault::NotFinite
                ),
                "{bad:?}: {fault}"
            );
        }
        assert_eq!(
            refused::<Rollback>(&[("rev", Value::Float(1.5))]),
            ("rev".to_owned(), Fault::Int(IntError::Fractional))
        );
        assert_eq!(refused::<Rollback>(&[]), ("rev".to_owned(), Fault::Missing));
        let log = |kv: &[(&str, Value)]| GetLog::decode(args(kv)).map(|a| (a.lines(), a.level()));
        assert_eq!(log(&[]), Ok((200, tracing::Level::TRACE)));
        assert_eq!(
            log(&[("lines", Value::UInt(9000)), ("level", "warn".into())]),
            Ok((2000, tracing::Level::WARN))
        );
        assert_eq!(
            log(&[("level", "".into())]),
            Ok((200, tracing::Level::TRACE))
        );
        assert_eq!(log(&[("level", "loud".into())]).unwrap_err().field, "level");
        assert_eq!(log(&[("lines", "many".into())]).unwrap_err().field, "lines");
    }

    /// A name that is no parameter is refused, also beside the fields of another struct.
    #[test]
    fn an_unknown_argument_is_refused() {
        assert_eq!(
            refused::<Start>(&[("forced", Value::Bool(true))]),
            ("forced".to_owned(), Fault::Unknown)
        );
        assert_eq!(
            refused::<InstallUrl>(&[
                ("name", "a".into()),
                ("url", "https://x.example/a.zip".into()),
                ("acept", Value::Bool(true)),
            ]),
            ("acept".to_owned(), Fault::Unknown)
        );
        // a downstream broker's Authorize takes its key and its sites, not a link's fields
        assert_eq!(
            refused::<ApproveBroker>(&[("driver", "mock".into())]),
            ("driver".to_owned(), Fault::Unknown)
        );
        let a: Approve = ApproveBroker::decode(args(&[
            ("key", " ab ".into()),
            ("via", "plant, cell".into()),
        ]))
        .unwrap()
        .into();
        assert_eq!(
            (a.key.as_deref(), a.via.as_deref(), a.driver),
            (Some("ab"), Some("plant, cell"), None)
        );
    }

    /// Audit of #136, finding 1: no `Args` struct of the admin declares a parameter
    /// name twice (its own field and one of a flattened struct). Each file lists its
    /// structs and checks the list against its own source.
    #[test]
    fn no_struct_declares_a_name_twice() {
        let all: Vec<(&str, Option<&str>)> = [
            super::arg_structs(),
            super::super::updates::arg_structs(),
            super::super::broker_update::arg_structs(),
            super::super::backups::arg_structs(),
            super::super::restore::arg_structs(),
            super::super::restore_broker::arg_structs(),
            super::super::send::arg_structs(),
            crate::history::arg_structs(),
        ]
        .concat();
        assert_eq!(all.len(), 55);
        for (name, twice) in all {
            assert_eq!(twice, None, "{name}");
        }
    }

    /// Audit of #136, finding 4: `role` and `path` of `update_permissions` are
    /// required and not empty; a text of white space is a value, as it was (the
    /// roles store says what it thinks of it).
    #[test]
    fn update_permissions_takes_what_it_took() {
        let up = |role: &str, path: &str| {
            UpdatePermissions::decode(args(&[
                ("role", role.into()),
                ("path", path.into()),
                ("level", "read".into()),
            ]))
            .map(|a| (a.role, a.path, a.level))
        };
        assert_eq!(
            up("operator", "wy/{site}/downstream/**"),
            Ok((
                "operator".to_owned(),
                "wy/{site}/downstream/**".to_owned(),
                Perm::Read
            ))
        );
        assert_eq!(
            up("  ", " x ").map(|a| (a.0, a.1)),
            Ok(("  ".to_owned(), " x ".to_owned()))
        );
        assert_eq!(up("", "x").unwrap_err().field, "role");
        assert_eq!(up("r", "").unwrap_err().field, "path");
    }

    /// Audit of #136, finding 4: `install_backup` declares the options of every
    /// install (`install_meta`). `auto_rollback_s` and `restore_point` do nothing
    /// for a backup, but a declared parameter is checked wherever it is declared:
    /// above its bound it is refused (the hand reader did not look at it here).
    #[test]
    fn install_backup_checks_the_options_it_declares() {
        use super::super::restore::InstallBackup;
        let a = InstallBackup::decode(args(&[
            ("upload", "u1".into()),
            ("id", " plc ".into()),
            ("accept", Value::Bool(true)),
            ("auto_rollback_s", Value::UInt(30)),
        ]))
        .unwrap();
        assert_eq!(
            (a.upload.as_deref(), a.id.as_deref()),
            (Some("u1"), Some("plc"))
        );
        assert!(a.opts.accept && a.file.is_none());
        assert_eq!(
            refused::<InstallBackup>(&[("auto_rollback_s", Value::UInt(100_000))]).0,
            "auto_rollback_s"
        );
        // a passphrase is never trimmed; only the empty text is "not given"
        let pass = |p: &str| {
            InstallBackup::decode(args(&[("passphrase", p.into())]))
                .unwrap()
                .passphrase
                .map(|p| p.expose().to_vec())
        };
        assert_eq!(pass("   "), Some(b"   ".to_vec()));
        assert_eq!(pass(""), None);
    }

    /// An install's options come with every install action, once.
    #[test]
    fn an_install_takes_its_options() {
        let a = InstallGit::decode(args(&[
            ("name", " plc ".into()),
            ("url", " https://git.example/x.git ".into()),
            ("ref", " main ".into()),
            ("accept", Value::Bool(true)),
            ("auto_rollback_s", Value::UInt(0)),
        ]))
        .unwrap();
        assert_eq!(
            (a.link.name.as_str(), a.url.as_str(), a.git_ref.as_str()),
            ("plc", "https://git.example/x.git", "main")
        );
        assert!(a.opts.accept && a.opts.restore_point);
        assert_eq!(a.opts.auto_rollback_s, 0);
        assert_eq!(
            refused::<InstallZip>(&[("name", "a".into()), ("zip", "not bytes".into())]),
            ("zip".to_owned(), Fault::Type("bytes"))
        );
        assert_eq!(
            refused::<InstallZip>(&[
                ("name", "a".into()),
                ("zip", Value::Bytes(vec![])),
                ("accept", "yes".into())
            ]),
            ("accept".to_owned(), Fault::Type("true or false"))
        );
    }

    #[test]
    fn an_upstream_is_named_with_its_endpoint_and_ca() {
        let base = [
            ("name", Value::from(" central ")),
            ("url", Value::from("quic/central.example:7450")),
            ("ca", Value::from("PEM")),
        ];
        let a = AddUpstream::decode(args(&base)).unwrap();
        assert_eq!(a.name, "central");
        assert!(a.enabled && !a.allow_config && a.token.is_none());
        let mut with = base.to_vec();
        with.extend([("token", Value::from("")), ("enabled", Value::Bool(false))]);
        let a = AddUpstream::decode(args(&with)).unwrap();
        assert!(
            !a.enabled && a.token.is_none(),
            "an empty token is no token"
        );
        // each of the three is required, and an empty text is not a value
        for i in 0..base.len() {
            let mut kv = base.to_vec();
            let (field, _) = kv.remove(i);
            assert_eq!(
                refused::<AddUpstream>(&kv),
                (field.to_owned(), Fault::Missing)
            );
            kv.push((field, Value::from("  ")));
            assert_eq!(
                refused::<AddUpstream>(&kv),
                (field.to_owned(), Fault::Missing)
            );
        }
    }
}
