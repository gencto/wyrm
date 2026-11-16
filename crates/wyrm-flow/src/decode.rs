//! Decoders of the maps the flow's worker tasks hand their nodes (docs/rust-rules.md
//! rule 7: one typed decoder per `Value` shape, in a `decode.rs`).

use wyrm_core::status::StatusCode;
use wyrm_core::{Status, Value};

/// A failed action or read as its worker task hands it to its node: the map
/// `{code, message}` (spec 04 status, the error's text). The one decoder of that answer
/// for the command blocks and the readers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Failure {
    /// [`crate::codes::error_status_of`]: a missing, fractional, negative or unknown code, or one
    /// that is not an error, is `internal_error`; a user-defined error code travels.
    pub code: StatusCode,
    /// The text, or empty when there is none (or it is no text).
    pub message: String,
}

impl Failure {
    pub fn of(m: &crate::def::Map) -> Self {
        Self {
            code: crate::codes::error_status_of(m.get("code")),
            message: match m.get("message") {
                Some(Value::Str(s)) => s.clone(),
                _ => String::new(),
            },
        }
    }

    /// The code as a table status: a user-defined or unknown one is `internal_error`.
    pub fn status(&self) -> Status {
        match self.code {
            StatusCode::Known(s) => s,
            _ => Status::InternalError,
        }
    }
}

/// The run an answer of a worker task belongs to: its `seq` as the task wrote it, an
/// unsigned integer. Anything else (a float, which `as_f64` compared after a cast to
/// `f64` that rounds above 2^53, a negative number, text) belongs to no run.
pub fn seq_of(m: &crate::def::Map) -> Option<u64> {
    match m.get("seq") {
        Some(Value::UInt(s)) => Some(*s),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_failure_never_reads_as_a_success() {
        let map = |kv: &[(&str, Value)]| -> crate::def::Map {
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect()
        };
        let f = Failure::of(&map(&[
            ("code", Value::UInt(u64::from(Status::Timeout.code()))),
            ("message", Value::from("late")),
        ]));
        assert_eq!((f.status(), f.message.as_str()), (Status::Timeout, "late"));
        for code in [
            None,
            Some(Value::Float(0.0)),
            Some(Value::Float(f64::from(Status::Timeout.code()) + 0.5)),
            Some(Value::Int(-1)),
            Some(Value::UInt(u64::from(Status::Ok.code()))),
            Some(Value::from("ok")),
        ] {
            let mut m = map(&[("message", Value::UInt(3))]);
            if let Some(c) = &code {
                m.insert("code".into(), c.clone());
            }
            let f = Failure::of(&m);
            assert_eq!(f.code, StatusCode::Known(Status::InternalError), "{code:?}");
            assert_eq!(f.status(), Status::InternalError);
            assert_eq!(f.message, "", "no text is no message");
        }
        let user = Failure::of(&map(&[("code", Value::UInt(0x41))]));
        assert_eq!(user.code, StatusCode::User(0x41));
        assert_eq!(user.status(), Status::InternalError);
    }

    #[test]
    fn a_seq_is_the_integer_written() {
        let m = |v: Value| -> crate::def::Map { [("seq".to_owned(), v)].into() };
        let big = (1u64 << 53) + 1;
        assert_eq!(seq_of(&m(Value::UInt(big))), Some(big));
        // a float equal after a cast to f64 is no seq (2^53 + 1 rounds to 2^53)
        assert_eq!(seq_of(&m(Value::Float((1u64 << 53) as f64))), None);
        assert_eq!(seq_of(&m(Value::Float(3.0))), None);
        assert_eq!(seq_of(&m(Value::Int(-3))), None);
        assert_eq!(seq_of(&crate::def::Map::new()), None);
    }
}
