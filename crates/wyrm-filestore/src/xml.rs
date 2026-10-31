//! A small XML reader for store replies (S3 listings and errors, WebDAV
//! multistatus): elements by local name (namespace prefixes dropped), their
//! text and children. Attributes, processing instructions, comments and
//! the doctype are skipped; CDATA is text. Depth and size are bounded:
//! replies come from the network.

/// Deepest nesting accepted.
pub const MAX_DEPTH: usize = 64;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Element {
    /// Local name: `D:href` → `href`.
    pub name: String,
    pub children: Vec<Element>,
    /// Text directly inside, entities decoded (not trimmed).
    pub text: String,
}

impl Element {
    pub fn child(&self, name: &str) -> Option<&Element> {
        self.children.iter().find(|c| c.name == name)
    }

    pub fn all<'a>(&'a self, name: &'a str) -> impl Iterator<Item = &'a Element> + 'a {
        self.children.iter().filter(move |c| c.name == name)
    }

    /// Trimmed text of the child `name`.
    pub fn text_of(&self, name: &str) -> Option<&str> {
        self.child(name).map(|c| c.text.trim())
    }

    /// The first element `name` at any depth (this one included).
    pub fn find(&self, name: &str) -> Option<&Element> {
        if self.name == name {
            return Some(self);
        }
        self.children.iter().find_map(|c| c.find(name))
    }
}

fn local(name: &str) -> &str {
    name.rsplit_once(':').map_or(name, |(_, l)| l)
}

/// `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#N;`, `&#xH;`.
fn decode_into(out: &mut String, s: &str) -> Result<(), String> {
    let mut rest = s;
    while let Some(i) = rest.find('&') {
        out.push_str(&rest[..i]);
        let after = &rest[i + 1..];
        let end = after.find(';').ok_or("unterminated entity")?;
        let ent = &after[..end];
        let c = match ent {
            "amp" => '&',
            "lt" => '<',
            "gt" => '>',
            "quot" => '"',
            "apos" => '\'',
            _ => {
                let n = if let Some(h) = ent.strip_prefix("#x").or(ent.strip_prefix("#X")) {
                    u32::from_str_radix(h, 16).ok()
                } else if let Some(d) = ent.strip_prefix('#') {
                    d.parse().ok()
                } else {
                    None
                };
                n.and_then(char::from_u32)
                    .ok_or_else(|| format!("unknown entity &{ent};"))?
            }
        };
        out.push(c);
        rest = &after[end + 1..];
    }
    out.push_str(rest);
    Ok(())
}

/// Escape text for an XML body.
pub fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            c => out.push(c),
        }
    }
    out
}

/// The end of a tag that starts at `s[0] == '<'`, quotes respected.
fn tag_end(s: &str) -> Option<usize> {
    let mut quote = None;
    for (i, c) in s.char_indices() {
        match (quote, c) {
            (None, '"' | '\'') => quote = Some(c),
            (Some(q), c) if c == q => quote = None,
            (None, '>') => return Some(i),
            _ => {}
        }
    }
    None
}

