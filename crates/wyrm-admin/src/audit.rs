//! Audit journal (wiki "Логування і аудит"): a `wyrm-state` store whose WAL
//! HMAC chain makes deletion or editing of records detectable. Recent
//! records stay in memory for `sys/audit/~act/tail`.

use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

const RECENT: usize = 1000;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct AuditRecord {
    /// Microseconds since the Unix epoch.
    #[n(0)]
    pub t: u64,
    /// Who: `user:<id>`, `link:<id>`, `system`, `anonymous`.
    #[n(1)]
    pub sub: String,
    /// `install|start|stop|remove|hello|approve|reject|quarantine|acl_denied`.
    #[n(2)]
    pub op: String,
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
