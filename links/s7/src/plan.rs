//! The read plan: points merged into spans per area and DB, and spans cut
//! into Read Var items packed into requests that fit the negotiated PDU.
//! Pure: no I/O.
//!
//! Merging does not depend on the PDU (two points merge when the bytes
//! between them are at most `max_gap`); packing does, so it runs once per
//! negotiated PDU size and is cached by the driver.

use crate::addr::Area;
use crate::proto::{read_req_len, reply_item_len, READ_REP_FIXED};
use std::collections::BTreeMap;

/// Where one point's value lies.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Loc {
    pub area: Area,
    pub db: u16,
    /// Byte offset, or the timer/counter number.
    pub start: u32,
    /// Bytes, or timers/counters (2 bytes each).
    pub units: u32,
}

impl Loc {
    fn end(&self) -> u32 {
        self.start + self.units
    }
}

/// Points read together: one contiguous range of an area.
#[derive(Debug, Clone, PartialEq)]
pub struct Span {
    pub area: Area,
    pub db: u16,
    pub start: u32,
    pub units: u32,
    /// Indexes of the member points.
    pub members: Vec<usize>,
}

impl Span {
    pub fn bytes(&self) -> usize {
        (self.units * self.area.unit_bytes()) as usize
    }

    /// The bytes of member `loc` in this span's buffer.
    pub fn range(&self, loc: &Loc) -> std::ops::Range<usize> {
        let ub = self.area.unit_bytes() as usize;
        let from = (loc.start - self.start) as usize * ub;
        from..from + loc.units as usize * ub
    }
}

/// Merge `locs` into spans: same area and DB, at most `max_gap` bytes apart
/// (timers and counters: `max_gap / 2` numbers). Points in `alone` are read
/// on their own (a failed merged read showed that they fail).
pub fn merge(locs: &[Loc], max_gap: u32, alone: impl Fn(usize) -> bool) -> Vec<Span> {
    let mut groups: BTreeMap<(Area, u16), Vec<usize>> = BTreeMap::new();
    for (i, l) in locs.iter().enumerate() {
        groups.entry((l.area, l.db)).or_default().push(i);
    }
    let mut spans = Vec::new();
    for ((area, db), mut idx) in groups {
        idx.sort_by_key(|&i| (locs[i].start, locs[i].units));
        let gap = max_gap / area.unit_bytes();
        let mut cur: Option<Span> = None;
        for i in idx {
            let l = locs[i];
            if alone(i) {
                spans.push(Span {
                    area,
                    db,
                    start: l.start,
                    units: l.units,
                    members: vec![i],
                });
                continue;
            }
            match &mut cur {
                Some(s) if l.start <= s.start + s.units + gap => {
                    s.units = s.units.max(l.end() - s.start);
                    s.members.push(i);
                }
                _ => {
                    if let Some(s) = cur.take() {
                        spans.push(s);
                    }
                    cur = Some(Span {
                        area,
                        db,
                        start: l.start,
                        units: l.units,
                        members: vec![i],
                    });
                }
            }
        }
        spans.extend(cur);
    }
    spans
}

/// One Read Var item: a part of a span.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Chunk {
    pub span: usize,
    /// Units from the span's start.
    pub offset: u32,
    pub units: u32,
}

/// The most data bytes one reply item may carry at `pdu` (even, so no fill
/// byte follows).
pub fn max_item_bytes(pdu: u16) -> usize {
    (usize::from(pdu).saturating_sub(READ_REP_FIXED + 4)) & !1
}

