//! The table value of the third set (ADR 0044 §2):
//! `{"columns": [<name>, …], "rows": [{<name>: <cell>, …}, …]}`.
//!
//! `columns` gives the order; a row is a map, and a cell it lacks is `null`. Every table input
//! also takes a list of maps (its columns are the keys in the order they first appear) and
//! rows given as lists (`{"columns": […], "rows": [[…]]}`, by position). There is no index
//! column: a row's index is its place from 0.

use std::collections::BTreeMap;
use wyrm_core::Value;

/// Rows of one table at most.
pub const MAX_ROWS: usize = 10_000;
/// Columns of one table at most.
pub const MAX_COLUMNS: usize = 128;
/// The longest column name, bytes.
pub const MAX_NAME: usize = 256;
/// The most a table's cells may take, encoded (about).
pub const MAX_BYTES: usize = 512 * 1024;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Table {
    pub columns: Vec<String>,
    pub rows: Vec<BTreeMap<String, Value>>,
}

/// How deep a cell may nest: the table, its rows and a row are three levels of 32.
pub const MAX_CELL_DEPTH: usize = wyrm_core::value::MAX_DEPTH - 3;

/// How deep `v` nests (a scalar is 0); stops past `cap`.
fn depth(v: &Value, cap: usize) -> usize {
    if cap == 0 {
        return usize::from(matches!(v, Value::Array(_) | Value::Map(_)));
    }
    match v {
        Value::Array(a) => 1 + a.iter().map(|x| depth(x, cap - 1)).max().unwrap_or(0),
        Value::Map(m) => 1 + m.values().map(|x| depth(x, cap - 1)).max().unwrap_or(0),
        _ => 0,
    }
}

/// About how many bytes `v` takes encoded; stops counting past `cap`.
pub fn size(v: &Value, cap: usize) -> usize {
    fn go(v: &Value, acc: &mut usize, cap: usize) {
        if *acc > cap {
            return;
        }
        *acc += match v {
            Value::Null | Value::Bool(_) => 1,
            Value::Int(_) | Value::UInt(_) | Value::Float(_) => 9,
            Value::Str(s) => s.len() + 3,
            Value::Bytes(b) => b.len() + 3,
            Value::Array(a) => {
                for x in a {
                    go(x, acc, cap);
                }
                3
            }
            Value::Map(m) => {
                for (k, x) in m {
                    *acc += k.len() + 3;
                    go(x, acc, cap);
                }
                3
            }
        };
    }
    let mut acc = 0;
    go(v, &mut acc, cap);
    acc
}

impl Table {
    pub fn new(columns: Vec<String>) -> Self {
        Self {
            columns,
            rows: Vec::new(),
        }
    }

    /// A table input. `None`: not a table, or past a bound.
    pub fn from_value(v: &Value) -> Option<Table> {
        match v {
            Value::Map(m) => {
                let Some(Value::Array(rows)) = m.get("rows") else {
                    return None;
                };
                let columns = match m.get("columns") {
                    Some(Value::Array(c)) => c
                        .iter()
                        .map(|n| match n {
                            Value::Str(s) => Some(s.clone()),
                            // a reference column `{name, type}`
                            Value::Map(c) => match c.get("name") {
                                Some(Value::Str(s)) => Some(s.clone()),
                                _ => None,
                            },
                            _ => None,
                        })
                        .collect::<Option<Vec<String>>>()?,
                    None => Vec::new(),
                    _ => return None,
                };
                Self::of_rows(columns, rows)
            }
            Value::Array(rows) => Self::of_rows(Vec::new(), rows),
            _ => None,
        }
    }

    fn of_rows(mut columns: Vec<String>, rows: &[Value]) -> Option<Table> {
        if rows.len() > MAX_ROWS {
            return None;
        }
        let mut out = Vec::with_capacity(rows.len());
        for r in rows {
            let row = match r {
                Value::Map(m) => {
                    for k in m.keys() {
                        if !columns.contains(k) {
                            columns.push(k.clone());
                        }
                    }
                    m.clone()
                }
                Value::Array(cells) => columns
                    .iter()
                    .zip(cells)
                    .map(|(c, v)| (c.clone(), v.clone()))
                    .collect(),
                _ => return None,
            };
            out.push(row);
            if columns.len() > MAX_COLUMNS {
                return None;
            }
        }
        dedup(&mut columns);
        let t = Table { columns, rows: out };
        t.fits().then_some(t)
    }

