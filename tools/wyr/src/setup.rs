//! `wyr setup --gateway https://<device address>:8445` (ADR 0051 §3): the first admin of a
//! new broker from the setup code of its image, through `wyrm_gateway_client::setup`.
//!
//! The code and the password are read from the terminal with echo off, or, when stdin is
//! no terminal, as its first and second line; never from the command line. The device's
//! CA is proven by the code before anything is sent, and pinned for every request after
//! that. `--ca-out` writes it as PEM: the `--gateway-ca` of `wyrm-mcp` and `wyrm-agent`.

use std::io::{BufRead, IsTerminal, Write};
use std::path::PathBuf;
use wyrm_gateway_client::setup::{self, HASH_TIMEOUT};
use zeroize::Zeroizing;

use crate::Error;

#[derive(clap::Args, Debug)]
pub struct SetupArgs {
    /// The device's gateway: https://<address or wyrm-<site>.local>[:port] (a board
    /// image listens on 8445).
    #[arg(long)]
    pub gateway: String,
    /// The name of the first admin.
    #[arg(long, default_value = "admin")]
    pub user: String,
    /// Write the device's CA here as PEM (for `--gateway-ca` of wyrm-mcp and wyrm-agent).
    #[arg(long)]
    pub ca_out: Option<PathBuf>,
}

/// Where the code and the password come from: the terminal, or the lines of stdin.
enum Input {
    Terminal,
    Lines(std::io::StdinLock<'static>),
}

impl Input {
    fn open() -> Self {
        if std::io::stdin().is_terminal() {
            Input::Terminal
        } else {
            Input::Lines(std::io::stdin().lock())
        }
    }

    /// One secret: asked for with echo off on a terminal, else the next line of stdin.
    fn secret(&mut self, prompt: &str, what: &str) -> Result<Zeroizing<String>, Error> {
        let mut line = Zeroizing::new(String::new());
        match self {
            Input::Terminal => {
                let mut err = std::io::stderr();
                write!(err, "{prompt}")?;
                err.flush()?;
                let echo = Echo::off();
                let read = std::io::stdin().lock().read_line(&mut line);
                drop(echo);
                writeln!(err)?;
                read?;
            }
            Input::Lines(lines) => {
                lines.read_line(&mut line)?;
            }
        }
        let text = Zeroizing::new(line.trim_end_matches(['\r', '\n']).to_owned());
        if text.is_empty() {
            return Err(format!("no {what} given").into());
        }
        Ok(text)
    }

    fn is_terminal(&self) -> bool {
        matches!(self, Input::Terminal)
    }
}

/// The terminal's echo, off while this lives (unix; elsewhere the input shows).
struct Echo {
    #[cfg(unix)]
    saved: Option<rustix::termios::Termios>,
}

impl Echo {
    fn off() -> Self {
        #[cfg(unix)]
        {
            use rustix::termios::{tcgetattr, tcsetattr, LocalModes, OptionalActions};
            let stdin = std::io::stdin();
            let saved = tcgetattr(&stdin).ok();
            if let Some(t) = &saved {
                let mut quiet = t.clone();
                quiet.local_modes.remove(LocalModes::ECHO);
                if tcsetattr(&stdin, OptionalActions::Now, &quiet).is_err() {
                    return Echo { saved: None };
                }
            }
            Echo { saved }
        }
        #[cfg(not(unix))]
        Echo {}
    }
}

impl Drop for Echo {
    fn drop(&mut self) {
        #[cfg(unix)]
        if let Some(t) = &self.saved {
            let back = rustix::termios::tcsetattr(
                std::io::stdin(),
                rustix::termios::OptionalActions::Now,
                t,
            );
            if back.is_err() {
                eprintln!("wyr: the terminal's echo could not be turned back on: run `stty echo`");
            }
        }
    }
}

/// [`setup::Offer::ca_fp`] in 8 groups of 4, as Studio and `wyrmd ca fingerprint` show it.
fn grouped(fp: &str) -> String {
    fp.as_bytes()
        .chunks(4)
        .map(String::from_utf8_lossy)
        .collect::<Vec<_>>()
        .join(" ")
}

/// `der` as one PEM certificate.
pub fn ca_pem(der: &[u8]) -> String {
    use base64::Engine as _;
    let b64 = base64::engine::general_purpose::STANDARD.encode(der);
    let mut out = String::from("-----BEGIN CERTIFICATE-----\n");
    for line in b64.as_bytes().chunks(64) {
        out.push_str(&String::from_utf8_lossy(line));
        out.push('\n');
    }
    out.push_str("-----END CERTIFICATE-----\n");
    out
}

pub async fn run(args: SetupArgs) -> Result<(), Error> {
    let mut input = Input::open();
    let code = input.secret("Setup code: ", "setup code")?;
    let pending = setup::begin(&args.gateway, &code).await?;
    let offer = pending.offer().clone();
    eprintln!(
        "The setup code proves this device's CA {} (site {}); its certificate is checked against {} from now on.",
        grouped(&offer.ca_fp),
        offer.site,
        pending.name()
    );
    let password = input.secret(&format!("Password for {}: ", args.user), "password")?;
    if input.is_terminal() {
        let again = input.secret("The password again: ", "password")?;
        if *again != *password {
            return Err("the two passwords differ: nothing was sent. Run wyr setup again".into());
        }
    }
    pending
        .finish(&code, &args.user, &password, HASH_TIMEOUT)
        .await?;
    out!(
        "Site {}: the first admin is the user {}, and the login works.",
        offer.site,
        args.user
    );
    out!(
        "The device's CA: {} (keep this code: Studio and `wyrmd ca fingerprint` on the device show the same one).",
        grouped(&offer.ca_fp)
    );
    if let Some(path) = &args.ca_out {
        std::fs::write(path, ca_pem(&offer.ca_der))
            .map_err(|e| format!("{}: {e}", path.display()))?;
        out!(
            "The CA is in {} (PEM): give it as --gateway-ca to wyrm-mcp and wyrm-agent.",
            path.display()
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, reason = "test code")]
    use super::*;

    #[test]
    fn the_pem_is_the_der() {
        use rustls_pki_types::pem::PemObject as _;
        let der: Vec<u8> = (0..=255u8).cycle().take(1000).collect();
        let pem = ca_pem(&der);
        assert!(pem.starts_with("-----BEGIN CERTIFICATE-----\n"));
        assert!(pem.ends_with("-----END CERTIFICATE-----\n"));
        assert!(pem.lines().all(|l| l.len() <= 64));
        let back = rustls_pki_types::CertificateDer::from_pem_slice(pem.as_bytes()).unwrap();
        assert_eq!(back.as_ref(), &der[..]);
    }

    #[test]
    fn the_code_reads_in_groups_of_four() {
        assert_eq!(
            grouped("de7263810b15bd9c80806f95fd2e5230"),
            "de72 6381 0b15 bd9c 8080 6f95 fd2e 5230"
        );
    }
}
