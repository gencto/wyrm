//! The group address list an ETS project exports as CSV, read into a
//! folder of points.
//!
//! ETS writes one row per main group, middle group and group address, in
//! one of these shapes (the separator is a tab, a semicolon or a comma;
//! cells may be quoted; the header row is optional):
//!
//! ```text
//! "Group name";"Address";"Central";"Unlocked";"Description";"DatapointType";"Security"
//! "Lighting";"1/-/-";"";"";"";"";"Auto"
//! "Ground floor";"1/0/-";"";"";"";"";"Auto"
//! "Kitchen";"1/0/1";"";"";"";"DPST-1-1";"Auto"
//! ```
//!
//! ```text
//! "Main";"Middle";"Sub";"Address";…
//! "Lighting";"";"";"1/-/-";…
//! "";"Ground floor";"";"1/0/-";…
//! "";"";"Kitchen";"1/0/1";…;"DPST-1-1";…
//! ```
//!
//! So a row is read by what its cells are, not by their column: the cell
//! that is an address (`1/0/1`, or `1/0/-` for a range), the last cell
//! with text before it (the name) and the first cell after it that names a
//! datapoint type. A row without an address (the header) is passed over.
//!
//! The folder: `<main>/<middle>/<point>` (two-level and free addresses
//! have fewer folders), ids from the address (`ga_1_0_1`, folders `1_…`
//! with the group's name), the group's name as the point's name for people.

use crate::addr::GroupAddr;
use crate::dpt::Dpt;
use std::collections::BTreeMap;
use wyrm_core::Value;
use wyrm_link_sdk::driver::branch::{Level, Node};

/// Addresses named in a report list at most.
const LISTED: usize = 50;
/// Rows read at most (the framework takes 5000 nodes; rows without a type
/// and group rows come on top).
pub const MAX_ROWS: usize = 20_000;
/// Octets of one cell at most.
pub const MAX_CELL: usize = 4096;
/// Characters of a group's name kept in a folder id.
const NAME_IN_ID: usize = 24;

/// Why an export is refused as a whole.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum EtsError {
    #[error("no group address in the text: expected the CSV export of the group addresses")]
    Empty,
    #[error("line {0}: a quoted cell is not closed")]
    Quote(usize),
    #[error("more than {MAX_ROWS} rows")]
    Rows,
    #[error("line {0}: a cell of more than {MAX_CELL} octets")]
    Cell(usize),
}

/// What the rows gave.
#[derive(Debug, Clone, PartialEq)]
pub struct Imported {
    /// The folder with everything below it.
    pub folder: Node,
    pub points: usize,
    /// Addresses left out because their row names no datapoint type.
    pub without_type: Vec<String>,
    /// Addresses left out because they came a second time.
    pub repeated: Vec<String>,
}

/// The separator of `text`: the one its first line with any holds most.
fn separator(text: &str) -> char {
    let line = text.lines().find(|l| !l.trim().is_empty()).unwrap_or("");
    let count = |c: char| line.chars().filter(|x| *x == c).count();
    let (tabs, semicolons, commas) = (count('\t'), count(';'), count(','));
    if tabs >= semicolons && tabs >= commas && tabs > 0 {
        '\t'
    } else if semicolons >= commas {
        ';'
    } else {
        ','
    }
}

/// The rows of a CSV text: cells split at `sep`, a quoted cell may hold
/// the separator, a line break and `""` for a quote.
fn rows(text: &str, sep: char) -> Result<Vec<Vec<String>>, EtsError> {
    let mut out = Vec::new();
    let mut row: Vec<String> = Vec::new();
    let mut cell = String::new();
    let mut quoted = false;
    let mut opened = 0;
    let mut line = 1;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\n' {
            line += 1;
        }
        if cell.len() > MAX_CELL {
            return Err(EtsError::Cell(line));
        }
        if out.len() >= MAX_ROWS {
            return Err(EtsError::Rows);
        }
        match c {
            '"' if quoted && chars.peek() == Some(&'"') => {
                chars.next();
                cell.push('"');
            }
            '"' if quoted => quoted = false,
            '"' if cell.trim().is_empty() => {
                cell.clear();
                quoted = true;
                opened = line;
            }
            c if quoted => cell.push(c),
            c if c == sep => row.push(std::mem::take(&mut cell)),
            '\r' => {}
            '\n' => {
                row.push(std::mem::take(&mut cell));
                out.push(std::mem::take(&mut row));
            }
            c => cell.push(c),
        }
    }
    if quoted {
        return Err(EtsError::Quote(opened));
    }
    if !cell.is_empty() || !row.is_empty() {
        row.push(cell);
        out.push(row);
    }
    Ok(out)
}

