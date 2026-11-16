//! The ops of the WebSocket protocol, decoded once at the frame boundary
//! (typing audit T2). An op name this gateway does not serve, or an op
//! without the field it needs, is refused there; past it an op is an [`Op`]
//! with its fields, and [`Op::route`] is the one table of what each op needs
//! and how it runs. That table is an exhaustive `match` with no `_` arm: an
//! op is not served until it is written there with its right.

use crate::Grants;
use std::collections::BTreeMap;
use wyrm_core::{Perm, Value};

wyrm_core::name_enum! {
    /// The op names of a request frame (`op`).
    pub(crate) enum OpName as "op" {
        Meta => "meta",
        Children => "children",
        List => "list",
        Subscribe => "subscribe",
        Unsubscribe => "unsubscribe",
        Set => "set",
        Invoke => "invoke",
        Check => "check",
        History => "history",
        Doc => "doc",
    }
}

impl From<OpName> for crate::DeniedFor {
    /// The same op, refused (every op has its own refusal, by the same name).
    fn from(op: OpName) -> Self {
        match op {
            OpName::Meta => Self::Meta,
            OpName::Children => Self::Children,
            OpName::List => Self::List,
            OpName::Subscribe => Self::Subscribe,
            OpName::Unsubscribe => Self::Unsubscribe,
            OpName::Set => Self::Set,
            OpName::Invoke => Self::Invoke,
            OpName::Check => Self::Check,
            OpName::History => Self::History,
            OpName::Doc => Self::Doc,
        }
    }
}

wyrm_core::name_enum! {
    /// The documents `doc` reads (spec 01).
    pub(crate) enum DocSuffix as "doc suffix" {
        State => "~state",
        Def => "~def",
    }
}

/// An action call: a valid key segment and its arguments as sent.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Call {
    pub action: String,
    pub args: Option<Value>,
}

impl Call {
    /// The arguments the responder gets: an empty map when the client sent none.
    pub fn args_or_empty(&self) -> Value {
        self.args
            .clone()
            .unwrap_or_else(|| Value::Map(BTreeMap::new()))
    }
}

/// A request's op with the fields it carries.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Op {
    Meta,
    Children,
    List,
    Subscribe,
    /// Ends the caller's stream whose request id is `sub`.
    Unsubscribe {
        sub: u64,
    },
    Set {
        value: Value,
    },
    Invoke(Call),
    /// spec 05 0.2.33: the responder checks the call and does nothing.
    Check(Call),
    /// `args {from, to?, agg?, window?, limit?}`, parsed when it runs.
    History {
        args: Option<Value>,
    },
    Doc {
        suffix: DocSuffix,
    },
}

/// What an op needs on its key before it runs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Right {
    /// Nothing: it ends one of the caller's own streams.
    OwnStream,
    /// At least `.1` on `<key>/<suffix>` for every pair.
    On(Vec<(String, Perm)>),
    /// `.1` on some part of `<pattern>/<suffix>` (each sample is filtered after).
    Any(&'static str, Perm),
    /// As reading the point's value; at a watch key, as reading the point it
    /// records, else as its Get History (spec 05 0.1.10, ADR 0020).
    History,
}

/// How an op runs once its right holds.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Run {
    /// A `list` stream.
    List,
    /// A `subscribe` stream.
    Subscribe,
    /// Ends the stream `sub`.
    Close(u64),
    /// One request, one answer (`invoke` streams values before it).
    Once(Once),
}

/// A one-shot request with what it carries.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Once {
    Meta,
    Children,
    History(Option<Value>),
    Doc(DocSuffix),
    Set(Value),
    Check(Call),
    Invoke(Call),
}

impl Once {
    /// The wire name, for the step-up's record of the request.
    pub fn name(&self) -> OpName {
        match self {
            Once::Meta => OpName::Meta,
            Once::Children => OpName::Children,
            Once::History(_) => OpName::History,
            Once::Doc(_) => OpName::Doc,
            Once::Set(_) => OpName::Set,
            Once::Check(_) => OpName::Check,
            Once::Invoke(_) => OpName::Invoke,
        }
    }
}

