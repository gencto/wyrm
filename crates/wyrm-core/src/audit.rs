//! The audit events a link reports for itself.
//!
//! A link (its SDK) reports each `set`, `invoke` and checked invoke to the broker,
//! which writes them into its journal. The names are declared once, here: the SDK
//! writes from this set, and the broker admits only these as an operation a link
//! may claim. Every other operation of the journal is the broker's own, and a
//! link cannot name one.

crate::name_enum! {
    /// What a link reports: one request it answered.
    pub enum LinkOp as "link audit op" {
        Set => "set",
        Invoke => "invoke",
        /// An invoke with `check`: the call was checked, not run (spec 05).
        Check => "check",
    }
}
