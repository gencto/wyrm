//! The probe link: runs test scenarios against a broker through its user
//! gateway, as a person in the explorer would, and reports every step:
//! actions and their answers, the `list` callbacks they cause (`added`,
//! `changed`, `removed`) with their delays, and values on subscriptions.
//!
//! It logs in as a gateway user (params `gateway`, a loopback URL; `user`;
//! the link secret `password`), so its rights are that user's: only that
//! very user may run it (`run` and `run_builtin` need `config` too), and
//! secret-looking fields of results are hidden in its reports. [`scenario`] describes the steps; [`runner`] runs them.
//! `wyr probe` runs the same scenarios from a terminal.

#![forbid(unsafe_code)]

pub mod runner;
pub mod scenario;

use std::collections::BTreeMap;
use wyrm_core::meta::{ActionResult, ParamMeta, EDITOR_TEXTAREA};
use wyrm_core::{ActionMeta, NodeMeta, Perm, Quality, TypeCode, Value};
use wyrm_link_sdk::params::Fields;
use wyrm_link_sdk::{now_us, Caller, FromParams, Link, LinkCtx, LinkError, ReplySink, Result};

pub use runner::{run, Report};
pub use scenario::{builtin, Scenario, BUILTIN};

/// Name of the link secret with the gateway user's password.
pub const PASSWORD: &str = "password";

/// Longest run of one scenario.
const RUN_TIMEOUT_MS: u32 = 120_000;

pub struct ProbeConfig {
    /// `http://127.0.0.1:<port>` of the broker's gateway.
    pub gateway: String,
    pub user: String,
    /// Site of `{site}` in scenarios; default the link's own.
    pub site: Option<String>,
}

impl FromParams for ProbeConfig {
    fn from_params(v: &Value) -> Result<Self> {
        let f = Fields::new(v)?;
        f.only(&["gateway", "user", "site"])?;
        Ok(Self {
            gateway: f
                .opt_str("gateway")?
                .unwrap_or("http://127.0.0.1:8445")
                .to_owned(),
            user: f.opt_str("user")?.unwrap_or("admin").to_owned(),
            site: f.opt_str("site")?.map(str::to_owned),
        })
    }
}

pub struct Probe {
    ctx: LinkCtx,
    cfg: ProbeConfig,
    password: Option<String>,
}

const VALUES: [(&str, TypeCode); 5] = [
    ("last_scenario", TypeCode::String),
    ("last_result", TypeCode::String),
    ("last_failed", TypeCode::Number),
    ("last_ms", TypeCode::Number),
    ("runs", TypeCode::Number),
];

impl Probe {
    async fn run_text(&mut self, text: &str, site: Option<&str>) -> Result<Value> {
        let sc = Scenario::parse(text).map_err(LinkError::invalid_parameter)?;
        let password = self.password.clone().ok_or_else(|| {
            LinkError::invalid_parameter(format!(
                "no gateway password: set the link secret {PASSWORD:?} (sys/links/<id> ▸ Set Secret) and restart the link"
            ))
        })?;
        let gw = wyrm_gateway_client::Gateway::login(&self.cfg.gateway, &self.cfg.user, &password)
            .await
            .map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
        let conn = gw
            .connect()
            .await
            .map_err(|e| LinkError::invalid_parameter(e.to_string()))?;
        let site = site
            .map(str::to_owned)
            .or_else(|| self.cfg.site.clone())
            .unwrap_or_else(|| self.ctx.site().to_owned());
        let report = run(&conn, &sc, BTreeMap::from([("site".to_owned(), site)])).await;
        self.publish(&report).await?;
        Ok(report.rows_value())
    }

