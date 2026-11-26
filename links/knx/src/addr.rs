//! KNX addresses: a group address (16 bits, written in three levels
//! `main/middle/sub`, two levels `main/sub` or as a plain number) and an
//! individual address (`area.line.device`).

use std::fmt;

/// Why an address text is refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AddrError {
    #[error("empty address")]
    Empty,
    #[error("{0:?} is not a number")]
    NotANumber(String),
    #[error("{part} {value} is above {max}")]
    TooLarge {
        part: &'static str,
        value: u32,
        max: u32,
    },
    #[error("a group address has one, two or three parts (1/2/3, 1/515 or 2563)")]
    GroupShape,
    #[error("0/0/0 is the broadcast address, not a group")]
    Broadcast,
    #[error("an individual address has three parts (1.1.5)")]
    IndividualShape,
}

fn part(text: &str, name: &'static str, max: u32) -> Result<u16, AddrError> {
    let text = text.trim();
    if text.is_empty() {
        return Err(AddrError::Empty);
    }
    let value: u32 = text
        .parse()
        .map_err(|_e: std::num::ParseIntError| AddrError::NotANumber(text.to_owned()))?;
    match u16::try_from(value) {
        Ok(v) if value <= max => Ok(v),
        _ => Err(AddrError::TooLarge {
            part: name,
            value,
            max,
        }),
    }
}

/// A group address.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct GroupAddr(pub u16);

impl GroupAddr {
    /// `1/2/3` (main 0…31, middle 0…7, sub 0…255), `1/515` (main 0…31,
    /// sub 0…2047) or `2563` (1…65535).
    pub fn parse(text: &str) -> Result<Self, AddrError> {
        let text = text.trim();
        if text.is_empty() {
            return Err(AddrError::Empty);
        }
        let parts: Vec<&str> = text.split('/').collect();
        let raw = match parts.as_slice() {
            [raw] => part(raw, "the address", 0xFFFF)?,
            [main, sub] => {
                (part(main, "the main group", 31)? << 11) | part(sub, "the subgroup", 2047)?
            }
            [main, middle, sub] => {
                (part(main, "the main group", 31)? << 11)
                    | (part(middle, "the middle group", 7)? << 8)
                    | part(sub, "the subgroup", 255)?
            }
            _ => return Err(AddrError::GroupShape),
        };
        if raw == 0 {
            return Err(AddrError::Broadcast);
        }
        Ok(GroupAddr(raw))
    }

    pub fn main(self) -> u16 {
        self.0 >> 11
    }

    pub fn middle(self) -> u16 {
        (self.0 >> 8) & 0x07
    }

    pub fn sub(self) -> u16 {
        self.0 & 0xFF
    }
}

/// Three levels, the form ETS shows by default.
impl fmt::Display for GroupAddr {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}/{}/{}", self.main(), self.middle(), self.sub())
    }
}

/// An individual (device) address.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Hash)]
pub struct IndividualAddr(pub u16);

impl IndividualAddr {
    /// `1.1.5`: area 0…15, line 0…15, device 0…255.
    pub fn parse(text: &str) -> Result<Self, AddrError> {
        let parts: Vec<&str> = text.trim().split('.').collect();
        let [area, line, device] = parts.as_slice() else {
            return Err(AddrError::IndividualShape);
        };
        Ok(IndividualAddr(
            (part(area, "the area", 15)? << 12)
                | (part(line, "the line", 15)? << 8)
                | part(device, "the device", 255)?,
        ))
    }
}

impl fmt::Display for IndividualAddr {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}.{}.{}",
            self.0 >> 12,
            (self.0 >> 8) & 0x0F,
            self.0 & 0xFF
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn group_addresses_in_three_forms() {
        assert_eq!(GroupAddr::parse("1/2/3"), Ok(GroupAddr(0x0A03)));
        assert_eq!(GroupAddr::parse(" 1/515 "), Ok(GroupAddr(0x0A03)));
        assert_eq!(GroupAddr::parse("2563"), Ok(GroupAddr(0x0A03)));
        assert_eq!(GroupAddr::parse("31/7/255"), Ok(GroupAddr(0xFFFF)));
        assert_eq!(GroupAddr::parse("31/2047"), Ok(GroupAddr(0xFFFF)));
        assert_eq!(GroupAddr(0x0A03).to_string(), "1/2/3");
        assert_eq!(GroupAddr(0xFFFF).to_string(), "31/7/255");
    }

    #[test]
    fn refused_group_addresses() {
        assert_eq!(GroupAddr::parse(""), Err(AddrError::Empty));
        assert_eq!(GroupAddr::parse("0/0/0"), Err(AddrError::Broadcast));
        assert_eq!(GroupAddr::parse("0"), Err(AddrError::Broadcast));
        assert_eq!(GroupAddr::parse("1/2/3/4"), Err(AddrError::GroupShape));
        assert!(matches!(
            GroupAddr::parse("32/0/1"),
            Err(AddrError::TooLarge { max: 31, .. })
        ));
        assert!(matches!(
            GroupAddr::parse("1/8/1"),
            Err(AddrError::TooLarge { max: 7, .. })
        ));
        assert!(matches!(
            GroupAddr::parse("1/2/256"),
            Err(AddrError::TooLarge { max: 255, .. })
        ));
        assert!(matches!(
            GroupAddr::parse("1/2048"),
            Err(AddrError::TooLarge { max: 2047, .. })
        ));
        assert!(matches!(
            GroupAddr::parse("65536"),
            Err(AddrError::TooLarge { .. })
        ));
        assert!(matches!(
            GroupAddr::parse("1/a/3"),
            Err(AddrError::NotANumber(_))
        ));
        assert!(matches!(GroupAddr::parse("1//3"), Err(AddrError::Empty)));
        assert!(matches!(
            GroupAddr::parse("-1"),
            Err(AddrError::NotANumber(_))
        ));
    }

    #[test]
    fn individual_addresses() {
        assert_eq!(IndividualAddr::parse("1.1.5"), Ok(IndividualAddr(0x1105)));
        assert_eq!(
            IndividualAddr::parse("15.15.255"),
            Ok(IndividualAddr(0xFFFF))
        );
        assert_eq!(IndividualAddr(0x1105).to_string(), "1.1.5");
        assert_eq!(
            IndividualAddr::parse("1.1"),
            Err(AddrError::IndividualShape)
        );
        assert!(matches!(
            IndividualAddr::parse("16.0.1"),
            Err(AddrError::TooLarge { max: 15, .. })
        ));
    }
}