fn on(suffix: impl Into<String>, perm: Perm) -> Right {
    Right::On(vec![(suffix.into(), perm)])
}

impl Op {
    /// Its wire name (audit records).
    pub fn name(&self) -> OpName {
        match self {
            Op::Meta => OpName::Meta,
            Op::Children => OpName::Children,
            Op::List => OpName::List,
            Op::Subscribe => OpName::Subscribe,
            Op::Unsubscribe { .. } => OpName::Unsubscribe,
            Op::Set { .. } => OpName::Set,
            Op::Invoke(_) => OpName::Invoke,
            Op::Check(_) => OpName::Check,
            Op::History { .. } => OpName::History,
            Op::Doc { .. } => OpName::Doc,
        }
    }

    /// The one table: each op's right and how it runs (see the module doc).
    pub fn route(self) -> (Right, Run) {
        match self {
            Op::Meta => (on("~meta", Perm::List), Run::Once(Once::Meta)),
            Op::Children => (on("~meta", Perm::List), Run::Once(Once::Children)),
            Op::List => (on("~meta", Perm::List), Run::List),
            Op::Subscribe => (Right::Any("~val", Perm::Read), Run::Subscribe),
            Op::Unsubscribe { sub } => (Right::OwnStream, Run::Close(sub)),
            Op::Set { value } => (on("~set", Perm::Write), Run::Once(Once::Set(value))),
            // `read` here; the action's own level is the responder's to check
            Op::Invoke(c) => (
                on(format!("~act/{}", c.action), Perm::Read),
                Run::Once(Once::Invoke(c)),
            ),
            Op::Check(c) => (
                on(format!("~act/{}", c.action), Perm::Read),
                Run::Once(Once::Check(c)),
            ),
            Op::History { args } => (Right::History, Run::Once(Once::History(args))),
            // as `list` on the node and on the document's own key (the token the responder
            // gets is for that key: a restricted node asks `list` there)
            Op::Doc { suffix } => (
                Right::On(vec![
                    ("~meta".to_owned(), Perm::List),
                    (suffix.name().to_owned(), Perm::List),
                ]),
                Run::Once(Once::Doc(suffix)),
            ),
        }
    }
}

