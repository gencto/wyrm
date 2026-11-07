use clap::{Parser, Subcommand};
use wyrmd::{Config, Daemon, Error};

#[derive(Parser, Debug)]
#[command(version, about = "WYRM broker")]
struct Args {
    /// Path to wyrmd.json5.
    #[arg(short, long, default_value = "wyrmd.json5", global = true)]
    config: std::path::PathBuf,
    #[command(subcommand)]
    cmd: Option<Cmd>,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Validate the config and exit.
    Check,
    /// Create the site CA if it does not exist, issue the certificates of
    /// the sites in `peers.downstream` (`data_dir/peers/<site>/broker.{pem,key}`,
    /// ADR 0015) and print the path of the CA certificate: the files to
    /// give to those sites (`peers.upstream` `ca`, `cert`, `key`).
    Ca,
    /// Write the WAL head anchors (state_anchor_dir) from the current
    /// stores, after moving or creating that directory. Run with wyrmd
    /// stopped, only on stores you trust.
    InitAnchors,
    /// Check every control-plane store offline (CRC, HMAC chain, anchors)
    /// without changing it; wyrmd must be stopped. Exit code 1 on a problem.
    Verify,
    /// Host one driver as a supervised link process (started by wyrmd).
    Link { driver: String },
    /// Gateway users (wyrmd stopped; passwords are read from stdin).
    #[command(subcommand)]
    User(UserCmd),
    /// The site's key bundle for a warm standby (ADR 0036): export it on
    /// the active broker, import it into the standby's empty data_dir. The
    /// passphrase comes from WYRM_KEYS_PASSPHRASE, else from stdin.
    #[command(subcommand)]
    Keys(KeysCmd),
}

#[derive(Subcommand, Debug)]
enum KeysCmd {
    /// Write the sealed bundle of this broker's keys to a file.
    Export { out: std::path::PathBuf },
    /// Read a bundle into this broker's data_dir (none of its files may exist yet).
    Import { file: std::path::PathBuf },
}

#[derive(Subcommand, Debug)]
enum UserCmd {
    /// Users with roles and state.
    List,
    /// Add a user; the password is read from stdin.
    Add {
        name: String,
        /// Comma-separated roles (viewer, operator, engineer, admin, …).
        #[arg(long, value_delimiter = ',', required = true)]
        roles: Vec<String>,
    },
    /// Set a new password (from stdin); ends the user's sessions.
    Passwd {
        name: String,
    },
    /// Replace the roles.
    Roles {
        name: String,
        #[arg(value_delimiter = ',', required = true)]
        roles: Vec<String>,
    },
    /// Disable (ends sessions) or enable a user.
    Disable {
        name: String,
    },
    Enable {
        name: String,
    },
    Remove {
        name: String,
    },
}

/// One line from stdin, without the line end; never echoed or logged.
fn read_password() -> Result<zeroize::Zeroizing<String>, Error> {
    let mut pw = zeroize::Zeroizing::new(String::new());
    std::io::stdin().read_line(&mut pw)?;
    let trimmed = zeroize::Zeroizing::new(pw.trim_end_matches(['\r', '\n']).to_owned());
    if trimmed.is_empty() {
        return Err("empty password on stdin".into());
    }
    Ok(trimmed)
}

fn user_cmd(cfg: &Config, cmd: UserCmd) -> Result<(), Error> {
    let ua = wyrmd::UserAdmin::open(cfg)?;
    let gw = ua.gateway();
    match cmd {
        UserCmd::List => {
            for (name, roles, disabled) in gw.list_users() {
                let state = if disabled { "disabled" } else { "active" };
                println!("{name:<24} {state:<9} {}", roles.join(","));
            }
            return Ok(());
        }
        UserCmd::Add { name, roles } => {
            let pw = read_password()?;
            gw.add_user(&name, &pw, roles.clone())?;
            ua.record("user", &name, &format!("add roles={}", roles.join(",")))?;
        }
        UserCmd::Passwd { name } => {
            let pw = read_password()?;
            gw.set_password(&name, &pw)?;
            ua.record("user", &name, "password")?;
        }
        UserCmd::Roles { name, roles } => {
            gw.set_roles(&name, roles.clone())?;
            ua.record("user", &name, &format!("roles={}", roles.join(",")))?;
        }
        UserCmd::Disable { name } => {
            gw.set_disabled(&name, true)?;
            ua.record("user", &name, "disabled")?;
        }
        UserCmd::Enable { name } => {
            gw.set_disabled(&name, false)?;
            ua.record("user", &name, "enabled")?;
        }
        UserCmd::Remove { name } => {
            gw.remove_user(&name)?;
            ua.record("user", &name, "remove")?;
        }
    }
    println!("ok");
    Ok(())
}

