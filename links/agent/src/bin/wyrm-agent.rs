//! `wyrm-agent`: work on a broker network through a gateway, as one of its users (ADR 0033).
//! Every command prints JSON, one object per line. The password comes from
//! `WYR_GATEWAY_PASSWORD` (never from the command line).

use clap::{Parser, Subcommand};
use serde_json::{json, Value as Json};
use std::time::Duration;
use wyrm_link_agent::cli;
use wyrm_mcp::json::json_to_value;

#[derive(Parser)]
#[command(
    version,
    about = "Work on WYRM brokers through a gateway: read, change, run plans"
)]
struct Args {
    /// The gateway, `http://host:port`; it reaches the sites below its own.
    #[arg(long, default_value = "http://127.0.0.1:8445", env = "WYR_GATEWAY")]
    gateway: String,
    #[arg(long, default_value = "admin", env = "WYR_GATEWAY_USER")]
    user: String,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// The nodes below a key, `depth` levels.
    Tree {
        key: String,
        #[arg(long, default_value_t = 1)]
        depth: usize,
    },
    /// The full `~meta` of a node: type, unit, actions with their parameters.
    Meta { key: String },
    /// Current values.
    Get { keys: Vec<String> },
    /// Samples of a key or a pattern (`wy/edge/downstream/mock/**`) for a while.
    Watch {
        pattern: String,
        #[arg(long, default_value_t = 5.0)]
        seconds: f64,
    },
    /// Write a value (JSON: `21.5`, `true`, `"text"`).
    Set { key: String, value: String },
    /// Run an action with JSON arguments (`{"name": "ahu2", "unit": 1}`).
    Invoke {
        key: String,
        action: String,
        #[arg(default_value = "{}")]
        args: String,
    },
    /// Recorded values of a point: JSON arguments as spec 01 `~val?history=`
    /// (`{"from": "2026-11-01T00:00:00Z", "limit": 100}`).
    History { key: String, args: String },
    /// Check a plan file against the live tree; `--apply` runs it.
    Run {
        plan: std::path::PathBuf,
        #[arg(long)]
        apply: bool,
    },
}

fn line(j: &Json) {
    println!("{j}");
}

fn parse(s: &str, what: &str) -> Result<Json, String> {
    serde_json::from_str(s).map_err(|e| format!("{what}: not JSON: {e}"))
}

async fn main_r(a: Args) -> Result<bool, String> {
    let password = std::env::var("WYR_GATEWAY_PASSWORD")
        .map_err(|_| "set WYR_GATEWAY_PASSWORD to the user's password".to_owned())?;
    let c = cli::connect(&a.gateway, &a.user, &password).await?;
    match a.cmd {
        Cmd::Tree { key, depth } => cli::tree(&c, &key, depth.clamp(1, 8))
            .await?
            .iter()
            .for_each(line),
        Cmd::Meta { key } => line(&cli::meta(&c, &key).await?),
        Cmd::Get { keys } => {
            for k in keys {
                match cli::get(&c, &k, Duration::from_secs(3)).await {
                    Ok(j) => line(&j),
                    Err(e) => line(&json!({ "key": k, "error": e })),
                }
            }
        }
        Cmd::Watch { pattern, seconds } => cli::watch(&c, &pattern, seconds.min(600.0))
            .await?
            .iter()
            .for_each(line),
        Cmd::Set { key, value } => {
            let v = json_to_value(&parse(&value, "value")?)?;
            line(&cli::set(&c, &key, v).await?);
        }
        Cmd::Invoke { key, action, args } => {
            let v = json_to_value(&parse(&args, "args")?)?;
            line(&cli::invoke(&c, &key, &action, v).await?);
        }
        Cmd::History { key, args } => {
            let v = json_to_value(&parse(&args, "args")?)?;
            line(&cli::history(&c, &key, v).await?);
        }
        Cmd::Run { plan, apply } => {
            let text =
                std::fs::read_to_string(&plan).map_err(|e| format!("{}: {e}", plan.display()))?;
            let steps = cli::parse_plan(&parse(&text, "plan")?)?;
            if !apply {
                let mut ok = true;
                for s in &steps {
                    let j = cli::check_step(&c, s).await;
                    ok &= j["check"] != json!("error");
                    line(&j);
                }
                line(
                    &json!({ "plan": plan.display().to_string(), "steps": steps.len(), "checked": ok, "applied": false }),
                );
                return Ok(ok);
            }
            for (i, s) in steps.iter().enumerate() {
                match cli::run_step(&c, s).await {
                    Ok(j) => line(&j),
                    Err(e) => {
                        line(&json!({ "step": i + 1, "error": e }));
                        line(
                            &json!({ "plan": plan.display().to_string(), "applied": false, "failed_at": i + 1 }),
                        );
                        return Ok(false);
                    }
                }
            }
            line(
                &json!({ "plan": plan.display().to_string(), "steps": steps.len(), "applied": true }),
            );
        }
    }
    Ok(true)
}

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() {
    let a = Args::parse();
    match main_r(a).await {
        Ok(true) => {}
        Ok(false) => std::process::exit(1),
        Err(e) => {
            line(&json!({ "error": e }));
            std::process::exit(2);
        }
    }
}
