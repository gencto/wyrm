//! Driver-facing error: a spec status plus a short message for `attachment.err`.

use wyrm_core::Status;

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
#[error("{status:?}: {message}")]
pub struct LinkError {
    pub status: Status,
    /// Goes to `attachment.err`. Must not contain secrets or `ptok`.
    pub message: String,
}

impl LinkError {
    pub fn new(status: Status, message: impl Into<String>) -> Self {
        Self {
            status,
            message: message.into(),
        }
    }

    pub fn not_found(what: impl Into<String>) -> Self {
        Self::new(Status::NotFound, what)
    }

    pub fn not_supported(what: impl Into<String>) -> Self {
        Self::new(Status::NotSupported, what)
    }

    pub fn invalid_parameter(what: impl Into<String>) -> Self {
        Self::new(Status::InvalidParameter, what)
    }

    pub fn internal(what: impl Into<String>) -> Self {
        Self::new(Status::InternalError, what)
    }

    pub fn timeout(what: impl Into<String>) -> Self {
        Self::new(Status::Timeout, what)
    }
}

impl From<wyrm_core::keyspace::KeyError> for LinkError {
    fn from(e: wyrm_core::keyspace::KeyError) -> Self {
        Self::invalid_parameter(e.to_string())
    }
}

impl From<zenoh::Error> for LinkError {
    fn from(e: zenoh::Error) -> Self {
        Self::new(Status::Disconnected, e.to_string())
    }
}

pub type Result<T, E = LinkError> = core::result::Result<T, E>;
