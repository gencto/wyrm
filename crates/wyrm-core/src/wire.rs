//! `wire_enum!`: one declaration per spec code table.
//!
//! Each variant lists its wire code and its spec name (the name used in
//! `spec/tables.json`). The macro generates the `#[repr(u8)]` enum and:
//!
//! * `code(self) -> u8` and `From<Self> for u8` — the only way to get a code;
//!   do not write `as u8` at call sites;
//! * `TryFrom<u8>` (`Err` carries the unknown code) — the only way back;
//! * `name(self) -> &'static str` and `ALL` — used by the test that checks
//!   every table against `spec/tables.json`.
//!
//! Extra derives (`Default`, `PartialOrd`, `Ord`) go on the enum as usual.
//!
//! ```
//! wyrm_core::wire_enum! {
//!     /// Example table.
//!     #[derive(Default)]
//!     pub enum Level {
//!         #[default]
//!         Low = 0 => "low",
//!         High = 1 => "high",
//!     }
//! }
//! assert_eq!(Level::High.code(), 1);
//! assert_eq!(Level::try_from(1), Ok(Level::High));
//! assert_eq!(Level::try_from(9), Err(9));
//! assert_eq!(Level::Low.name(), "low");
//! ```

#[macro_export]
macro_rules! wire_enum {
    (
        $(#[$meta:meta])*
        $vis:vis enum $ty:ident {
            $(
                $(#[$vmeta:meta])*
                $variant:ident = $code:literal => $name:literal
            ),+ $(,)?
        }
    ) => {
        $(#[$meta])*
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        #[repr(u8)]
        $vis enum $ty {
            $( $(#[$vmeta])* $variant = $code, )+
        }

        impl $ty {
            /// Every variant, in declaration order.
            pub const ALL: &'static [Self] = &[$(Self::$variant),+];

            /// Wire code.
            pub const fn code(self) -> u8 {
                self as u8
            }

            /// Spec name, as in `spec/tables.json`.
            pub const fn name(self) -> &'static str {
                match self {
                    $(Self::$variant => $name,)+
                }
            }
        }

        impl ::core::convert::From<$ty> for u8 {
            fn from(v: $ty) -> u8 {
                v.code()
            }
        }

        impl ::core::convert::TryFrom<u8> for $ty {
            type Error = u8;
            fn try_from(code: u8) -> ::core::result::Result<Self, u8> {
                match code {
                    $($code => Ok(Self::$variant),)+
                    other => Err(other),
                }
            }
        }
    };
}