/// The parts of an address cell: numbers, `None` for the `-` of a range.
fn address_parts(cell: &str) -> Option<Vec<Option<u16>>> {
    let cell = cell.trim();
    if cell.is_empty() {
        return None;
    }
    let parts: Option<Vec<Option<u16>>> = cell
        .split('/')
        .map(|p| match p.trim() {
            "-" => Some(None),
            digits => digits.parse::<u16>().ok().map(Some),
        })
        .collect();
    let parts = parts?;
    let numbers = parts.iter().take_while(|p| p.is_some()).count();
    // numbers first, then only `-`; one to three parts
    let shaped = parts.iter().skip(numbers).all(Option::is_none);
    (shaped && numbers > 0 && parts.len() <= 3).then_some(parts)
}

/// One row with an address.
struct Row {
    parts: Vec<Option<u16>>,
    address: String,
    name: String,
    dpt: Option<Dpt>,
}

fn row_of(cells: &[String]) -> Option<Row> {
    // The address is the first cell written with `/`. Only when no cell
    // is (free addresses, plain numbers) a cell of digits is one, and then
    // not the row's first text: a group named `100` is a name.
    let shaped = |want_slash: bool| {
        let first_text = cells.iter().position(|c| !c.trim().is_empty());
        cells.iter().enumerate().find_map(|(i, c)| {
            let slash = c.contains('/');
            let fits = if want_slash {
                slash
            } else {
                !slash && Some(i) != first_text
            };
            fits.then(|| address_parts(c)).flatten().map(|p| (i, p))
        })
    };
    let (at, parts) = shaped(true).or_else(|| shaped(false))?;
    let name = cells
        .get(..at)?
        .iter()
        .rev()
        .map(|c| c.trim())
        .find(|c| !c.is_empty())
        .unwrap_or("");
    // several types in one cell: the first one
    let dpt = cells.get(at + 1..)?.iter().find_map(|c| {
        let first = c.split([',', ' ']).find(|p| !p.is_empty())?;
        let upper = first.to_ascii_uppercase();
        (upper.starts_with("DPT") || upper.starts_with("DPST"))
            .then(|| Dpt::parse(first).ok())
            .flatten()
    });
    Some(Row {
        parts,
        address: cells.get(at)?.trim().to_owned(),
        name: name.to_owned(),
        dpt,
    })
}

/// A key segment of a group's number and name: `1_ground_floor`.
fn folder_id(number: u16, name: &str) -> String {
    let mut id = number.to_string();
    let mut gap = true;
    for c in name.chars().take(NAME_IN_ID) {
        if c.is_ascii_alphanumeric() {
            if gap {
                id.push('_');
            }
            id.push(c.to_ascii_lowercase());
            gap = false;
        } else {
            gap = true;
        }
    }
    id
}

/// Folders by their numbers, with the points in each.
#[derive(Default)]
struct Groups {
    name: String,
    below: BTreeMap<u16, Groups>,
    points: Vec<Node>,
}

impl Groups {
    fn at(&mut self, path: &[u16]) -> &mut Groups {
        let mut here = self;
        for n in path {
            here = here.below.entry(*n).or_default();
        }
        here
    }

    fn into_children(self) -> Vec<Node> {
        let folders = self.below.into_iter().map(|(n, g)| Node {
            level: Level::Folder,
            name: folder_id(n, &g.name),
            params: BTreeMap::new(),
            enabled: true,
            children: g.into_children(),
        });
        folders.chain(self.points).collect()
    }
}

fn note(list: &mut Vec<String>, address: &str) {
    if list.len() < LISTED {
        list.push(address.to_owned());
    }
}

