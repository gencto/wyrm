//! The request frame's decoder (rule 7 of `docs/rust-rules.md`: one typed
//! decoder per `Value` shape): a frame becomes a [`Req`] with an [`Op`] that
//! carries what it needs, or a refusal, before anything else reads it.

use super::op::{Call, DocSuffix, Op, OpName};
use super::Req;
use std::collections::BTreeMap;
use wyrm_core::codec::from_slice;
use wyrm_core::{Status, Value};

/// A frame decoded into a request, or the request id (0 when none could be
/// read), the status and the message of its refusal: a frame that is not a
/// request map is `invalid_message`; an op this gateway does not serve, or one
/// without a field it needs, `invalid_parameter` ([`Op::decode`]).
pub(super) fn parse(bytes: &[u8]) -> Result<Req, (u64, Status, String)> {
    let malformed = |id: u64, msg: String| (id, Status::InvalidMessage, msg);
    let v: Value = from_slice(bytes).map_err(|e| malformed(0, format!("frame: {e}")))?;
    let Value::Map(mut m) = v else {
        return Err(malformed(0, "frame must be a map".into()));
    };
    let Some(Value::UInt(id)) = m.get("id").cloned() else {
        return Err(malformed(0, "id: uint required".into()));
    };
    let mut text = |k: &str| match m.remove(k) {
        None => Ok(None),
        Some(Value::Str(s)) => Ok(Some(s)),
        Some(_) => Err(malformed(id, format!("{k}: text required"))),
    };
    let name = text("op")?.ok_or_else(|| malformed(id, "op required".to_owned()))?;
    let key = text("key")?.unwrap_or_default();
    let op = Op::decode(&name, &mut m).map_err(|(status, msg)| (id, status, msg))?;
    if !matches!(op, Op::Unsubscribe { .. }) && key.is_empty() {
        return Err(malformed(id, "key required".into()));
    }
    Ok(Req { id, key, op })
}

impl Op {
    /// Decode the op of a frame from its fields (`value`, `action`, `args`,
    /// `sub`, `suffix` taken out of `m`). `Err` is the refusal's status and
    /// message: an unknown op, or a field the op needs missing or of the
    /// wrong type.
    pub fn decode(name: &str, m: &mut BTreeMap<String, Value>) -> Result<Self, (Status, String)> {
        let bad = |msg: &str| (Status::InvalidParameter, msg.to_owned());
        let Some(op) = OpName::from_name(name) else {
            return Err((Status::InvalidParameter, format!("unknown op {name:?}")));
        };
        let call = |m: &mut BTreeMap<String, Value>| -> Result<Call, (Status, String)> {
            let action = match m.remove("action") {
                Some(Value::Str(a)) if wyrm_core::keyspace::validate_segment(&a).is_ok() => a,
                _ => return Err(bad("action: valid segment required")),
            };
            Ok(Call {
                action,
                args: m.remove("args"),
            })
        };
        Ok(match op {
            OpName::Meta => Op::Meta,
            OpName::Children => Op::Children,
            OpName::List => Op::List,
            OpName::Subscribe => Op::Subscribe,
            OpName::Unsubscribe => match m.remove("sub") {
                Some(Value::UInt(sub)) => Op::Unsubscribe { sub },
                _ => return Err(bad("sub: uint required")),
            },
            OpName::Set => match m.remove("value") {
                Some(value) => Op::Set { value },
                None => return Err(bad("value required")),
            },
            OpName::Invoke => Op::Invoke(call(m)?),
            OpName::Check => Op::Check(call(m)?),
            OpName::History => Op::History {
                args: m.remove("args"),
            },
            OpName::Doc => match m.remove("suffix") {
                Some(Value::Str(s)) => match DocSuffix::from_name(&s) {
                    Some(suffix) => Op::Doc { suffix },
                    None => return Err(bad("suffix: ~state or ~def required")),
                },
                _ => return Err(bad("suffix: ~state or ~def required")),
            },
        })
    }
}
