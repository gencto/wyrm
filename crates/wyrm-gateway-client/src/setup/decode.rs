//! `/api/info` as the setup reads it: the fields of a pending setup, typed. The one place
//! this crate reads them out of the map (docs/rust-rules.md rule 6).

use wyrm_core::Value;

/// The fields of `/api/info` a setup needs; a field that is absent or of another type is
/// not there.
#[derive(Debug, Default, PartialEq)]
pub(super) struct Info {
    /// `setup: true`: a setup is pending.
    pub setup: bool,
    /// `ca`: the DER of the CA the gateway presents.
    pub ca: Option<Vec<u8>>,
    /// `setup_proof`: the proof that binds `ca` to the setup code.
    pub setup_proof: Option<Vec<u8>>,
    /// `names`: the DNS and IP names of the gateway's certificate, lower case.
    pub names: Vec<String>,
    /// `site`.
    pub site: String,
}

/// `None` when the answer is no map.
pub(super) fn info(v: &Value) -> Option<Info> {
    let Value::Map(m) = v else { return None };
    let mut out = Info::default();
    for (k, v) in m {
        match (k.as_str(), v) {
            ("setup", Value::Bool(b)) => out.setup = *b,
            ("ca", Value::Bytes(b)) => out.ca = Some(b.clone()),
            ("setup_proof", Value::Bytes(b)) => out.setup_proof = Some(b.clone()),
            ("names", Value::Array(a)) => {
                out.names = a
                    .iter()
                    .filter_map(|n| match n {
                        Value::Str(s) => Some(s.to_ascii_lowercase()),
                        _ => None,
                    })
                    .collect();
            }
            ("site", Value::Str(s)) => out.site.clone_from(s),
            _ => {}
        }
    }
    Some(out)
}