fn main() -> Result<(), Error> {
    // Text on stdout as before, plus the ring and level behind sys/get_log
    // and sys/log_level.
    wyrm_admin::logs::install();
    let args = Args::parse();
    if matches!(args.cmd, Some(Cmd::Link { .. })) {
        // Before the runtime: no_new_privs reaches only threads created
        // after it (wyrm_link_sdk::limits).
        wyrm_link_sdk::limits::apply_from_env()?;
    }
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    // on a thread with known stack bounds (musl: see `run_on_big_stack`)
    wyrm_link_sdk::process::run_on_big_stack(move || rt.block_on(run(args)))
}

async fn run(args: Args) -> Result<(), Error> {
    if let Some(Cmd::Link { driver }) = &args.cmd {
        return wyrmd::run_link(driver).await;
    }
    let text = std::fs::read_to_string(&args.config)
        .map_err(|e| format!("{}: {e}", args.config.display()))?;
    let cfg = Config::from_json5(&text)?;
    match args.cmd {
        Some(Cmd::Check) => {
            println!("ok");
            return Ok(());
        }
        Some(Cmd::Ca) => {
            let pki = wyrm_admin::secret::Pki::open_or_create(&cfg.data_dir.join("pki"))?;
            for d in &cfg.peers.downstream {
                let f = wyrm_admin::control::broker_cert_in(&pki, &cfg.data_dir, &d.site)?;
                eprintln!("{}: {} {}", d.site, f.cert.display(), f.key.display());
            }
            println!("{}", pki.ca_path().display());
            return Ok(());
        }
        Some(Cmd::User(cmd)) => return user_cmd(&cfg, cmd),
        Some(Cmd::Keys(cmd)) => return keys_cmd(&cfg, cmd),
        Some(Cmd::Verify) => {
            let checks = wyrmd::verify_state(&cfg);
            let mut bad = false;
            for c in &checks {
                match &c.result {
                    Ok(r) => {
                        let anchor = match r.anchor_ok {
                            None => "no anchor",
                            Some(true) => "anchor ok",
                            Some(false) => "ANCHOR MISMATCH",
                        };
                        let torn = if r.torn_tail {
                            ", TORN LAST RECORD (crash or tampering; open drops it)"
                        } else {
                            ""
                        };
                        println!(
                            "{:<20} ok: {} records, lsn {}, {anchor}{torn}",
                            c.name, r.records, r.last_lsn
                        );
                    }
                    Err(e) => println!("{:<20} FAILED: {e}", c.name),
                }
                bad |= !c.ok();
            }
            if bad {
                std::process::exit(1);
            }
            return Ok(());
        }
        Some(Cmd::InitAnchors) => {
            if cfg.state_anchor_dir.is_none() {
                return Err("state_anchor_dir is not set in the config".into());
            }
            let mut cfg = cfg;
            cfg.init_anchors = true;
            drop(Daemon::open(cfg, std::env::current_exe()?)?);
            println!("anchors written");
            return Ok(());
        }
        _ => {}
    }
    if cfg.admin_keys.is_empty() {
        tracing::warn!("no admin_keys: every set/invoke will be denied");
    }
    if cfg.standby.is_some() {
        return run_with_standby(cfg).await;
    }
    let daemon = Daemon::open(cfg, std::env::current_exe()?)?;
    daemon
        .run_until(async {
            stop_signal().await;
            tracing::info!("stopping");
        })
        .await
}