    /// Within the bounds of a table.
    pub fn fits(&self) -> bool {
        self.rows.len() <= MAX_ROWS
            && self.columns.len() <= MAX_COLUMNS
            && self.columns.iter().all(|c| c.len() <= MAX_NAME)
            && self.bytes() <= MAX_BYTES
    }

    fn bytes(&self) -> usize {
        let mut n = 0;
        for r in &self.rows {
            for v in r.values() {
                // a cell is three levels inside the table (spec README rule 6: 32 in all)
                if depth(v, MAX_CELL_DEPTH) > MAX_CELL_DEPTH {
                    return usize::MAX;
                }
                n += size(v, MAX_BYTES);
                if n > MAX_BYTES {
                    return n;
                }
            }
        }
        n
    }

    /// The cell of `col` in row `r`; `null` when it has none.
    pub fn cell<'a>(&'a self, r: usize, col: &str) -> &'a Value {
        self.rows
            .get(r)
            .and_then(|row| row.get(col))
            .unwrap_or(&Value::Null)
    }

    /// The table as a value; `None` past a bound (the block sends `null`, `bad`).
    pub fn to_value(&self) -> Option<Value> {
        if !self.fits() {
            return None;
        }
        Some(Value::Map(BTreeMap::from([
            (
                "columns".to_owned(),
                Value::Array(self.columns.iter().map(|c| Value::Str(c.clone())).collect()),
            ),
            (
                "rows".to_owned(),
                Value::Array(
                    self.rows
                        .iter()
                        .map(|r| {
                            // only the table's columns, every one of them
                            Value::Map(
                                self.columns
                                    .iter()
                                    .map(|c| (c.clone(), r.get(c).cloned().unwrap_or(Value::Null)))
                                    .collect(),
                            )
                        })
                        .collect(),
                ),
            ),
        ])))
    }
}

/// Column names once each, in their first place.
fn dedup(c: &mut Vec<String>) {
    let mut seen = std::collections::BTreeSet::new();
    c.retain(|n| seen.insert(n.clone()));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(kv: &[(&str, Value)]) -> Value {
        Value::Map(
            kv.iter()
                .map(|(k, v)| ((*k).to_owned(), v.clone()))
                .collect(),
        )
    }

    #[test]
    fn forms_of_a_table() {
        let rows = Value::Array(vec![
            map(&[("name", "pump".into()), ("kw", Value::Int(3))]),
            map(&[("name", "fan".into()), ("zone", "B".into())]),
        ]);
        let t = Table::from_value(&rows).unwrap();
        assert_eq!(t.columns, ["kw", "name", "zone"]);
        assert_eq!(t.cell(1, "kw"), &Value::Null);
        let canon = t.to_value().unwrap();
        let back = Table::from_value(&canon).unwrap();
        assert_eq!(
            back,
            Table {
                rows: back.rows.clone(),
                ..t.clone()
            }
        );
        assert_eq!(
            back.cell(0, "zone"),
            &Value::Null,
            "every column in every row"
        );
        // rows as lists, by position; reference columns `{name, type}`
        let v = map(&[
            (
                "columns",
                Value::Array(vec![
                    map(&[("name", "a".into()), ("type", "number".into())]),
                    "b".into(),
                ]),
            ),
            (
                "rows",
                Value::Array(vec![Value::Array(vec![Value::Int(1), Value::Int(2)])]),
            ),
        ]);
        let t = Table::from_value(&v).unwrap();
        assert_eq!(
            (t.columns.clone(), t.cell(0, "b").clone()),
            (vec!["a".into(), "b".into()], Value::Int(2))
        );
        assert!(Table::from_value(&Value::Int(1)).is_none());
        assert!(Table::from_value(&Value::Array(vec![Value::Int(1)])).is_none());
        let big = Value::Array(vec![map(&[("a", Value::Int(1))]); MAX_ROWS + 1]);
        assert!(Table::from_value(&big).is_none());
        let wide = Value::Array(vec![Value::Map(
            (0..=MAX_COLUMNS)
                .map(|i| (format!("c{i}"), Value::Null))
                .collect(),
        )]);
        assert!(Table::from_value(&wide).is_none());
        let heavy = Value::Array(vec![map(&[("a", Value::Str("x".repeat(MAX_BYTES)))])]);
        assert!(Table::from_value(&heavy).is_none());
    }
}