    async fn publish(&self, r: &Report) -> Result<()> {
        let t = now_us();
        let runs = match self.ctx.last("runs").map(|s| s.v) {
            Some(Value::UInt(n)) => n + 1,
            _ => 1,
        };
        let failed = r.count(Some(false)) as u64;
        for (k, v) in [
            ("last_scenario", Value::from(r.name.as_str())),
            (
                "last_result",
                Value::from(if r.passed() { "passed" } else { "failed" }),
            ),
            ("last_failed", Value::UInt(failed)),
            ("last_ms", Value::UInt(r.ms)),
            ("runs", Value::UInt(runs)),
        ] {
            self.ctx.update(k, v, Quality::Good, t).await?;
        }
        Ok(())
    }
}

fn site_param() -> ParamMeta {
    ParamMeta::of(TypeCode::String)
        .display("Site")
        .description("{site} in the scenario; default the link's site param, else its own site")
}

impl Link for Probe {
    const NAME: &'static str = "probe";
    const VERSION: &'static str = env!("CARGO_PKG_VERSION");
    type Config = ProbeConfig;

    async fn start(cfg: ProbeConfig, ctx: LinkCtx) -> Result<Self> {
        for (k, ty) in VALUES {
            ctx.declare_node(k, NodeMeta::leaf(ty)).await?;
        }
        ctx.declare_action(
            "",
            "run_builtin",
            ActionMeta::new()
                .display("Run Scenario")
                .param(
                    "name",
                    ParamMeta::of(TypeCode::String)
                        .enum_values(BUILTIN.iter().map(|(n, _)| *n))
                        .required(true)
                        .display("Scenario"),
                )
                .param("site", site_param())
                .result(ActionResult::Type(TypeCode::Array))
                .timeout_ms(RUN_TIMEOUT_MS)
                .level(Perm::Config),
        )
        .await?;
        ctx.declare_action(
            "",
            "run",
            ActionMeta::new()
                .display("Run Steps")
                .param(
                    "scenario",
                    ParamMeta::of(TypeCode::String)
                        .required(true)
                        .editor(EDITOR_TEXTAREA)
                        .display("Scenario")
                        .description(
                            "JSON: {\"name\", \"steps\": [...]} (links/probe/src/scenario.rs)",
                        ),
                )
                .param("site", site_param())
                .result(ActionResult::Type(TypeCode::Array))
                .timeout_ms(RUN_TIMEOUT_MS)
                .level(Perm::Config),
        )
        .await?;
        let password = ctx
            .secrets()
            .get(PASSWORD)
            .and_then(|s| s.expose_str().map(str::to_owned));
        Ok(Self { ctx, cfg, password })
    }

    async fn on_invoke(
        &mut self,
        path: &str,
        action: &str,
        args: Value,
        who: &Caller,
        out: ReplySink,
    ) -> Result<()> {
        // The probe acts as its gateway user: only that user may make it act
        // (no one else borrows that user's rights through it).
        let me = format!("user:{}", self.cfg.user);
        if who.claims.as_ref().map(|c| c.sub.as_str()) != Some(me.as_str()) {
            return Err(LinkError::new(
                wyrm_core::Status::PermissionDenied,
                format!("only {me} runs this probe (it acts as that gateway user)"),
            ));
        }
        let arg = |k: &str| match &args {
            Value::Map(m) => match m.get(k) {
                Some(Value::Str(s)) if !s.is_empty() => Some(s.clone()),
                _ => None,
            },
            _ => None,
        };
        let site = arg("site");
        let rows = match (path, action) {
            ("", "run_builtin") => {
                let name = arg("name").unwrap_or_default();
                let text = builtin(&name)
                    .ok_or_else(|| LinkError::invalid_parameter(format!("no scenario {name:?}")))?;
                self.run_text(text, site.as_deref()).await?
            }
            ("", "run") => {
                let text = arg("scenario")
                    .ok_or_else(|| LinkError::invalid_parameter("scenario: required"))?;
                self.run_text(&text, site.as_deref()).await?
            }
            _ => return Err(LinkError::not_supported(action.to_owned())),
        };
        out.reply(rows).await
    }
}
