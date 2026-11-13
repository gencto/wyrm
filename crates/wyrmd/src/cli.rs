//! The command line of `wyrmd` (`src/main.rs` calls [`main`]).

use crate::{Config, Daemon, Error};
use clap::{Parser, Subcommand};

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
    /// Validate the config and exit. With `--state`, also open every
    /// control-plane store of that directory (a copy of a broker's state,
    /// laid out as a data_dir) with this binary: what a broker runs a newer
    /// version with before it updates to it (ADR 0048).
    Check {
        #[arg(long)]
        state: Option<std::path::PathBuf>,
    },
    /// Print what this binary is as JSON: version, target, the SCHEMA of
    /// each control-plane store, the replication protocol (no wyrmd.json5).
    ReleaseInfo,
    /// Before every start of a broker that updates itself (the unit's
    /// ExecStartPre, run as <prefix>/bin/wyrmd-guard): take back an update
    /// whose trial failed (ADR 0048).
    UpdateGuard,
    /// For a unit that keeps <prefix>/bin away from the broker's user: run
    /// as root after update-guard (`ExecStartPre=+`), it makes the guard
    /// the verified binary of the current version.
    GuardRefresh,
    /// Make the install layout of a broker that updates itself in PREFIX
    /// from this binary: versions/<version>/wyrmd, current, bin/wyrmd-guard
    /// (no wyrmd.json5).
    InstallLayout { prefix: std::path::PathBuf },
    /// Release tooling: pack, describe, index and sign a wyrmd release
    /// (ADR 0048; `packaging/wyrmd`). No wyrmd.json5.
    #[command(subcommand)]
    Release(crate::update::ReleaseCmd),
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
    /// The lease arbiter of a standby pair (ADR 0036), on a third host:
    /// `issue` its files on a broker of the pair, `serve` them there.
    #[command(subcommand)]
    Arbiter(ArbiterCmd),
}

