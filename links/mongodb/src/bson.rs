//! The part of BSON the MongoDB target needs: documents of doubles, strings, documents, arrays,
//! binaries, bools, dates, nulls and integers, written and read (a server's answer is bounded
//! in size and depth; types it never sends to us are read past or refused).

/// A BSON value.
#[derive(Debug, Clone, PartialEq)]
pub enum B {
    Double(f64),
    Str(String),
    Doc(Doc),
    Arr(Vec<B>),
    Bin(Vec<u8>),
    Bool(bool),
    /// UTC milliseconds.
    Date(i64),
    Null,
    Int32(i32),
    Int64(i64),
    /// A type it reads past (ObjectId, timestamp, decimal128): kept as its bytes.
    Other(u8, Vec<u8>),
}

/// A document: its fields in order.
pub type Doc = Vec<(String, B)>;

/// Build a document from `(key, value)` pairs.
pub fn doc<const N: usize>(fields: [(&str, B); N]) -> Doc {
    fields.into_iter().map(|(k, v)| (k.to_owned(), v)).collect()
}

fn cstr(out: &mut Vec<u8>, s: &str) {
    // keys are ours, never with NUL
    out.extend(s.bytes().filter(|b| *b != 0));
    out.push(0);
}

fn value(out: &mut Vec<u8>, key: &str, v: &B) {
    let kind = match v {
        B::Double(_) => 0x01,
        B::Str(_) => 0x02,
        B::Doc(_) => 0x03,
        B::Arr(_) => 0x04,
        B::Bin(_) => 0x05,
        B::Bool(_) => 0x08,
        B::Date(_) => 0x09,
        B::Null => 0x0a,
        B::Int32(_) => 0x10,
        B::Int64(_) => 0x12,
        B::Other(k, _) => *k,
    };
    out.push(kind);
    cstr(out, key);
    match v {
        B::Double(f) => out.extend_from_slice(&f.to_le_bytes()),
        B::Str(s) => {
            out.extend_from_slice(&((s.len() + 1) as i32).to_le_bytes());
            out.extend_from_slice(s.as_bytes());
            out.push(0);
        }
        B::Doc(d) => write_into(out, d),
        B::Arr(a) => {
            let d: Doc = a
                .iter()
                .enumerate()
                .map(|(i, v)| (i.to_string(), v.clone()))
                .collect();
            write_into(out, &d);
        }
        B::Bin(b) => {
            out.extend_from_slice(&(b.len() as i32).to_le_bytes());
            out.push(0); // generic subtype
            out.extend_from_slice(b);
        }
        B::Bool(b) => out.push(u8::from(*b)),
        B::Date(ms) => out.extend_from_slice(&ms.to_le_bytes()),
        B::Null => {}
        B::Int32(i) => out.extend_from_slice(&i.to_le_bytes()),
        B::Int64(i) => out.extend_from_slice(&i.to_le_bytes()),
        B::Other(_, raw) => out.extend_from_slice(raw),
    }
}

fn write_into(out: &mut Vec<u8>, d: &Doc) {
    let start = out.len();
    out.extend_from_slice(&[0; 4]);
    for (k, v) in d {
        value(out, k, v);
    }
    out.push(0);
    let len = (out.len() - start) as i32;
    out[start..start + 4].copy_from_slice(&len.to_le_bytes());
}

/// A document as bytes.
pub fn write(d: &Doc) -> Vec<u8> {
    let mut out = Vec::new();
    write_into(&mut out, d);
    out
}

/// Nesting it reads at most.
const MAX_DEPTH: usize = 32;

fn take<'a>(b: &mut &'a [u8], n: usize) -> Result<&'a [u8], String> {
    if b.len() < n {
        return Err("bson: short".into());
    }
    let (h, t) = b.split_at(n);
    *b = t;
    Ok(h)
}

fn i32_of(b: &mut &[u8]) -> Result<i32, String> {
    let s = take(b, 4)?;
    Ok(i32::from_le_bytes([s[0], s[1], s[2], s[3]]))
}

