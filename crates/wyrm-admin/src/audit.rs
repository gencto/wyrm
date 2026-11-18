//! Audit journal (wiki "Логування і аудит"): a `wyrm-state` store whose WAL
//! HMAC chain makes deletion or editing of records detectable. Recent
//! records stay in memory for `sys/audit/~act/tail`.

use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use wyrm_core::named::OrUnknown;

const RECENT: usize = 1000;

wyrm_core::name_enum! {
    /// What an audit record is about: every `op` this build writes. The broker's own
    /// operations, the gateway's events (`login`, `user`, a refused request under the
    /// name of what was refused) and the three a link reports for itself (`set`,
    /// `invoke`, `check`).
    pub enum AuditOp as "audit op" {
        AclDenied => "acl_denied",
        Approve => "approve",
        AuditDropped => "audit_dropped",
        BackupDownload => "backup_download",
        BackupRemove => "backup_remove",
        BackupSend => "backup_send",
        Deauthorize => "deauthorize",
        DeleteSecret => "delete_secret",
        Demoted => "demoted",
        DeviceAdded => "device_added",
        DeviceLogin => "device_login",
        DeviceRefused => "device_refused",
        DeviceRemoved => "device_removed",
        Enroll => "enroll",
        EnrollmentExpire => "enrollment_expire",
        Event => "event",
        Hello => "hello",
        HistoryGroup => "history_group",
        HistoryOptions => "history_options",
        HistoryPurge => "history_purge",
        HistorySink => "history_sink",
        HistoryWatch => "history_watch",
        HotStart => "hot_start",
        Install => "install",
        LinkGrant => "link_grant",
        LinkRestore => "link_restore",
        LogLevel => "log_level",
        Login => "login",
        McpSignIn => "mcp_sign_in",
        PackageInstall => "package_install",
        PackageRemove => "package_remove",
        PackageUpdate => "package_update",
        PeerAdd => "peer_add",
        PeerAllowConfig => "peer_allow_config",
        PeerCert => "peer_cert",
        PeerEnable => "peer_enable",
        PeerRemove => "peer_remove",
        PeerSecretsKept => "peer_secrets_kept",
        PeerTokenKept => "peer_token_kept",
        ProfilePut => "profile_put",
        ProfileRemove => "profile_remove",
        Promoted => "promoted",
        Quarantine => "quarantine",
        Reject => "reject",
        Remove => "remove",
        Renew => "renew",
        RestoreApplied => "restore_applied",
        RestoreApply => "restore_apply",
        RestoreFailed => "restore_failed",
        RestorePoint => "restore_point",
        SecretDropped => "secret_dropped",
        SetOption => "set_option",
        SetSecret => "set_secret",
        Signers => "signers",
        StandbyForked => "standby_forked",
        Start => "start",
        StepUp => "step_up",
        Stop => "stop",
        TokenAdd => "token_add",
        TokenRemove => "token_remove",
        Update => "update",
        UpdateConfirmed => "update_confirmed",
        UpdatePermissions => "update_permissions",
        UpdateRollback => "update_rollback",
        UpdateStart => "update_start",
        User => "user",
        WatchKey => "watch_key",
        Set => "set",
        Invoke => "invoke",
        Check => "check",
        Meta => "meta",
        Children => "children",
        List => "list",
        Subscribe => "subscribe",
        Unsubscribe => "unsubscribe",
        History => "history",
        Doc => "doc",
        ConfirmRequired => "confirm_required",
        Rollback => "rollback",
        AutoInstall => "auto_install",
        EnrollToken => "enroll_token",
        LinkBackup => "link_backup",
        BackupCreate => "backup_create",
    }
}