/// Does `right` hold for grants `g` on the key `own` (the key as the own
/// site's)? `history` answers [`Right::History`], which needs the sites the
/// gateway reaches.
pub(crate) fn allowed(
    right: &Right,
    g: &Grants,
    own: &str,
    history: impl FnOnce() -> bool,
) -> bool {
    match right {
        Right::OwnStream => true,
        Right::On(needs) => needs
            .iter()
            .all(|(suffix, perm)| g.perm(&format!("{own}/{suffix}")) >= *perm),
        Right::Any(suffix, perm) => g.any(&format!("{own}/{suffix}"), *perm),
        Right::History => history(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_core::ptok::Grant;

    /// The audit names a refused op as the op itself: `DeniedFor` holds every op name,
    /// spelled the same (it was the op's text before it was typed).
    #[test]
    fn a_refused_op_keeps_its_name() {
        for op in OpName::ALL {
            assert_eq!(crate::DeniedFor::from(*op).name(), op.name());
        }
    }
    use wyrm_core::Status;

    fn sample(op: OpName) -> Op {
        let call = Call {
            action: "restart".into(),
            args: None,
        };
        match op {
            OpName::Meta => Op::Meta,
            OpName::Children => Op::Children,
            OpName::List => Op::List,
            OpName::Subscribe => Op::Subscribe,
            OpName::Unsubscribe => Op::Unsubscribe { sub: 1 },
            OpName::Set => Op::Set {
                value: Value::Float(1.5),
            },
            OpName::Invoke => Op::Invoke(call),
            OpName::Check => Op::Check(call),
            OpName::History => Op::History { args: None },
            OpName::Doc => Op::Doc {
                suffix: DocSuffix::State,
            },
        }
    }

    /// Every op the protocol has, with the right it needs: a new op is a compile error in
    /// `sample` and `route` until it is decided, and a changed right fails here.
    #[test]
    fn every_op_has_its_right() {
        let list = on("~meta", Perm::List);
        let act = on("~act/restart", Perm::Read);
        for name in OpName::ALL {
            let op = sample(*name);
            assert_eq!(op.name(), *name);
            let want = match name {
                OpName::Meta | OpName::Children | OpName::List => list.clone(),
                OpName::Subscribe => Right::Any("~val", Perm::Read),
                OpName::Unsubscribe => Right::OwnStream,
                OpName::Set => on("~set", Perm::Write),
                OpName::Invoke | OpName::Check => act.clone(),
                OpName::History => Right::History,
                OpName::Doc => Right::On(vec![
                    ("~meta".into(), Perm::List),
                    ("~state".into(), Perm::List),
                ]),
            };
            let (right, run) = op.route();
            assert_eq!(right, want, "{}", name.name());
            let streams = matches!(run, Run::List | Run::Subscribe | Run::Close(_));
            assert_eq!(
                streams,
                matches!(name, OpName::List | OpName::Subscribe | OpName::Unsubscribe),
                "{}",
                name.name()
            );
            if let Run::Once(o) = run {
                assert_eq!(o.name(), *name);
            }
        }
    }

    /// The right is checked against the grants: one level below refuses, the level passes,
    /// and `doc` needs both of its keys.
    #[test]
    fn a_right_holds_only_at_its_level() {
        let key = "wy/s/downstream/plc/t";
        let grants = |p: Perm| {
            Grants::new(vec![Grant {
                k: "wy/s/**".into(),
                p,
            }])
        };
        let below = |p: Perm| match p {
            Perm::Read => Perm::List,
            Perm::Write => Perm::Read,
            _ => Perm::None,
        };
        for name in OpName::ALL {
            let (right, _) = sample(*name).route();
            let need = match &right {
                Right::On(v) => v.iter().map(|(_, p)| *p).max().unwrap_or(Perm::None),
                Right::Any(_, p) => *p,
                Right::OwnStream | Right::History => continue,
            };
            assert!(
                allowed(&right, &grants(need), key, || false),
                "{}",
                name.name()
            );
            assert!(
                !allowed(&right, &grants(below(need)), key, || true),
                "{}",
                name.name()
            );
        }
        // `doc`: the node readable but its document not
        let (right, _) = sample(OpName::Doc).route();
        let g = Grants::new(vec![
            Grant {
                k: format!("{key}/~state"),
                p: Perm::None,
            },
            Grant {
                k: "wy/s/**".into(),
                p: Perm::List,
            },
        ]);
        assert!(!allowed(&right, &g, key, || true));
        // history asks the gateway
        assert!(allowed(&Right::History, &grants(Perm::None), key, || true));
        assert!(!allowed(
            &Right::History,
            &grants(Perm::Config),
            key,
            || false
        ));
    }

    /// An op this gateway does not serve, and an op without what it needs, are refused
    /// when the frame is read.
    #[test]
    fn unknown_ops_and_missing_fields_are_refused() {
        let decode = |name: &str, fields: &[(&str, Value)]| {
            let mut m: BTreeMap<String, Value> = fields
                .iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect();
            Op::decode(name, &mut m)
        };
        for name in ["drop", "Meta", "", "approve", "invoke "] {
            let (status, msg) = decode(name, &[]).unwrap_err();
            assert_eq!(status, Status::InvalidParameter);
            assert!(msg.starts_with("unknown op"), "{msg}");
        }
        let refused = |name: &str, fields: &[(&str, Value)]| decode(name, fields).is_err();
        assert!(refused("set", &[]));
        assert!(refused("invoke", &[]));
        assert!(refused("invoke", &[("action", Value::from("a/b"))]));
        assert!(refused("check", &[("action", Value::UInt(1))]));
        assert!(refused("doc", &[("suffix", Value::from("~meta"))]));
        assert!(refused("doc", &[]));
        assert!(refused("unsubscribe", &[("sub", Value::from("1"))]));
        assert_eq!(
            decode("invoke", &[("action", Value::from("restart"))]).unwrap(),
            Op::Invoke(Call {
                action: "restart".into(),
                args: None
            })
        );
        assert_eq!(
            decode("doc", &[("suffix", Value::from("~def"))]).unwrap(),
            Op::Doc {
                suffix: DocSuffix::Def
            }
        );
    }
}
