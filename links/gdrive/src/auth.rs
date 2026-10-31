//! OAuth 2.0 access tokens for the Drive API: a service account (a JWT
//! signed RS256 with its key, RFC 7523) or a user's refresh token. A token
//! is kept until a minute before it expires, or until the API refuses it.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use hyper::Method;
use ring::signature::{RsaKeyPair, RSA_PKCS1_SHA256};
use serde_json::Value as Json;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use wyrm_filestore::http::{Http, Request};
use wyrm_filestore::util::pct_encode;
use wyrm_filestore::Error;

/// The Drive scope: files the account can see.
pub const SCOPE: &str = "https://www.googleapis.com/auth/drive";
const JWT_GRANT: &str = "urn:ietf:params:oauth:grant-type:jwt-bearer";

pub enum Grant {
    ServiceAccount {
        email: String,
        key: Box<RsaKeyPair>,
        /// Domain-wide delegation: act as this user.
        subject: Option<String>,
    },
    RefreshToken {
        client_id: String,
        client_secret: zeroize::Zeroizing<String>,
        refresh_token: zeroize::Zeroizing<String>,
    },
}

/// A private key from PEM (`PRIVATE KEY`, PKCS#8) as in a service
/// account's JSON key. Errors never echo the key.
pub fn rsa_key(pem: &str) -> Result<RsaKeyPair, String> {
    let body: String = pem
        .lines()
        .map(str::trim)
        .skip_while(|l| !l.starts_with("-----BEGIN PRIVATE KEY-----"))
        .skip(1)
        .take_while(|l| !l.starts_with("-----END"))
        .collect();
    let der = base64::engine::general_purpose::STANDARD
        .decode(body.as_bytes())
        .map_err(|_| "not a PEM private key (PKCS#8 'PRIVATE KEY')".to_owned())?;
    RsaKeyPair::from_pkcs8(&der)
        .map_err(|_| "not an RSA private key of 2048 bits or more".to_owned())
}

pub struct Tokens {
    pub grant: Grant,
    pub http: Http,
    /// The token endpoint's path and query.
    pub path: String,
    /// `aud` of the JWT: the token URL.
    pub url: String,
    pub timeout: Duration,
    cached: Mutex<Option<(zeroize::Zeroizing<String>, Instant)>>,
}

fn now_s() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl Tokens {
    pub fn new(grant: Grant, http: Http, path: String, url: String, timeout: Duration) -> Self {
        Self {
            grant,
            http,
            path,
            url,
            timeout,
            cached: Mutex::new(None),
        }
    }

    fn assertion(
        &self,
        email: &str,
        key: &RsaKeyPair,
        subject: Option<&str>,
    ) -> Result<String, Error> {
        let iat = now_s();
        let mut claims = serde_json::json!({
            "iss": email,
            "scope": SCOPE,
            "aud": self.url,
            "iat": iat,
            "exp": iat + 3600,
        });
        if let Some(s) = subject {
            claims["sub"] = Json::String(s.to_owned());
        }
        let head = URL_SAFE_NO_PAD.encode(br#"{"alg":"RS256","typ":"JWT"}"#);
        let body = URL_SAFE_NO_PAD.encode(claims.to_string());
        let signing = format!("{head}.{body}");
        let mut sig = vec![0u8; key.public().modulus_len()];
        key.sign(
            &RSA_PKCS1_SHA256,
            &ring::rand::SystemRandom::new(),
            signing.as_bytes(),
            &mut sig,
        )
        .map_err(|_| Error::Auth("signing the token request failed".into()))?;
        Ok(format!("{signing}.{}", URL_SAFE_NO_PAD.encode(sig)))
    }

    /// Forget the token (the API refused it).
    pub async fn drop_token(&self) {
        *self.cached.lock().await = None;
    }

    /// A valid access token.
    pub async fn token(&self) -> Result<zeroize::Zeroizing<String>, Error> {
        let mut c = self.cached.lock().await;
        if let Some((t, until)) = c.as_ref() {
            if Instant::now() < *until {
                return Ok(t.clone());
            }
        }
        let form = match &self.grant {
            Grant::ServiceAccount {
                email,
                key,
                subject,
            } => format!(
                "grant_type={}&assertion={}",
                pct_encode(JWT_GRANT, false),
                self.assertion(email, key, subject.as_deref())?
            ),
            Grant::RefreshToken {
                client_id,
                client_secret,
                refresh_token,
            } => format!(
                "grant_type=refresh_token&client_id={}&client_secret={}&refresh_token={}",
                pct_encode(client_id, false),
                pct_encode(client_secret, false),
                pct_encode(refresh_token, false)
            ),
        };
        let req = Request::new(Method::POST, self.path.clone())
            .header("content-type", "application/x-www-form-urlencoded")
            .header("accept", "application/json")
            .body(form.into_bytes());
        let r = self.http.send(&req, self.timeout, 64 * 1024).await?;
        let j: Json = serde_json::from_slice(&r.body).unwrap_or(Json::Null);
        if !r.ok() {
            // `error` and `error_description` name the problem, never a secret
            let e = j["error"].as_str().unwrap_or("");
            let d = j["error_description"].as_str().unwrap_or("");
            return Err(match r.status {
                400 | 401 | 403 => Error::Auth(format!("token: HTTP {} {e} {d}", r.status)),
                _ => Error::Unreachable(format!("token: HTTP {} {e}", r.status)),
            });
        }
        let token = j["access_token"]
            .as_str()
            .filter(|t| !t.is_empty())
            .ok_or_else(|| Error::Auth("token: no access_token in the reply".into()))?;
        let life = j["expires_in"].as_u64().unwrap_or(3600).clamp(60, 86_400);
        let t = zeroize::Zeroizing::new(token.to_owned());
        *c = Some((t.clone(), Instant::now() + Duration::from_secs(life - 60)));
        Ok(t)
    }
}
