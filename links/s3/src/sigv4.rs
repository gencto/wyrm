//! AWS Signature Version 4 for S3 (header auth, signed payload hash).

use ring::digest::{digest, SHA256};
use ring::hmac;

pub const ALGORITHM: &str = "AWS4-HMAC-SHA256";
/// `x-amz-content-sha256` of an empty body.
pub const EMPTY_SHA256: &str = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

pub fn sha256_hex(b: &[u8]) -> String {
    hex::encode(digest(&SHA256, b).as_ref())
}

fn hmac(key: &[u8], msg: &str) -> Vec<u8> {
    hmac::sign(&hmac::Key::new(hmac::HMAC_SHA256, key), msg.as_bytes())
        .as_ref()
        .to_vec()
}

/// The canonical query: pairs sorted, both sides encoded (unreserved
/// kept), `=` always present.
pub fn canonical_query(pairs: &[(String, String)]) -> String {
    let mut enc: Vec<(String, String)> = pairs
        .iter()
        .map(|(k, v)| {
            (
                wyrm_filestore::util::pct_encode(k, false),
                wyrm_filestore::util::pct_encode(v, false),
            )
        })
        .collect();
    enc.sort();
    enc.iter()
        .map(|(k, v)| format!("{k}={v}"))
        .collect::<Vec<_>>()
        .join("&")
}

/// What a signature covers.
pub struct Signing<'a> {
    pub method: &'a str,
    /// The path as sent (already encoded).
    pub path: &'a str,
    pub query: &'a [(String, String)],
    /// Lowercase names and trimmed values; every one is signed.
    pub headers: &'a [(String, String)],
    pub payload_sha256: &'a str,
    pub access_key: &'a str,
    pub secret_key: &'a str,
    pub region: &'a str,
    pub service: &'a str,
    /// `20150830T123600Z`.
    pub amz_date: &'a str,
}

/// The `Authorization` header value.
pub fn authorization(s: &Signing<'_>) -> String {
    let mut headers: Vec<(String, String)> = s
        .headers
        .iter()
        .map(|(k, v)| (k.to_ascii_lowercase(), v.trim().to_owned()))
        .collect();
    headers.sort();
    let canonical_headers: String = headers.iter().map(|(k, v)| format!("{k}:{v}\n")).collect();
    let signed: Vec<&str> = headers.iter().map(|(k, _)| k.as_str()).collect();
    let signed = signed.join(";");
    let path = if s.path.is_empty() { "/" } else { s.path };
    let creq = format!(
        "{}\n{}\n{}\n{}\n{}\n{}",
        s.method,
        path,
        canonical_query(s.query),
        canonical_headers,
        signed,
        s.payload_sha256
    );
    let date = &s.amz_date[..8.min(s.amz_date.len())];
    let scope = format!("{date}/{}/{}/aws4_request", s.region, s.service);
    let sts = format!(
        "{ALGORITHM}\n{}\n{scope}\n{}",
        s.amz_date,
        sha256_hex(creq.as_bytes())
    );
    let k = hmac(format!("AWS4{}", s.secret_key).as_bytes(), date);
    let k = hmac(&k, s.region);
    let k = hmac(&k, s.service);
    let k = hmac(&k, "aws4_request");
    let sig = hex::encode(hmac(&k, &sts));
    format!(
        "{ALGORITHM} Credential={}/{scope}, SignedHeaders={signed}, Signature={sig}",
        s.access_key
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn h(kv: &[(&str, &str)]) -> Vec<(String, String)> {
        kv.iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    /// `get-vanilla` of the AWS SigV4 test suite.
    #[test]
    fn get_vanilla() {
        let headers = h(&[
            ("host", "example.amazonaws.com"),
            ("x-amz-date", "20150830T123600Z"),
        ]);
        let a = authorization(&Signing {
            method: "GET",
            path: "/",
            query: &[],
            headers: &headers,
            payload_sha256: EMPTY_SHA256,
            access_key: "AKIDEXAMPLE",
            secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "service",
            amz_date: "20150830T123600Z",
        });
        assert_eq!(
            a,
            "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, \
             SignedHeaders=host;x-amz-date, \
             Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31"
        );
    }

    /// "GET Object" of the S3 SigV4 documentation.
    #[test]
    fn s3_get_object() {
        let headers = h(&[
            ("host", "examplebucket.s3.amazonaws.com"),
            ("range", "bytes=0-9"),
            ("x-amz-content-sha256", EMPTY_SHA256),
            ("x-amz-date", "20130524T000000Z"),
        ]);
        let a = authorization(&Signing {
            method: "GET",
            path: "/test.txt",
            query: &[],
            headers: &headers,
            payload_sha256: EMPTY_SHA256,
            access_key: "AKIAIOSFODNN7EXAMPLE",
            secret_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "s3",
            amz_date: "20130524T000000Z",
        });
        assert!(
            a.ends_with(
                "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
            ),
            "{a}"
        );
    }

    /// "GET Bucket (List Objects)" of the S3 SigV4 documentation.
    #[test]
    fn s3_list_objects() {
        let headers = h(&[
            ("host", "examplebucket.s3.amazonaws.com"),
            ("x-amz-content-sha256", EMPTY_SHA256),
            ("x-amz-date", "20130524T000000Z"),
        ]);
        let q = h(&[("max-keys", "2"), ("prefix", "J")]);
        let a = authorization(&Signing {
            method: "GET",
            path: "/",
            query: &q,
            headers: &headers,
            payload_sha256: EMPTY_SHA256,
            access_key: "AKIAIOSFODNN7EXAMPLE",
            secret_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "s3",
            amz_date: "20130524T000000Z",
        });
        assert!(
            a.ends_with(
                "Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7"
            ),
            "{a}"
        );
    }
}
