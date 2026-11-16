//! Quality and status codes read from a `Value` (a script result, an answer map, a saved
//! state). One decoder each, and each fails closed: only a valid code (an unsigned integer
//! in the table) or a valid wire name (`spec/tables.json`) is taken; a fraction, a
//! negative number, NaN, a number out of range, an unknown name or a missing field gives
//! `bad` / `internal_error`, never `good` / `ok` (docs/flow-blocks.md "Quality and status
//! codes from a value").

use wyrm_core::status::StatusCode;
use wyrm_core::{Quality, Status, StatusGroup, Value};

/// The code of `v` when it is an unsigned integer that fits a `u8`, or the code of the
/// table entry whose wire name `v` is (`from_name` of its `wire_enum!`).
fn code_of<T>(
    v: Option<&Value>,
    from_name: fn(&str) -> Option<T>,
    code: fn(T) -> u8,
) -> Option<u8> {
    match v? {
        Value::UInt(u) => u8::try_from(*u).ok(),
        Value::Str(s) => from_name(s).map(code),
        _ => None,
    }
}

/// The quality `v` names, or `None` for anything that is not a valid code or name.
pub fn quality(v: Option<&Value>) -> Option<Quality> {
    let c = code_of(v, Quality::from_name, Quality::code)?;
    Quality::try_from(c).ok()
}

/// The quality `v` names; anything else (also a missing field) is `bad`.
pub fn quality_of(v: Option<&Value>) -> Quality {
    quality(v).unwrap_or(Quality::Bad)
}

/// The status `v` names; anything else (also a missing field, and a user-defined or
/// unknown code, which has no `Status`) is `internal_error`.
pub fn status_of(v: Option<&Value>) -> Status {
    match code_of(v, Status::from_name, Status::code) {
        Some(c) => Status::try_from(c).unwrap_or(Status::InternalError),
        None => Status::InternalError,
    }
}

/// The status of a failed answer: as [`status_of`], but a user-defined or unknown code
/// travels as it is (CONTRIBUTING "Wire enums" rule 3), and a code that is not in the error
/// group (`ok`, a progress or a closed code) is `internal_error`: a failure never reads
/// as a success.
pub fn error_status_of(v: Option<&Value>) -> StatusCode {
    let s = match code_of(v, Status::from_name, Status::code) {
        Some(c) => StatusCode::from(c),
        None => StatusCode::Known(Status::InternalError),
    };
    if s.group() == StatusGroup::Error {
        s
    } else {
        StatusCode::Known(Status::InternalError)
    }
}

/// A failed action or read as its worker task hands it to its node: the map
/// `{code, message}` (spec 04 status, the error's text). The one decoder of that answer
/// for the command blocks and the readers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Failure {
    /// [`error_status_of`]: a missing, fractional, negative or unknown code, or one
    /// that is not an error, is `internal_error`; a user-defined error code travels.
    pub code: StatusCode,
    /// The text, or empty when there is none (or it is no text).
    pub message: String,
}

impl Failure {
    pub fn of(m: &crate::def::Map) -> Self {
        Self {
            code: error_status_of(m.get("code")),
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

    fn cases() -> Vec<(&'static str, Option<Value>)> {
        vec![
            ("fraction", Some(Value::Float(0.9))),
            ("whole float", Some(Value::Float(2.0))),
            ("zero float", Some(Value::Float(0.0))),
            ("negative", Some(Value::Int(-1))),
            ("NaN", Some(Value::Float(f64::NAN))),
            ("1e9 float", Some(Value::Float(1e9))),
            ("1e9", Some(Value::UInt(1_000_000_000))),
            ("256", Some(Value::UInt(256))),
            ("unknown name", Some(Value::from("worse"))),
            ("name with a case", Some(Value::from("Good"))),
            ("null", Some(Value::Null)),
            ("bool", Some(Value::Bool(false))),
            ("missing", None),
        ]
    }

    #[test]
    fn quality_takes_only_a_code_or_a_name() {
        for (what, v) in cases() {
            assert_eq!(quality(v.as_ref()), None, "{what}");
            assert_eq!(quality_of(v.as_ref()), Quality::Bad, "{what}");
        }
        assert_eq!(quality_of(Some(&Value::UInt(3))), Quality::Bad, "3");
        for q in Quality::ALL {
            let code = Value::UInt(u64::from(q.code()));
            assert_eq!(quality_of(Some(&code)), *q);
            assert_eq!(quality_of(Some(&Value::from(q.name()))), *q);
        }
        assert_eq!(quality_of(Some(&Value::from("bad"))), Quality::Bad);
        assert_eq!(quality_of(Some(&Value::from("good"))), Quality::Good);
    }

    #[test]
    fn status_takes_only_a_code_or_a_name() {
        for (what, v) in cases() {
            assert_eq!(status_of(v.as_ref()), Status::InternalError, "{what}");
            assert_eq!(
                error_status_of(v.as_ref()),
                StatusCode::Known(Status::InternalError),
                "{what}"
            );
        }
        for s in Status::ALL {
            let code = Value::UInt(u64::from(s.code()));
            assert_eq!(status_of(Some(&code)), *s);
            assert_eq!(status_of(Some(&Value::from(s.name()))), *s);
            // on a failure path only an error code passes
            let want = if s.is_error() {
                StatusCode::Known(*s)
            } else {
                StatusCode::Known(Status::InternalError)
            };
            assert_eq!(error_status_of(Some(&code)), want, "{}", s.name());
            assert_eq!(error_status_of(Some(&Value::from(s.name()))), want);
        }
        // a user-defined code has no `Status`; on a failure path it travels as it is
        let user = Value::UInt(0x41);
        assert_eq!(status_of(Some(&user)), Status::InternalError);
        assert_eq!(error_status_of(Some(&user)), StatusCode::User(0x41));
        // an unknown error-group code too; an unknown progress code does not pass
        assert_eq!(
            error_status_of(Some(&Value::UInt(0x30))),
            StatusCode::Unknown(0x30)
        );
        assert_eq!(
            error_status_of(Some(&Value::UInt(0x05))),
            StatusCode::Known(Status::InternalError)
        );
    }
}
