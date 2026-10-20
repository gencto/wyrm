//! Status codes carried in attachment key 0. Spec: 04-attachment.

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum Status {
    Ok = 0x00,
    Initializing = 0x01,
    Refreshed = 0x02,
    NotAvailable = 0x08,
    Closed = 0x10,
    Disconnected = 0x20,
    PermissionDenied = 0x21,
    InvalidMessage = 0x22,
    InvalidParameter = 0x23,
    Busy = 0x24,
    InternalError = 0x25,
    NotSupported = 0x26,
    NotFound = 0x27,
    Timeout = 0x28,
    OutOfRange = 0x29,
    RateLimited = 0x2A,
}

impl Status {
    pub fn is_success(self) -> bool {
        (self as u8) < 0x10
    }
    pub fn is_error(self) -> bool {
        (self as u8) >= 0x20
    }
    pub fn code(self) -> u8 {
        self as u8
    }
}

/// Status as it travels on the wire: known or user-defined (0x40..=0x4F) or unknown.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum StatusCode {
    Known(Status),
    User(u8),
    Unknown(u8),
}

impl StatusCode {
    pub fn code(self) -> u8 {
        match self {
            StatusCode::Known(s) => s.code(),
            StatusCode::User(c) | StatusCode::Unknown(c) => c,
        }
    }
    pub fn is_error(self) -> bool {
        self.code() >= 0x20
    }
}

impl From<u8> for StatusCode {
    fn from(c: u8) -> Self {
        use Status::*;
        let known = match c {
            0x00 => Ok,
            0x01 => Initializing,
            0x02 => Refreshed,
            0x08 => NotAvailable,
            0x10 => Closed,
            0x20 => Disconnected,
            0x21 => PermissionDenied,
            0x22 => InvalidMessage,
            0x23 => InvalidParameter,
            0x24 => Busy,
            0x25 => InternalError,
            0x26 => NotSupported,
            0x27 => NotFound,
            0x28 => Timeout,
            0x29 => OutOfRange,
            0x2A => RateLimited,
            0x40..=0x4F => return StatusCode::User(c),
            _ => return StatusCode::Unknown(c),
        };
        StatusCode::Known(known)
    }
}

impl From<Status> for StatusCode {
    fn from(s: Status) -> Self {
        StatusCode::Known(s)
    }
}
