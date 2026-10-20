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

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,zenoh=warn".into()),
        )
        .init();
    let args = Args::parse();
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
        Some(Cmd::User(cmd)) => return user_cmd(&cfg, cmd),
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
    let daemon = Daemon::open(cfg, std::env::current_exe()?)?;
    daemon
        .run_until(async {
            let _ = tokio::signal::ctrl_c().await;
            tracing::info!("stopping");
        })
        .await
}