/// The `op` of a record as the journal keeps it. The writer side is closed: a record
/// is made only from an [`AuditOp`]. The reader side is not, for two reasons, and
/// both are about records this build did not make:
///
/// * the journal is an append-only WAL under an HMAC chain that outlives the build:
///   it holds records of every earlier version, a standby follows the journal of an
///   active that may be newer, and a rollback after an update reads what the newer
///   version wrote. One name this build does not know must not make the whole
///   journal unreadable (a refused record breaks the replay and the chain check);
/// * a link reports its own `set`/`invoke` events from another process, built with
///   its own SDK version.
///
/// An unknown name is kept as written and shown as written; nothing reads it as an
/// operation of this build.
pub type StoredOp = OrUnknown<AuditOp>;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct AuditRecord {
    /// Microseconds since the Unix epoch.
    #[n(0)]
    pub t: u64,
    /// Who: `user:<id>`, `link:<id>`, `system`, `anonymous`.
    #[n(1)]
    pub sub: String,
    /// What was done ([`AuditOp`]; a name of another build is kept as written).
    #[n(2)]
    pub op: StoredOp,
    #[n(3)]
    pub key: String,
    /// Spec 04 status code of the outcome.
    #[n(4)]
    pub status: u8,
    #[n(5)]
    pub detail: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct AuditLog {
    pub count: u64,
    pub recent: VecDeque<AuditRecord>,
}

impl wyrm_state::State for AuditLog {
    const SCHEMA: u32 = 1;
    type Op = AuditRecord;

    fn apply(&mut self, rec: &AuditRecord) -> Result<(), String> {
        self.count += 1;
        if self.recent.len() == RECENT {
            self.recent.pop_front();
        }
        self.recent.push_back(rec.clone());
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Records as the journal held them when `op` was a `String` (bytes made by that
    /// build): the WAL form (CBOR) and the snapshot form (postcard), one with an op of
    /// this build and one with a name no build has any more.
    const OLD_WAL_KNOWN: &str = "861b000643b64621e80069757365723a726f6f746b706565725f72656d6f7665637570310067766961205b615d";
    const OLD_WAL_RETIRED: &str =
        "861b000643b64621e80069757365723a726f6f746a726574697265645f6f70637570310067766961205b615d";
    const OLD_SNAPSHOT: &str = "020280d087b1e4f6900309757365723a726f6f740b706565725f72656d6f7665037570310007766961205b615d80d087b1e4f6900309757365723a726f6f740a726574697265645f6f70037570310007766961205b615d";

    fn rec(op: StoredOp) -> AuditRecord {
        AuditRecord {
            t: 1_763_300_000_000_000,
            sub: "user:root".into(),
            op,
            key: "up1".into(),
            status: 0,
            detail: "via [a]".into(),
        }
    }

    #[test]
    fn a_journal_written_with_text_ops_reads_and_writes_back_the_same_bytes() {
        let known = rec(AuditOp::PeerRemove.into());
        let retired = rec(OrUnknown::Unknown("retired_op".into()));
        for (hex, want) in [(OLD_WAL_KNOWN, &known), (OLD_WAL_RETIRED, &retired)] {
            let bytes = wyrm_core::hex::decode(hex).unwrap();
            let got: AuditRecord = minicbor::decode(&bytes).unwrap();
            assert_eq!(&got, want);
            assert_eq!(minicbor::to_vec(&got).unwrap(), bytes);
        }
        let bytes = wyrm_core::hex::decode(OLD_SNAPSHOT).unwrap();
        let log: AuditLog = postcard::from_bytes(&bytes).unwrap();
        assert_eq!(log.count, 2);
        assert_eq!(log.recent, [known, retired]);
        assert_eq!(postcard::to_allocvec(&log).unwrap(), bytes);
    }

    #[test]
    fn every_op_keeps_its_name_and_no_name_is_twice() {
        let mut seen = std::collections::BTreeSet::new();
        for op in AuditOp::ALL {
            assert!(seen.insert(op.name()), "{}", op.name());
            assert_eq!(StoredOp::of(op.name()), OrUnknown::Known(*op));
        }
        // the names of the first journal format (the field's doc until 2026-11-17)
        for n in [
            "install",
            "start",
            "stop",
            "remove",
            "hello",
            "approve",
            "reject",
            "quarantine",
            "acl_denied",
        ] {
            assert!(AuditOp::from_name(n).is_some(), "{n}");
        }
        // case and form are exact: nothing is read as another op
        assert_eq!(AuditOp::from_name("Install"), None);
        assert_eq!(StoredOp::of("Install").known(), None);
    }
}