/// A broker of a standby pair (ADR 0036): follow the other broker until it
/// is away, then run as the active one; a non-primary active steps down
/// and follows again when the primary is back.
async fn run_with_standby(cfg: Config) -> Result<(), Error> {
    use std::sync::atomic::{AtomicBool, Ordering};
    use wyrmd::standby::{follow, isolated, primary_is_back, Outcome};
    let exe = std::env::current_exe()?;
    let peer = cfg
        .standby
        .as_ref()
        .map(|s| s.peer.clone())
        .unwrap_or_default();
    loop {
        match follow(&cfg, stop_signal()).await? {
            Outcome::Stopped => return Ok(()),
            Outcome::Takeover => {}
        }
        let daemon = Daemon::open(cfg.clone(), exe.clone())?;
        wyrmd::standby::mark_active(&cfg.data_dir);
        let ctl = daemon.control();
        ctl.record(
            "system",
            "promoted",
            &peer,
            wyrm_core::Status::Ok,
            "the other broker was away",
        );
        tracing::warn!("standby: promoted; this broker is the active one now");
        let demoted = std::sync::Arc::new(AtomicBool::new(false));
        let flag = demoted.clone();
        let (ctl2, cfg2, peer2) = (ctl.clone(), cfg.clone(), peer.clone());
        daemon
            .run_until(async move {
                tokio::select! {
                    _ = stop_signal() => tracing::info!("stopping"),
                    _ = primary_is_back(&cfg2) => {
                        flag.store(true, Ordering::SeqCst);
                        ctl2.record("system", "demoted", &peer2, wyrm_core::Status::Ok, "the primary broker is back");
                        tracing::warn!("standby: the primary is back; stepping down to follow it");
                    }
                    _ = isolated(&cfg2, &ctl2) => {
                        flag.store(true, Ordering::SeqCst);
                        ctl2.record("system", "demoted", &peer2, wyrm_core::Status::Ok, "cut off: no witness and no standby");
                        tracing::warn!("standby: cut off (no witness answers, the standby is quiet); stepping down");
                    }
                }
            })
            .await?;
        if !demoted.load(Ordering::SeqCst) {
            return Ok(());
        }
    }
}

fn passphrase() -> Result<zeroize::Zeroizing<Vec<u8>>, Error> {
    if let Ok(p) = std::env::var("WYRM_KEYS_PASSPHRASE") {
        return Ok(zeroize::Zeroizing::new(p.into_bytes()));
    }
    eprintln!("passphrase (WYRM_KEYS_PASSPHRASE not set; read from stdin):");
    let mut line = String::new();
    std::io::stdin().read_line(&mut line)?;
    Ok(zeroize::Zeroizing::new(
        line.trim_end_matches(['\r', '\n']).as_bytes().to_vec(),
    ))
}

fn keys_cmd(cfg: &Config, cmd: KeysCmd) -> Result<(), Error> {
    match cmd {
        KeysCmd::Export { out } => {
            let bundle = wyrm_admin::keys::export(&cfg.data_dir, &passphrase()?)?;
            wyrm_admin::secret::write_private(&out, &bundle)?;
            println!(
                "{}: {} bytes (keep it as the site itself)",
                out.display(),
                bundle.len()
            );
        }
        KeysCmd::Import { file } => {
            let bundle = std::fs::read(&file)?;
            std::fs::create_dir_all(&cfg.data_dir)?;
            let names = wyrm_admin::keys::import(&cfg.data_dir, &bundle, &passphrase()?)?;
            println!(
                "imported into {}: {}",
                cfg.data_dir.display(),
                names.join(", ")
            );
        }
    }
    Ok(())
}

/// SIGINT (Ctrl-C) or SIGTERM (systemd, docker, `kill`): a clean stop that
/// flushes the historian and ends the link processes (ADR 0036, option 1).
async fn stop_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut term = match signal(SignalKind::terminate()) {
            Ok(t) => t,
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
                return;
            }
        };
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {}
            _ = term.recv() => {}
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