/// The export `text` as the folder `folder`; every point gets `extra`
/// beside its address, type and name.
pub fn import(
    text: &str,
    folder: &str,
    extra: &BTreeMap<String, Value>,
) -> Result<Imported, EtsError> {
    let text = text.trim_start_matches('\u{feff}');
    let mut root = Groups::default();
    let (mut without_type, mut repeated) = (Vec::new(), Vec::new());
    let mut seen = std::collections::BTreeSet::new();
    let mut points = 0;
    for cells in rows(text, separator(text))? {
        let Some(row) = row_of(&cells) else {
            continue;
        };
        let numbers: Vec<u16> = row.parts.iter().map_while(|p| *p).collect();
        if numbers.len() < row.parts.len() {
            // a main or middle group: the name of its folder
            root.at(&numbers).name = row.name;
            continue;
        }
        let Ok(to) = GroupAddr::parse(&row.address) else {
            continue;
        };
        let Some(dpt) = row.dpt else {
            note(&mut without_type, &row.address);
            continue;
        };
        if !seen.insert(to) {
            note(&mut repeated, &row.address);
            continue;
        }
        let mut params = extra.clone();
        params.insert("address".into(), Value::Str(to_text(&numbers)));
        params.insert("dpt".into(), Value::Str(dpt.to_string()));
        if !row.name.is_empty() {
            params.insert("display".into(), Value::Str(row.name));
        }
        let (_, groups) = numbers.split_last().unwrap_or((&0, &[]));
        root.at(groups).points.push(Node {
            level: Level::Point,
            name: format!("ga_{}", to_text(&numbers).replace('/', "_")),
            params,
            enabled: true,
            children: Vec::new(),
        });
        points += 1;
    }
    if points == 0 && without_type.is_empty() {
        return Err(EtsError::Empty);
    }
    Ok(Imported {
        folder: Node {
            level: Level::Folder,
            name: folder.to_owned(),
            params: BTreeMap::new(),
            enabled: true,
            children: root.into_children(),
        },
        points,
        without_type,
        repeated,
    })
}

/// The address as the export wrote it (its levels kept).
fn to_text(numbers: &[u16]) -> String {
    let parts: Vec<String> = numbers.iter().map(u16::to_string).collect();
    parts.join("/")
}

#[cfg(test)]
mod tests {
    use super::*;

    const THREE: &str = "\u{feff}\"Group name\";\"Address\";\"Central\";\"Unlocked\";\"Description\";\"DatapointType\";\"Security\"\r\n\
        \"Lighting\";\"1/-/-\";\"\";\"\";\"\";\"\";\"Auto\"\r\n\
        \"Ground floor\";\"1/0/-\";\"\";\"\";\"\";\"\";\"Auto\"\r\n\
        \"Kitchen; \"\"main\"\" light\";\"1/0/1\";\"\";\"\";\"on/off\";\"DPST-1-1\";\"Auto\"\r\n\
        \"Kitchen dimmer\";\"1/0/2\";\"\";\"\";\"\";\"DPST-5-1, DPST-5-4\";\"Auto\"\r\n\
        \"No type\";\"1/0/3\";\"\";\"\";\"\";\"\";\"Auto\"\r\n\
        \"Heating\";\"2/-/-\";\"\";\"\";\"\";\"\";\"Auto\"\r\n\
        \"Rooms\";\"2/1/-\";\"\";\"\";\"\";\"\";\"Auto\"\r\n\
        \"Living room\ntemperature\";\"2/1/10\";\"\";\"\";\"\";\"DPT-9\";\"Auto\"\r\n\
        \"Again\";\"2/1/10\";\"\";\"\";\"\";\"DPST-9-1\";\"Auto\"\r\n";

    fn names(nodes: &[Node]) -> Vec<&str> {
        nodes.iter().map(|n| n.name.as_str()).collect()
    }