#[derive(Subcommand, Debug)]
enum ArbiterCmd {
    /// Write an arbiter's directory from this broker's site CA: ca.pem,
    /// arbiter.{pem,key} for HOST (the name or IPv4 address the brokers
    /// dial in standby.arbiter) and the site name.
    Issue {
        #[arg(long)]
        host: String,
        #[arg(long)]
        out: std::path::PathBuf,
    },
    /// Serve the lease of the site whose files are in DIR (no wyrmd.json5).
    Serve {
        #[arg(long)]
        dir: std::path::PathBuf,
        /// Address to listen on, e.g. 0.0.0.0:7450.
        #[arg(long)]
        listen: String,
    },
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
    let ua = crate::UserAdmin::open(cfg)?;
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

/// Run `wyrmd` with the arguments of this process. `test`: a build that
/// says it is another version (the update tests' second binary); `wyrmd`
/// passes `None`.
pub fn main(test: Option<crate::update::TestBuild>) -> Result<(), Error> {
    wyrm_admin::release::set_identity(crate::update::identity(test.as_ref()));
    let mut args = Args::parse();
    if matches!(args.cmd, Some(Cmd::Release(_))) {
        let Some(Cmd::Release(cmd)) = args.cmd.take() else {
            return Ok(());
        };
        return crate::update::release_cmd(cmd);
    }
    match &args.cmd {
        Some(Cmd::ReleaseInfo) => {
            println!(
                "{}",
                serde_json::to_string(wyrm_admin::release::identity()).map_err(|e| e.to_string())?
            );
            return Ok(());
        }
        Some(Cmd::InstallLayout { prefix }) => {
            let me = &wyrm_admin::release::identity().version;
            let l = wyrm_admin::release::Layout::install(prefix, &std::env::current_exe()?, me)?;
            println!(
                "ExecStartPre={} -c <wyrmd.json5> update-guard\nExecStart={} -c <wyrmd.json5>",
                l.guard().display(),
                l.current().join(wyrm_admin::release::BIN).display()
            );
            return Ok(());
        }
        _ => {}
    }
    // Text on stdout as before, plus the ring and level behind sys/get_log
    // and sys/log_level.
    wyrm_admin::logs::install();
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
        return crate::run_link(driver).await;
    }
    if let Some(Cmd::Arbiter(ArbiterCmd::Serve { dir, listen })) = &args.cmd {
        return crate::arbiter::serve(dir, listen, async {
            stop_signal().await;
            tracing::info!("stopping");
        })
        .await;
    }
    let text = std::fs::read_to_string(&args.config)
        .map_err(|e| format!("{}: {e}", args.config.display()))?;
    let mut cfg = Config::from_json5(&text)?;
    cfg.config_file = Some(args.config.clone());
    match args.cmd {
        Some(Cmd::Check { state }) => {
            if let Some(dir) = state {
                for line in crate::update::check_state(&dir)? {
                    println!("{line}");
                }
            }
            println!("ok");
            return Ok(());
        }
        Some(Cmd::UpdateGuard) => return crate::update::run_guard(&cfg),
        Some(Cmd::GuardRefresh) => return crate::update::run_guard_refresh(&cfg),
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
        Some(Cmd::Arbiter(ArbiterCmd::Issue { host, out })) => {
            crate::arbiter::issue(&cfg, &host, &out)?;
            println!("{}", out.display());
            return Ok(());
        }
        Some(Cmd::Verify) => {
            let checks = crate::verify_state(&cfg);
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
    // the trial of a new version begins with its first start (ADR 0048 §2.5)
    crate::update::trial_start(&cfg.data_dir, cfg.updates.trial_s);
    // a broker that updates itself runs only a verified binary (ADR 0048 §2)
    crate::update::verify_self(&cfg, &own_exe()?)?;
    if cfg.standby.is_some() {
        return run_with_standby(cfg).await;
    }
    let daemon = Daemon::open(cfg, own_exe()?)?;
    let ctl = daemon.control();
    daemon
        .run_until(async {
            stop_signal().await;
            tracing::info!("stopping");
        })
        .await?;
    exit_if_asked(&ctl);
    Ok(())
}

/// This binary's own file, not a link to it: a broker started as
/// `<prefix>/current/wyrmd` hosts its process links with the version it is,
/// also after `current` moved to the next one (ADR 0048 §2).
fn own_exe() -> Result<std::path::PathBuf, Error> {
    let exe = std::env::current_exe()?;
    Ok(exe.canonicalize().unwrap_or(exe))
}

/// A new version that gave its trial up ends with the code the guard and
/// the supervisor read (ADR 0048 §2.5).
fn exit_if_asked(ctl: &wyrm_admin::Control) {
    if let Some(code) = ctl.exit_code() {
        std::process::exit(code);
    }
}

/// A broker of a standby pair (ADR 0036): follow the other broker until it
/// is away, then run as the active one; a non-primary active steps down
/// and follows again when the primary is back.
async fn run_with_standby(cfg: Config) -> Result<(), Error> {
    use crate::standby::{follow_with, isolated, lease_lost, primary_is_back, Outcome};
    use std::sync::atomic::{AtomicBool, Ordering};
    let exe = own_exe()?;
    let arbiters = crate::arbiter::Arbiters::of(&cfg)?;
    if arbiters.is_none() {
        tracing::warn!("standby: no standby.arbiter: a split where both hosts reach a witness but not each other makes both brokers active (ADR 0036)");
    }
    let peer = cfg
        .standby
        .as_ref()
        .map(|s| s.peer.clone())
        .unwrap_or_default();
    loop {
        let followed = tokio::select! {
            r = follow_with(&cfg, arbiters.clone(), stop_signal()) => r?,
            // a standby in its trial that never followed again gives up
            _ = crate::update::standby_trial(&cfg.data_dir, &exe) => {
                std::process::exit(wyrm_admin::release::TRIAL_EXIT);
            }
        };
        match followed {
            // `Update`: the new version is current; the supervisor starts it
            Outcome::Stopped | Outcome::Update => return Ok(()),
            Outcome::Takeover => {}
        }
        // `follow` took the lease (its send time is in the shared
        // arbiters): renewed from here on, before the daemon opens
        let held = std::sync::Arc::new(std::sync::Mutex::new(crate::arbiter::Held::default()));
        let keeper = arbiters
            .clone()
            .map(|a| AbortOnDrop(tokio::spawn(crate::arbiter::keep(a, held.clone()))));
        let daemon = Daemon::open(cfg.clone(), exe.clone())?;
        crate::standby::mark_active(&cfg.data_dir);
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
        let (held2, leased) = (held.clone(), keeper.is_some());
        daemon
            .run_until(async move {
                tokio::select! {
                    why = async { if leased { lease_lost(held2, &ctl2).await } else { std::future::pending().await } } => {
                        flag.store(true, Ordering::SeqCst);
                        ctl2.record("system", "demoted", &peer2, wyrm_core::Status::Ok, why);
                        tracing::warn!("standby: {why}; stepping down");
                    }
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
        exit_if_asked(&ctl);
        drop(keeper);
        if let Some(a) = &arbiters {
            // stopped or stepped down: the lease is free for the other host
            // (it holds it already if it was taken away)
            a.release().await;
        }
        if !demoted.load(Ordering::SeqCst) {
            return Ok(());
        }
    }
}

/// Aborts the task when dropped.
struct AbortOnDrop(tokio::task::JoinHandle<()>);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
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