/// Cut `spans` into items of at most [`max_item_bytes`] and pack them into
/// requests in order: a request takes items while the request and its
/// reply fit `pdu` and it has fewer than `max_items`.
pub fn pack(spans: &[Span], pdu: u16, max_items: usize) -> Vec<Vec<Chunk>> {
    let pdu = usize::from(pdu);
    let max_items = max_items.max(1);
    let mut reqs = Vec::new();
    let mut cur: Vec<Chunk> = Vec::new();
    let mut rep = READ_REP_FIXED;
    for (si, s) in spans.iter().enumerate() {
        let ub = s.area.unit_bytes() as usize;
        let per = (max_item_bytes(pdu as u16) / ub).clamp(1, usize::from(u16::MAX)) as u32;
        let mut offset = 0;
        while offset < s.units {
            let units = per.min(s.units - offset);
            let bytes = units as usize * ub;
            let full = cur.len() >= max_items
                || read_req_len(cur.len() + 1) > pdu
                || rep + reply_item_len(bytes) > pdu;
            if full && !cur.is_empty() {
                reqs.push(std::mem::take(&mut cur));
                rep = READ_REP_FIXED;
            }
            cur.push(Chunk {
                span: si,
                offset,
                units,
            });
            rep += reply_item_len(bytes);
            offset += units;
        }
    }
    if !cur.is_empty() {
        reqs.push(cur);
    }
    reqs
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::ITEM_SPEC;

    fn db(start: u32, units: u32) -> Loc {
        Loc {
            area: Area::Db,
            db: 1,
            start,
            units,
        }
    }

    #[test]
    fn merges_by_area_db_and_gap() {
        let locs = [
            db(0, 2),
            db(2, 4),  // adjacent
            db(10, 2), // gap 4: merged at max_gap 4
            db(20, 1), // gap 8: own span
            db(3, 1),  // inside
            Loc { db: 2, ..db(0, 2) },
            Loc {
                area: Area::Marker,
                db: 0,
                start: 0,
                units: 1,
            },
            Loc {
                area: Area::Timer,
                db: 0,
                start: 3,
                units: 1,
            },
            Loc {
                area: Area::Timer,
                db: 0,
                start: 5,
                units: 1,
            },
        ];
        let spans = merge(&locs, 4, |_| false);
        let got: Vec<(Area, u16, u32, u32, Vec<usize>)> = spans
            .iter()
            .map(|s| (s.area, s.db, s.start, s.units, s.members.clone()))
            .collect();
        assert_eq!(
            got,
            vec![
                (Area::Marker, 0, 0, 1, vec![6]),
                (Area::Db, 1, 0, 12, vec![0, 1, 4, 2]),
                (Area::Db, 1, 20, 1, vec![3]),
                (Area::Db, 2, 0, 2, vec![5]),
                // timers: a gap of 1 number (2 bytes) at max_gap 4
                (Area::Timer, 0, 3, 3, vec![7, 8]),
            ]
        );
        assert_eq!(spans[1].range(&locs[2]), 10..12);
        assert_eq!(spans[4].bytes(), 6);
        assert_eq!(spans[4].range(&locs[8]), 4..6);
        // max_gap 0: only touching or overlapping ranges
        assert_eq!(merge(&locs[..3], 0, |_| false).len(), 2);
        // a point read alone stays alone
        let alone = merge(&locs[..3], 8, |i| i == 1);
        let mut members: Vec<Vec<usize>> = alone.iter().map(|s| s.members.clone()).collect();
        members.sort();
        assert_eq!(members, vec![vec![0, 2], vec![1]]);
    }

    /// Requests and replies fit the PDU, the item count is capped, and a
    /// span longer than one item is cut.
    #[test]
    fn packs_into_the_pdu() {
        let check = |spans: &[Span], pdu: u16, max_items: usize| {
            let reqs = pack(spans, pdu, max_items);
            for r in &reqs {
                assert!(!r.is_empty() && r.len() <= max_items);
                assert!(12 + ITEM_SPEC * r.len() <= pdu as usize, "request fits");
                let rep: usize = 14
                    + r.iter()
                        .map(|c| {
                            reply_item_len((c.units * spans[c.span].area.unit_bytes()) as usize)
                        })
                        .sum::<usize>();
                assert!(rep <= pdu as usize, "reply {rep} fits {pdu}");
            }
            // every unit of every span once, in order
            for (si, s) in spans.iter().enumerate() {
                let mut at = 0;
                for c in reqs.iter().flatten().filter(|c| c.span == si) {
                    assert_eq!(c.offset, at);
                    at += c.units;
                }
                assert_eq!(at, s.units);
            }
            reqs
        };
        let one = |units| Span {
            area: Area::Db,
            db: 1,
            start: 0,
            units,
            members: vec![0],
        };
        // a STRING[254] (256 bytes) on a 240-byte PDU: 222 + 34
        let reqs = check(&[one(256)], 240, 20);
        assert_eq!(reqs.len(), 2);
        assert_eq!(reqs[0][0].units as usize, max_item_bytes(240));
        assert_eq!(max_item_bytes(240), 222);
        // 30 small items: the item cap and the request size both bind
        let many: Vec<Span> = (0..30).map(|_| one(2)).collect();
        assert_eq!(check(&many, 960, 20).len(), 2);
        assert_eq!(check(&many, 960, 5).len(), 6);
        // pdu 96: (96 - 12) / 12 = 7 items per request
        assert_eq!(check(&many, 96, 20)[0].len(), 7);
        // a timer span is cut on whole timers
        let t = Span {
            area: Area::Timer,
            db: 0,
            start: 0,
            units: 100,
            members: vec![0],
        };
        let reqs = check(&[t], 96, 20);
        assert!(reqs.iter().flatten().all(|c| c.units <= 39));
        check(&[one(1), one(3), one(1000), one(7)], 240, 20);
        check(&[one(1), one(3), one(1000), one(7)], 480, 3);
    }
}
