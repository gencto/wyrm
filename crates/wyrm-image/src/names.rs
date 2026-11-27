//! Whether a `wyrmd.json5` text names a path under a key, told without a JSON5 parser.
//!
//! The device puts `setup` and `seed.json` at fixed paths, and the broker reads them only
//! from where its configuration says. A configuration that does not name the path would
//! carry a file nobody takes, so the assembler refuses it. The check reads tokens: comments
//! and the content of strings never count as a key or a value.

/// What the check tells apart in the text.
#[derive(PartialEq, Eq)]
enum Token {
    /// A name without quotes: a key, `true`, a number.
    Word(String),
    /// A string in either kind of quotes, without them. `None` when it holds an escape:
    /// such a string is never taken for a key or a path.
    Text(Option<String>),
    Colon,
    /// Any other character outside strings and comments.
    Other,
}

/// Where a `//` comment ends in JSON5.
fn ends_line(c: char) -> bool {
    matches!(c, '\n' | '\r' | '\u{2028}' | '\u{2029}')
}

fn tokens(text: &str) -> Vec<Token> {
    let mut out = Vec::new();
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '/' if chars.peek() == Some(&'/') => {
                for c in chars.by_ref() {
                    if ends_line(c) {
                        break;
                    }
                }
            }
            '/' if chars.peek() == Some(&'*') => {
                chars.next();
                let mut star = false;
                for c in chars.by_ref() {
                    if star && c == '/' {
                        break;
                    }
                    star = c == '*';
                }
            }
            '"' | '\'' => {
                let mut content = Some(String::new());
                loop {
                    match chars.next() {
                        None => break,
                        Some(end) if end == c => break,
                        Some('\\') => {
                            chars.next();
                            content = None;
                        }
                        Some(other) => {
                            if let Some(content) = content.as_mut() {
                                content.push(other);
                            }
                        }
                    }
                }
                out.push(Token::Text(content));
            }
            ':' => out.push(Token::Colon),
            c if c.is_whitespace() => {}
            c if c.is_alphanumeric() || c == '_' || c == '$' => {
                let mut word = String::from(c);
                while let Some(next) = chars.peek() {
                    if next.is_alphanumeric() || *next == '_' || *next == '$' {
                        word.push(*next);
                        chars.next();
                    } else {
                        break;
                    }
                }
                out.push(Token::Word(word));
            }
            _ => out.push(Token::Other),
        }
    }
    out
}

/// `text` holds the member `key: "path"` somewhere: the key bare or quoted, the path a string
/// in either kind of quotes without an escape. A comment does not count, nor does the same
/// text inside a string. The object that holds the member is not looked at (`setup_file` and
/// `seed_dir` are keys of one section each).
pub(crate) fn names(text: &str, key: &str, path: &str) -> bool {
    tokens(text).windows(3).any(|window| match window {
        [Token::Word(k), Token::Colon, Token::Text(Some(p))]
        | [Token::Text(Some(k)), Token::Colon, Token::Text(Some(p))] => k == key && p == path,
        _ => false,
    })
}

#[cfg(test)]
mod tests {
    use super::names;

    #[test]
    fn a_member_is_found_in_every_spelling() {
        for text in [
            r#"{ gateway: { setup_file: "/p" } }"#,
            r#"{ gateway: { setup_file:'/p' } }"#,
            r#"{ "gateway": { "setup_file" : "/p" } }"#,
            "{ gateway: {\n  // the hash\n  setup_file /* here */ : /* it */ \"/p\",\n} }",
            r#"{ note: "setup_file: '/x'", gateway: { 'setup_file': "/p" } }"#,
        ] {
            assert!(names(text, "setup_file", "/p"), "{text}");
        }
    }

    #[test]
    fn a_comment_or_a_string_is_no_member() {
        for text in [
            r#"{ gateway: { } }"#,
            r#"{ gateway: { setup_file: "/other" } }"#,
            r#"{ gateway: { setup_file: "/p/more" } }"#,
            r#"{ gateway: { my_setup_file: "/p" } }"#,
            "{ gateway: { // setup_file: \"/p\"\n } }",
            "{ gateway: { /* setup_file: \"/p\" */ } }",
            "{ gateway: { // off\r setup_fil: 1 } } // setup_file: \"/p\"",
            r#"{ note: "setup_file: '/p'" }"#,
            r#"{ note: 'setup_file: "/p"' }"#,
            r#"{ note: "\" setup_file: '/p'" }"#,
            r#"{ gateway: { setup_file: "\/p" } }"#,
            r#"{ gateway: { setup_file: /p } }"#,
            r#"{ gateway: { setup_file: ["/p"] } }"#,
            r#"{ gateway: { setup_file "/p" } }"#,
            "",
            "/* never closed setup_file: \"/p\"",
        ] {
            assert!(!names(text, "setup_file", "/p"), "{text}");
        }
        // an unclosed string ends the text: what it holds is a string
        assert!(names("{ setup_file: \"/p", "setup_file", "/p"));
    }
}
