//! Status codes carried in attachment key 0. Spec: 04-attachment.

crate::wire_enum! {
    pub enum Status {
        Ok = 0x00 => "ok",
        Initializing = 0x01 => "initializing",
        Refreshed = 0x02 => "refreshed",
        NotAvailable = 0x08 => "not_available",
        Closed = 0x10 => "closed",
        Disconnected = 0x20 => "disconnected",
        PermissionDenied = 0x21 => "permission_denied",
        InvalidMessage = 0x22 => "invalid_message",
        InvalidParameter = 0x23 => "invalid_parameter",
        Busy = 0x24 => "busy",
        InternalError = 0x25 => "internal_error",
        NotSupported = 0x26 => "not_supported",
        NotFound = 0x27 => "not_found",
        Timeout = 0x28 => "timeout",
        OutOfRange = 0x29 => "out_of_range",
        RateLimited = 0x2A => "rate_limited",
    }
}

/// Status group (spec 04): what a requester does with a code it may not know.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum StatusGroup {
    /// `0x00..=0x0F` — success or progress.
    Progress,
    /// `0x10..=0x1F` — the stream or request is closed.
    Closed,
    /// `0x20..` — error.
    Error,
}

impl StatusGroup {
    pub const fn of(code: u8) -> Self {
        match code {
            0x00..=0x0F => Self::Progress,
            0x10..=0x1F => Self::Closed,
            _ => Self::Error,
        }
    }
}

impl Status {
    pub const fn group(self) -> StatusGroup {
        StatusGroup::of(self.code())
    }
    pub fn is_success(self) -> bool {
        self.group() == StatusGroup::Progress
    }
    pub fn is_error(self) -> bool {
        self.group() == StatusGroup::Error
    }
}

/// User-defined status range (spec 04).
pub const USER_RANGE: core::ops::RangeInclusive<u8> = 0x40..=0x4F;

/// Status as it travels on the wire: known, user-defined (0x40..=0x4F) or unknown.
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
    pub fn group(self) -> StatusGroup {
        StatusGroup::of(self.code())
    }
    pub fn is_error(self) -> bool {
        self.group() == StatusGroup::Error
    }
}

impl From<u8> for StatusCode {
    fn from(c: u8) -> Self {
        match Status::try_from(c) {
            Ok(s) => StatusCode::Known(s),
            Err(c) if USER_RANGE.contains(&c) => StatusCode::User(c),
            Err(c) => StatusCode::Unknown(c),
        }
    }
}

impl From<Status> for StatusCode {
    fn from(s: Status) -> Self {
        StatusCode::Known(s)
    }
}
