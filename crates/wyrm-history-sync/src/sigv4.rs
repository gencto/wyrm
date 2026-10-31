//! AWS Signature Version 4 for one request (DynamoDB and other AWS JSON APIs): the canonical
//! request, the string to sign, the signing key chain, the `Authorization` header.

use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};

type HmacSha256 = Hmac<Sha256>;

fn hmac(key: &[u8], data: &[u8]) -> [u8; 32] {
    // HMAC takes a key of any length
    let mut m = HmacSha256::new_from_slice(key).unwrap_or_else(|_| unreachable!());
    m.update(data);
    m.finalize().into_bytes().into()
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

pub fn sha256_hex(b: &[u8]) -> String {
    hex(&Sha256::digest(b))
}

/// `YYYYMMDDTHHMMSSZ` of a UTC time in µs.
pub fn amz_date(now_us: u64) -> String {
    let secs = now_us / 1_000_000;
    let (days, rem) = ((secs / 86_400) as i64, secs % 86_400);
    // civil from days (H. Hinnant)
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!(
        "{y:04}{m:02}{d:02}T{:02}{:02}{:02}Z",
        rem / 3600,
        rem % 3600 / 60,
        rem % 60
    )
}

/// What one signature covers.
pub struct Signing<'a> {
    pub access_key: &'a str,
    pub secret_key: &'a str,
    pub region: &'a str,
    pub service: &'a str,
    /// `YYYYMMDDTHHMMSSZ`, also sent as `x-amz-date`.
    pub amz_date: &'a str,
}

/// The `Authorization` header of a request. `headers` are every header to sign, names in
/// lowercase (at least `host` and `x-amz-date`); `query` is the canonical query (sorted,
/// encoded) or empty.
pub fn authorization(
    s: &Signing<'_>,
    method: &str,
    path: &str,
    query: &str,
    headers: &[(&str, &str)],
    payload: &[u8],
) -> String {
    let mut hs: Vec<(String, String)> = headers
        .iter()
        .map(|(k, v)| (k.to_ascii_lowercase(), v.trim().to_owned()))
        .collect();
    hs.sort();
    let canonical_headers: String = hs.iter().map(|(k, v)| format!("{k}:{v}\n")).collect();
    let signed: Vec<&str> = hs.iter().map(|(k, _)| k.as_str()).collect();
    let signed = signed.join(";");
    let canonical = format!(
        "{method}\n{path}\n{query}\n{canonical_headers}\n{signed}\n{}",
        sha256_hex(payload)
    );
    let date = &s.amz_date[..8];
    let scope = format!("{date}/{}/{}/aws4_request", s.region, s.service);
    let to_sign = format!(
        "AWS4-HMAC-SHA256\n{}\n{scope}\n{}",
        s.amz_date,
        sha256_hex(canonical.as_bytes())
    );
    let k = hmac(format!("AWS4{}", s.secret_key).as_bytes(), date.as_bytes());
    let k = hmac(&k, s.region.as_bytes());
    let k = hmac(&k, s.service.as_bytes());
    let k = hmac(&k, b"aws4_request");
    let sig = hex(&hmac(&k, to_sign.as_bytes()));
    format!(
        "AWS4-HMAC-SHA256 Credential={}/{scope}, SignedHeaders={signed}, Signature={sig}",
        s.access_key
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const SIGNING: Signing<'static> = Signing {
        access_key: "AKIDEXAMPLE",
        secret_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        region: "us-east-1",
        service: "service",
        amz_date: "20150830T123600Z",
    };

    /// The AWS SigV4 test suite: `get-vanilla` and `post-vanilla`.
    #[test]
    fn aws_test_suite() {
        let headers = [
            ("Host", "example.amazonaws.com"),
            ("X-Amz-Date", "20150830T123600Z"),
        ];
        let prefix =
            "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, \
                      SignedHeaders=host;x-amz-date, Signature=";
        assert_eq!(
            authorization(&SIGNING, "GET", "/", "", &headers, b""),
            format!("{prefix}5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31")
        );
        assert_eq!(
            authorization(&SIGNING, "POST", "/", "", &headers, b""),
            format!("{prefix}5da7c1a2acd57cee7505fc6676e4e544621c30862966e37dddb68e92efbe5d6b")
        );
    }

    #[test]
    fn dates() {
        assert_eq!(amz_date(1_440_938_160_000_000), "20150830T123600Z");
        assert_eq!(amz_date(0), "19700101T000000Z");
        assert_eq!(
            amz_date(951_782_400_000_000),
            "20000229T000000Z",
            "leap day"
        );
        assert_eq!(amz_date(4_102_444_799_000_000), "20991231T235959Z");
    }
}
