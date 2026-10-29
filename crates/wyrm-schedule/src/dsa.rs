//! Import of a DSA `dslink-dart-localschedule` 2.0.4 export (`Schedule.toJson`).

use jiff::civil::{Date, DateTime, Time};
use jiff::tz::TimeZone;
use jiff::{SignedDuration, Timestamp};
use serde_json::Value as Json;

use crate::convert::value_from_json;
use crate::model::{validate, Event, Freq, Invalid, Rule, RuleEnd, Schedule};
use wyrm_core::Value;

/// A DSA time string as `tz` local time. `Z` or an offset converts; no offset is taken as local.
fn local(field: &str, j: Option<&Json>, zone: &TimeZone) -> Result<DateTime, Invalid> {
    let Some(Json::String(s)) = j else {
        return Err(Invalid::new(field, "required, as a date-time text"));
    };
    if let Ok(ts) = s.parse::<Timestamp>() {
        return Ok(ts.to_zoned(zone.clone()).datetime());
    }
    s.parse::<DateTime>()
        .map_err(|_| Invalid::new(field, format!("not a date-time: {s:?}")))
}

fn date_time(date: Date, time: Time) -> DateTime {
    date.to_datetime(time)
}

/// Import a DSA export as schedule `id` in zone `tz`. Event ids are `e1…` in file order.
pub fn import(json: &str, id: &str, tz: &str) -> Result<Schedule, Invalid> {
    let zone = TimeZone::get(tz)
        .map_err(|_| Invalid::new("tz", format!("unknown IANA time zone {tz:?}")))?;
    let root: Json = serde_json::from_str(json)
        .map_err(|e| Invalid::new("json", format!("not valid JSON: {e}")))?;
    let Json::Object(root) = &root else {
        return Err(Invalid::new("json", "must be an object"));
    };
    let display = match root.get("name") {
        Some(Json::String(s)) => s.clone(),
        _ => id.to_string(),
    };
    let items: &[Json] = match root.get("events") {
        None | Some(Json::Null) => &[],
        Some(Json::Array(a)) => a,
        Some(_) => return Err(Invalid::new("events", "must be an array")),
    };
    let mut events = Vec::new();
    for (i, item) in items.iter().enumerate() {
        events.push(event(i, item, &zone)?);
    }
    let s = Schedule {
        id: id.to_string(),
        display,
        tz: tz.to_string(),
        default: root.get("value").map_or(Value::Null, value_from_json),
        enabled: true,
        next_event: u32::try_from(events.len() + 1).unwrap_or(u32::MAX),
        events,
    };
    validate(&s)?;
    Ok(s)
}

fn event(i: usize, item: &Json, zone: &TimeZone) -> Result<Event, Invalid> {
    let f = |name: &str| format!("events[{i}].{name}");
    let Json::Object(o) = item else {
        return Err(Invalid::new(format!("events[{i}]"), "must be an object"));
    };
    let Some(Json::Object(tr)) = o.get("timeRange") else {
        return Err(Invalid::new(f("timeRange"), "required, as an object"));
    };
    let tf = |name: &str| f(&format!("timeRange.{name}"));
    let s_time = local(&tf("sTime"), tr.get("sTime"), zone)?;
    let e_time = local(&tf("eTime"), tr.get("eTime"), zone)?;
    let s_date = local(&tf("sDate"), tr.get("sDate"), zone)?;
    let start = date_time(s_date.date(), s_time.time());
    let span: SignedDuration = e_time.duration_since(s_time);
    let end = start
        .checked_add(span)
        .map_err(|_| Invalid::new(tf("eTime"), "out of range"))?;
    let freq = tr
        .get("freq")
        .and_then(Json::as_u64)
        .ok_or_else(|| Invalid::new(tf("freq"), "required, a number 0 to 5"))?;
    let freq = match freq {
        0 => None,
        1 => Some(Freq::Hourly),
        2 => Some(Freq::Daily),
        3 => Some(Freq::Weekly),
        4 => Some(Freq::Monthly),
        5 => Some(Freq::Yearly),
        n => {
            return Err(Invalid::new(
                tf("freq"),
                format!("must be 0 (single) to 5 (yearly), got {n}"),
            ))
        }
    };
    let recurrence = match freq {
        None => None,
        Some(freq) => {
            let e_date = local(&tf("eDate"), tr.get("eDate"), zone)?;
            Some(Rule {
                freq,
                interval: 1,
                end: RuleEnd::Until(date_time(e_date.date(), s_time.time())),
                by_day: Vec::new(),
                by_month_day: Vec::new(),
                by_month: Vec::new(),
            })
        }
    };
    let priority = match o.get("priority") {
        None => 0,
        Some(p) => p
            .as_u64()
            .and_then(|n| u8::try_from(n).ok())
            .ok_or_else(|| Invalid::new(f("priority"), "must be 0 to 9"))?,
    };
    Ok(Event {
        id: format!("e{}", i + 1),
        display: match o.get("name") {
            Some(Json::String(s)) => s.clone(),
            _ => String::new(),
        },
        value: o.get("value").map_or(Value::Null, value_from_json),
        priority,
        special: matches!(o.get("special"), Some(Json::Bool(true))),
        start,
        end,
        recurrence,
    })
}