    fn text<'a>(n: &'a Node, key: &str) -> &'a str {
        match n.params.get(key) {
            Some(Value::Str(s)) => s,
            other => panic!("{key}: {other:?}"),
        }
    }

    #[test]
    fn one_name_column_with_a_header() {
        let got = import(THREE, "ets", &BTreeMap::new()).unwrap();
        assert_eq!(got.points, 3);
        assert_eq!(got.without_type, ["1/0/3"]);
        assert_eq!(got.repeated, ["2/1/10"]);
        let f = &got.folder;
        assert_eq!((f.level, f.name.as_str()), (Level::Folder, "ets"));
        assert_eq!(names(&f.children), ["1_lighting", "2_heating"]);
        let ground = &f.children[0].children[0];
        assert_eq!(ground.name, "0_ground_floor");
        assert_eq!(names(&ground.children), ["ga_1_0_1", "ga_1_0_2"]);
        let kitchen = &ground.children[0];
        assert_eq!(kitchen.level, Level::Point);
        assert_eq!(text(kitchen, "address"), "1/0/1");
        assert_eq!(text(kitchen, "dpt"), "1.001");
        assert_eq!(text(kitchen, "display"), "Kitchen; \"main\" light");
        assert_eq!(text(&ground.children[1], "dpt"), "5.001");
        let living = &f.children[1].children[0].children[0];
        assert_eq!(f.children[1].children[0].name, "1_rooms");
        assert_eq!(text(living, "dpt"), "9");
        assert_eq!(text(living, "display"), "Living room\ntemperature");
    }

    #[test]
    fn three_name_columns_tabs_no_header_no_quotes() {
        let csv = "Lighting\t\t\t1/-/-\t\t\t\t\tAuto\n\
                   \tGround floor\t\t1/0/-\t\t\t\t\tAuto\n\
                   \t\tKitchen\t1/0/1\t\t\t\tDPST-1-1\tAuto\n\
                   \t\tHall\t1/0/2\t\t\t\tdpst-1-1\tAuto";
        let extra = BTreeMap::from([("read_on_start".to_owned(), Value::Bool(true))]);
        let got = import(csv, "plan", &extra).unwrap();
        assert_eq!(got.points, 2);
        let ground = &got.folder.children[0].children[0];
        assert_eq!(got.folder.children[0].name, "1_lighting");
        assert_eq!(names(&ground.children), ["ga_1_0_1", "ga_1_0_2"]);
        assert_eq!(text(&ground.children[1], "display"), "Hall");
        assert_eq!(
            ground.children[0].params.get("read_on_start"),
            Some(&Value::Bool(true))
        );
    }

    #[test]
    fn two_level_and_free_addresses_with_commas() {
        let csv = "Main,1/-,,,,,Auto\n\
                   Pump,1/515,,,,DPST-1-1,Auto\n\
                   \"Free, one\",2600,,,,DPST-9-1,Auto\n";
        let got = import(csv, "ets", &BTreeMap::new()).unwrap();
        assert_eq!(got.points, 2, "{got:?}");
        assert_eq!(names(&got.folder.children), ["1_main", "ga_2600"]);
        let pump = &got.folder.children[0].children[0];
        assert_eq!(pump.name, "ga_1_515");
        assert_eq!(text(pump, "address"), "1/515");
        assert_eq!(text(&got.folder.children[1], "display"), "Free, one");
    }

    #[test]
    fn refused_texts() {
        assert_eq!(import("", "ets", &BTreeMap::new()), Err(EtsError::Empty));
        assert_eq!(
            import("name;address\nfoo;bar\n", "ets", &BTreeMap::new()),
            Err(EtsError::Empty)
        );
        assert_eq!(
            import(
                "a;1/0/1;DPST-1-1\n\"open;1/0/2;DPST-1-1\n",
                "ets",
                &BTreeMap::new()
            ),
            Err(EtsError::Quote(2))
        );
        // out of range and broadcast addresses are passed over
        let got = import(
            "a;40/0/1;DPST-1-1\nb;0/0/0;DPST-1-1\nc;1/0/1;DPST-1-1\n",
            "ets",
            &BTreeMap::new(),
        )
        .unwrap();
        assert_eq!(got.points, 1);
    }

    #[test]
    fn a_name_of_digits_is_not_the_address() {
        let csv = "100;1/-/-;;\n200;1/0/-;;\n2024;1/0/1;;;;DPST-1-1\n";
        let got = import(csv, "ets", &BTreeMap::new()).unwrap();
        assert_eq!(got.points, 1);
        assert_eq!(names(&got.folder.children), ["1_100"]);
        let point = &got.folder.children[0].children[0].children[0];
        assert_eq!(got.folder.children[0].children[0].name, "0_200");
        assert_eq!(point.name, "ga_1_0_1");
        assert_eq!(text(point, "display"), "2024");
        // free addresses: the number after the name, never the name
        let got = import("300;2600;;;;DPST-9-1\n", "ets", &BTreeMap::new()).unwrap();
        assert_eq!(names(&got.folder.children), ["ga_2600"]);
        assert_eq!(text(&got.folder.children[0], "display"), "300");
        // a row of one number has no address
        assert_eq!(
            import("2600\n", "ets", &BTreeMap::new()),
            Err(EtsError::Empty)
        );
    }

    #[test]
    fn rows_and_cells_are_bounded() {
        let long = format!("{};1/0/1;;;;DPST-1-1\n", "x".repeat(MAX_CELL + 2));
        assert_eq!(
            import(&long, "ets", &BTreeMap::new()),
            Err(EtsError::Cell(1))
        );
        let quoted = format!("\"{}", "x".repeat(MAX_CELL + 2));
        assert_eq!(
            import(&quoted, "ets", &BTreeMap::new()),
            Err(EtsError::Cell(1))
        );
        let many = "a;1/0/1;;;;DPST-1-1\n".repeat(MAX_ROWS + 1);
        assert_eq!(import(&many, "ets", &BTreeMap::new()), Err(EtsError::Rows));
    }

    #[test]
    fn folder_ids_are_key_segments() {
        assert_eq!(folder_id(3, "Étage 1 — Küche/Bad"), "3_tage_1_k_che_bad");
        assert_eq!(folder_id(0, ""), "0");
        assert_eq!(
            folder_id(7, "A very long name of a main group in the project"),
            "7_a_very_long_name_of_a_ma"
        );
    }
}