/// Parse a document into its root element.
pub fn parse(doc: &str) -> Result<Element, String> {
    let mut stack: Vec<Element> = Vec::new();
    let mut root: Option<Element> = None;
    let mut rest = doc.trim_start_matches('\u{feff}');
    while !rest.is_empty() {
        let Some(lt) = rest.find('<') else {
            if let Some(top) = stack.last_mut() {
                decode_into(&mut top.text, rest)?;
            } else if !rest.trim().is_empty() {
                return Err("text outside the root element".into());
            }
            break;
        };
        if lt > 0 {
            let text = &rest[..lt];
            match stack.last_mut() {
                Some(top) => decode_into(&mut top.text, text)?,
                None if text.trim().is_empty() => {}
                None => return Err("text outside the root element".into()),
            }
        }
        rest = &rest[lt..];
        if let Some(r) = rest.strip_prefix("<!--") {
            let end = r.find("-->").ok_or("unterminated comment")?;
            rest = &r[end + 3..];
            continue;
        }
        if let Some(r) = rest.strip_prefix("<![CDATA[") {
            let end = r.find("]]>").ok_or("unterminated CDATA")?;
            match stack.last_mut() {
                Some(top) => top.text.push_str(&r[..end]),
                None => return Err("CDATA outside the root element".into()),
            }
            rest = &r[end + 3..];
            continue;
        }
        if rest.starts_with("<?") {
            let end = rest
                .find("?>")
                .ok_or("unterminated processing instruction")?;
            rest = &rest[end + 2..];
            continue;
        }
        if rest.starts_with("<!") {
            let end = tag_end(rest).ok_or("unterminated declaration")?;
            rest = &rest[end + 1..];
            continue;
        }
        let end = tag_end(rest).ok_or("unterminated tag")?;
        let inner = &rest[1..end];
        rest = &rest[end + 1..];
        if let Some(name) = inner.strip_prefix('/') {
            let name = local(name.trim());
            let el = stack.pop().ok_or("closing tag without an opening one")?;
            if el.name != name {
                return Err(format!("</{name}> closes <{}>", el.name));
            }
            match stack.last_mut() {
                Some(parent) => parent.children.push(el),
                None => {
                    if root.is_some() {
                        return Err("more than one root element".into());
                    }
                    root = Some(el);
                }
            }
            continue;
        }
        let self_closing = inner.ends_with('/');
        let inner = inner.trim_end_matches('/');
        let name = inner
            .split(|c: char| c.is_ascii_whitespace())
            .next()
            .filter(|n| !n.is_empty())
            .ok_or("empty tag name")?;
        let el = Element {
            name: local(name).to_owned(),
            ..Element::default()
        };
        if self_closing {
            match stack.last_mut() {
                Some(parent) => parent.children.push(el),
                None => {
                    if root.is_some() {
                        return Err("more than one root element".into());
                    }
                    root = Some(el);
                }
            }
        } else {
            if stack.len() >= MAX_DEPTH {
                return Err(format!("nested deeper than {MAX_DEPTH}"));
            }
            if root.is_some() {
                return Err("more than one root element".into());
            }
            stack.push(el);
        }
    }
    if let Some(open) = stack.last() {
        return Err(format!("<{}> is not closed", open.name));
    }
    root.ok_or_else(|| "no root element".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn listing() {
        let doc = r#"<?xml version="1.0" encoding="UTF-8"?>
<!-- a comment -->
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>b</Name>
  <Contents><Key>a &amp; b/c&#x2F;d.txt</Key><Size>12</Size></Contents>
  <Contents><Key><![CDATA[x<y]]></Key><Size>0</Size></Contents>
  <IsTruncated>false</IsTruncated>
  <Empty/>
</ListBucketResult>"#;
        let r = parse(doc).unwrap();
        assert_eq!(r.name, "ListBucketResult");
        let keys: Vec<&str> = r.all("Contents").filter_map(|c| c.text_of("Key")).collect();
        assert_eq!(keys, ["a & b/c/d.txt", "x<y"]);
        assert_eq!(r.text_of("IsTruncated"), Some("false"));
        assert!(r.child("Empty").is_some());
    }

    #[test]
    fn namespaces_and_attributes() {
        let doc = r#"<d:multistatus xmlns:d="DAV:"><d:response><d:href>/a%20b/</d:href>
<d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>
<lp1:getlastmodified xmlns:lp1="DAV:" a='x>y'>Tue, 02 Jan 2024 03:04:05 GMT</lp1:getlastmodified>
</d:prop></d:propstat></d:response></d:multistatus>"#;
        let r = parse(doc).unwrap();
        let resp = r.child("response").unwrap();
        assert_eq!(resp.text_of("href"), Some("/a%20b/"));
        assert!(resp.find("collection").is_some());
        assert_eq!(
            resp.find("getlastmodified").map(|e| e.text.as_str()),
            Some("Tue, 02 Jan 2024 03:04:05 GMT")
        );
    }

    #[test]
    fn malformed() {
        for bad in [
            "",
            "<a>",
            "<a></b>",
            "</a>",
            "<a/><b/>",
            "text",
            "<a>&bogus;</a>",
            "<a><!-- x</a>",
        ] {
            assert!(parse(bad).is_err(), "{bad:?}");
        }
        let deep = "<a>".repeat(MAX_DEPTH + 1) + &"</a>".repeat(MAX_DEPTH + 1);
        assert!(parse(&deep).is_err());
        assert_eq!(escape("<a&'\">"), "&lt;a&amp;&apos;&quot;&gt;");
    }
}