fn read_doc(b: &mut &[u8], depth: usize) -> Result<Doc, String> {
    if depth > MAX_DEPTH {
        return Err("bson: too deep".into());
    }
    let len = usize::try_from(i32_of(b)?).map_err(|_| "bson: bad length")?;
    let mut body = take(b, len.checked_sub(4).ok_or("bson: bad length")?)?;
    let mut out = Doc::new();
    loop {
        let kind = take(&mut body, 1)?[0];
        if kind == 0 {
            return Ok(out);
        }
        let end = body.iter().position(|x| *x == 0).ok_or("bson: key")?;
        let key = String::from_utf8_lossy(&body[..end]).into_owned();
        body = &body[end + 1..];
        let v = match kind {
            0x01 => B::Double(f64::from_le_bytes(
                take(&mut body, 8)?.try_into().map_err(|_| "bson")?,
            )),
            0x02 => {
                let n = usize::try_from(i32_of(&mut body)?).map_err(|_| "bson: bad string")?;
                let s = take(&mut body, n)?;
                B::Str(String::from_utf8_lossy(s.strip_suffix(&[0]).unwrap_or(s)).into_owned())
            }
            0x03 => B::Doc(read_doc(&mut body, depth + 1)?),
            0x04 => B::Arr(
                read_doc(&mut body, depth + 1)?
                    .into_iter()
                    .map(|(_, v)| v)
                    .collect(),
            ),
            0x05 => {
                let n = usize::try_from(i32_of(&mut body)?).map_err(|_| "bson: bad binary")?;
                take(&mut body, 1)?;
                B::Bin(take(&mut body, n)?.to_vec())
            }
            0x07 => B::Other(kind, take(&mut body, 12)?.to_vec()),
            0x08 => B::Bool(take(&mut body, 1)?[0] != 0),
            0x09 => B::Date(i64::from_le_bytes(
                take(&mut body, 8)?.try_into().map_err(|_| "bson")?,
            )),
            0x0a => B::Null,
            0x10 => B::Int32(i32_of(&mut body)?),
            0x11 => B::Other(kind, take(&mut body, 8)?.to_vec()),
            0x12 => B::Int64(i64::from_le_bytes(
                take(&mut body, 8)?.try_into().map_err(|_| "bson")?,
            )),
            0x13 => B::Other(kind, take(&mut body, 16)?.to_vec()),
            k => return Err(format!("bson: type {k:#x}")),
        };
        out.push((key, v));
    }
}

/// A document from bytes (the whole slice).
pub fn read(mut b: &[u8]) -> Result<Doc, String> {
    read_doc(&mut b, 0)
}

/// A field of a document.
pub fn get<'a>(d: &'a Doc, key: &str) -> Option<&'a B> {
    d.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

/// A number field as f64 (`ok`, `code`).
pub fn num(d: &Doc, key: &str) -> Option<f64> {
    match get(d, key)? {
        B::Double(f) => Some(*f),
        B::Int32(i) => Some(f64::from(*i)),
        B::Int64(i) => Some(*i as f64),
        B::Bool(b) => Some(f64::from(u8::from(*b))),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_and_bounds() {
        let d = doc([
            ("a", B::Double(1.5)),
            ("s", B::Str("é\0x".into())),
            ("d", B::Doc(doc([("n", B::Null), ("b", B::Bool(true))]))),
            ("arr", B::Arr(vec![B::Int32(1), B::Int64(-2), B::Date(3)])),
            ("bin", B::Bin(vec![1, 2, 3])),
        ]);
        let bytes = write(&d);
        // {"x": 1} as BSON (the spec's example shape)
        assert_eq!(
            write(&doc([("x", B::Int32(1))])),
            [12, 0, 0, 0, 0x10, b'x', 0, 1, 0, 0, 0, 0]
        );
        assert_eq!(read(&bytes).unwrap(), d);
        assert_eq!(num(&d, "a"), Some(1.5));
        assert!(read(&bytes[..bytes.len() - 3]).is_err(), "cut short");
        // a document nested past the bound
        let mut deep = doc([("x", B::Null)]);
        for _ in 0..40 {
            deep = doc([("x", B::Doc(deep))]);
        }
        assert!(read(&write(&deep)).unwrap_err().contains("deep"));
        // a negative length
        assert!(read(&[0xff, 0xff, 0xff, 0xff, 0]).is_err());
    }
}
