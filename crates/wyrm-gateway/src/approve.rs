//! Approvals of an agent task for a logged-in user (ADR 0049 §2–4).
//!
//! `approve` on `downstream/<agent>/tasks/<id>` takes one human `ptok` per step (ADR 0005).
//! A user of the gateway holds no key, so on `invoke … approve {steps: [n…], plan}` the
//! gateway signs those tokens with the user's rights, as it signs flow deploy proofs
//! (ADR 0008). The rule, in the order it is checked:
//!
//! 0. the session is a person's own (a login with a password): a session of an MCP client
//!    (`/mcp`, ADR 0041) is refused, because approving a plan is a human act; and the key
//!    is `wy/<this site>/downstream/<link>/tasks/<id>` where `<link>` is an agent link by
//!    the broker's registry ([`crate::Gateway::set_agent_links`]), not by what the link
//!    serves: no other link gets a token of the user;
//! 1. the plan is the one the agent link stores: the gateway reads `tasks/<id>/~state` itself
//!    with the user's own token; the client names steps by number and nothing else of a
//!    step comes from the client (`approvals` in the arguments means a caller with its own
//!    keys: the call then goes through as it is);
//! 2. the task was not replaced by a follow-up (`~state.replaced_by`: the answer names the
//!    task that took its place) and is `awaiting_approval`, and the hash of the plan the gateway read (made here
//!    from its steps, not taken from the record) is the hash the client made from the plan
//!    the user saw (`args.plan`); the link checks the hash against its own plan again when
//!    it takes the approval;
//! 3. every named step is a step of that plan that changes something (a `set` or an
//!    `invoke`), named once; the link decides which of the steps that were not named still
//!    run: for the asker of the task or a user with `config` on the link, those that need
//!    no human; for anybody else, none;
//! 4. the user's grants give every named step at least the level it needs; if one does not,
//!    the whole call is refused before anything is sent, the answer names the step and the
//!    right that is missing, and no token is made;
//! 5. one token per named step: subject the user, the single grant exactly the step's request
//!    key, `max` the level the step needs (never the user's whole level), `args` the SHA-256 of
//!    the step's request body, a fresh `jti`, `exp` in [`APPROVAL_TTL`];
//! 6. the link gets `approvals {"<n>": token}` and `plan`; a step that needs a human and was
//!    not named gets no token, and the link skips it and the steps that need it.

use crate::Refusal;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::time::Duration;
use wyrm_core::{Perm, Status, Value};

/// Lifetime of an approval token: the run must send the step within it. Kept short (spec
/// 04: at most 15 min, single use): the agent link takes no approval whose step comes later
/// than the token lives (`links/agent` `tools::MAX_WAIT_BEFORE_APPROVAL_S`), and the rest of
/// a long plan is approved as a follow-up, when its turn comes.
pub const APPROVAL_TTL: Duration = Duration::from_secs(300);
/// Largest document the `doc` op returns, and the largest task record `approve` reads.
pub const MAX_DOC: usize = 1024 * 1024;
/// Steps one `approve` may name (the agent link keeps at most 50 in a plan).
pub const MAX_STEPS: usize = 64;
/// The keys of a step in `~state` that say something about it and are no part of what it
/// does (`links/agent` `tools::UNHASHED`): left out of the plan's hash.
const UNHASHED: [&str; 5] = ["approval", "check", "warn", "reason", "result"];

/// One step of the stored plan, as far as an approval needs it.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Step {
    /// Its number in the plan, from 1.
    pub n: usize,
    /// What a token for it is for; `None`: the step sends nothing (`wait`, `expect`,
    /// `sleep`).
    pub request: Option<Request>,
    /// Does the step need a human (the link's bar of now)?
    pub approval: bool,
}

/// The request of a step that changes something.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Request {
    /// `<node>/~set` or `<node>/~act/<action>`.
    pub key: String,
    pub level: Perm,
    /// SHA-256 of the request body the run will send.
    pub body: [u8; 32],
}

/// The task record, as far as an approval needs it.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Plan {
    pub state: String,
    /// The follow-up task that took this one's place: nothing of this plan is signed.
    pub replaced_by: Option<String>,
    pub hash: String,
    pub steps: Vec<Step>,
}

/// What the client asks for: `args {steps: [<n>, …], plan: <plan hash>}`.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct Ask {
    pub steps: Vec<usize>,
    pub plan: String,
}

fn bad(m: impl Into<String>) -> Refusal {
    Refusal::new(Status::InvalidParameter, m)
}

fn text<'a>(m: &'a BTreeMap<String, Value>, k: &str) -> Option<&'a str> {
    match m.get(k) {
        Some(Value::Str(s)) => Some(s),
        _ => None,
    }
}

/// Is this `approve` the form of a gateway user (`steps`), for the gateway to sign? With
/// `approvals` the caller brings its own tokens and the gateway adds nothing.
pub(crate) fn asks_for_tokens(args: &Value) -> bool {
    matches!(args, Value::Map(m) if m.contains_key("steps") && !m.contains_key("approvals"))
}

/// Rule 0 of the module, before anything is read: `human` is a person's own session,
/// `agent_task` says the key is a task of an agent link of this site.
pub(crate) fn gate(human: bool, agent_task: bool) -> Result<(), Refusal> {
    if !human {
        return Err(Refusal::new(
            Status::PermissionDenied,
            "approving a plan is for a person: approve it in Studio",
        ));
    }
    if !agent_task {
        return Err(Refusal::new(
            Status::PermissionDenied,
            "approvals are signed only for a task of an agent link of this site",
        ));
    }
    Ok(())
}

impl Ask {
    pub fn parse(args: &Value) -> Result<Self, Refusal> {
        let Value::Map(m) = args else {
            return Err(bad("args: {steps, plan} required"));
        };
        if let Some(k) = m.keys().find(|k| !matches!(k.as_str(), "steps" | "plan")) {
            return Err(bad(format!("args.{k}: only steps and plan are taken")));
        }
        let Some(Value::Array(items)) = m.get("steps") else {
            return Err(bad("args.steps: an array of step numbers required"));
        };
        if items.is_empty() {
            return Err(bad(
                "args.steps: no step is approved (reject the plan instead)",
            ));
        }
        if items.len() > MAX_STEPS {
            return Err(bad(format!("args.steps: at most {MAX_STEPS}")));
        }
        let mut steps: Vec<usize> = Vec::with_capacity(items.len());
        for i in items {
            let n = match i {
                Value::UInt(n) => usize::try_from(*n).ok().filter(|n| *n >= 1),
                _ => None,
            }
            .ok_or_else(|| bad("args.steps: step numbers (from 1) required"))?;
            if steps.contains(&n) {
                return Err(bad(format!("args.steps: step {n} is named twice")));
            }
            steps.push(n);
        }
        let plan = text(m, "plan").filter(|h| !h.is_empty()).ok_or_else(|| {
            bad("args.plan: the hash of the plan you read is required (plan_hash)")
        })?;
        Ok(Self {
            steps,
            plan: plan.to_owned(),
        })
    }
}

fn level_of(name: &str) -> Option<Perm> {
    Perm::ALL.iter().copied().find(|p| p.name() == name)
}

/// The hash of a plan (`links/agent` `tools::plan_hash`): SHA-256, in hex, of the canonical
/// CBOR of the plan as `~state.plan` shows it, each step without the keys of [`UNHASHED`].
/// The link, the gateway and the client each make it from the plan they hold; an approval
/// goes through only when all three agree.
pub fn plan_hash(plan: &[Value]) -> Option<String> {
    let steps = plan
        .iter()
        .map(|s| match s {
            Value::Map(m) => Some(Value::Map(
                m.iter()
                    .filter(|(k, _)| !UNHASHED.contains(&k.as_str()))
                    .map(|(k, v)| (k.clone(), v.clone()))
                    .collect(),
            )),
            _ => None,
        })
        .collect::<Option<Vec<_>>>()?;
    let bytes = wyrm_core::codec::to_vec(&Value::Array(steps)).ok()?;
    Some(
        Sha256::digest(&bytes)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect(),
    )
}

impl Request {
    /// The request of a step in the `wyrm-agent run` format: `{set: <node>, value}` or
    /// `{invoke: <node>, action, args}`. The node must be a plain node key of `site` (no
    /// wildcard, no `~` segment): the request key becomes a token's grant. `Ok(None)`: a
    /// step that sends nothing.
    fn of(s: &BTreeMap<String, Value>, site: &str) -> Result<Option<Self>, &'static str> {
        let (node, suffix, body) = if let Some(node) = text(s, "set") {
            let v = s.get("value").cloned().unwrap_or(Value::Null);
            (node, "~set".to_owned(), wyrm_client::set_payload(v))
        } else if let Some(node) = text(s, "invoke") {
            let action = text(s, "action").ok_or("no action")?;
            wyrm_core::keyspace::validate_segment(action).map_err(|_| "a bad action name")?;
            let args = s.get("args").cloned().unwrap_or(Value::Null);
            (
                node,
                format!("~act/{action}"),
                wyrm_client::invoke_payload(&args),
            )
        } else if ["wait", "expect", "sleep_s"]
            .iter()
            .any(|k| s.contains_key(*k))
        {
            return Ok(None);
        } else {
            return Err("not one of set, invoke, wait, expect, sleep_s");
        };
        if crate::ws::check_key(site, node, false).is_err() {
            return Err("its key is not a node of this site");
        }
        let level = text(s, "level")
            .and_then(level_of)
            .filter(|p| *p >= Perm::Write)
            .ok_or("no level of write or config")?;
        let body = body.map_err(|_| "its arguments do not encode")?;
        Ok(Some(Self {
            key: format!("{node}/{suffix}"),
            level,
            body: Sha256::digest(&body).into(),
        }))
    }
}

impl Plan {
    /// Read a task's `~state` document (`links/agent`). `site` is the site of the task: every
    /// step that changes something must be a request on a node of it.
    pub fn parse(doc: &Value, site: &str) -> Result<Self, Refusal> {
        let old = || {
            Refusal::new(
                Status::NotSupported,
                "this node is not a task of an agent link that takes approvals from the gateway",
            )
        };
        let Value::Map(m) = doc else {
            return Err(old());
        };
        let state = text(m, "state").ok_or_else(old)?.to_owned();
        // absent on an agent link older than ADR 0049: it knows no step numbers
        let claimed = text(m, "plan_hash").ok_or_else(old)?;
        let Some(Value::Array(items)) = m.get("plan") else {
            return Err(old());
        };
        let mut steps: Vec<Step> = Vec::with_capacity(items.len());
        for (i, s) in items.iter().enumerate() {
            let n = i + 1;
            let broken =
                |what: &str| Refusal::new(Status::InternalError, format!("plan step {n}: {what}"));
            let Value::Map(s) = s else {
                return Err(broken("not a map"));
            };
            if s.get("n") != Some(&Value::UInt(n as u64)) {
                return Err(broken("its number is not its place"));
            }
            let request = Request::of(s, site).map_err(broken)?;
            steps.push(Step {
                n,
                approval: request.is_some() && matches!(s.get("approval"), Some(Value::Bool(true))),
                request,
            });
        }
        // The hash is made here from the plan as read, never taken from the record: the
        // approval is for these very requests, whatever the link says its hash is.
        let hash = plan_hash(items)
            .ok_or_else(|| Refusal::new(Status::InternalError, "the plan does not encode"))?;
        if hash != claimed {
            return Err(Refusal::new(
                Status::InternalError,
                "the task's plan_hash is not the hash of its plan",
            ));
        }
        Ok(Self {
            state,
            replaced_by: text(m, "replaced_by").map(str::to_owned),
            hash,
            steps,
        })
    }

    /// Rules 2–4 of the module: the steps to sign, each with its request. `may(key)` is the
    /// user's level on a request key.
    pub fn select(
        &self,
        ask: &Ask,
        may: impl Fn(&str) -> Perm,
    ) -> Result<Vec<(usize, &Request)>, Refusal> {
        if let Some(by) = &self.replaced_by {
            return Err(bad(format!(
                "task was replaced by {by}: its plan is no longer approved; approve that task"
            )));
        }
        if self.state != "awaiting_approval" {
            return Err(bad(format!(
                "task is {}, not awaiting_approval",
                self.state
            )));
        }
        if self.hash != ask.plan {
            return Err(bad(
                "plan: the plan is not the one this approval was made for; read it again",
            ));
        }
        let mut sign = Vec::with_capacity(ask.steps.len());
        for n in &ask.steps {
            match self.steps.get(n - 1) {
                // A step that needs no human may be named too: a user who does not manage
                // the task (not its asker, no `config` on the link) decides only for the
                // steps they sign, and the link runs no other step on their word.
                Some(Step {
                    request: Some(r), ..
                }) => sign.push((*n, r)),
                Some(_) => {
                    return Err(bad(format!("step {n} sends nothing: it takes no approval")))
                }
                None => return Err(bad(format!("the plan has no step {n}"))),
            }
        }
        let denied: Vec<String> = sign
            .iter()
            .filter_map(|(n, r)| {
                let have = may(&r.key);
                (have < r.level).then(|| {
                    format!(
                        "step {n} needs {} on {}; you have {}",
                        r.level.name(),
                        r.key,
                        have.name()
                    )
                })
            })
            .collect();
        if !denied.is_empty() {
            return Err(Refusal::new(Status::PermissionDenied, denied.join("; ")));
        }
        Ok(sign)
    }

    /// The steps that need a human and are not in `named`.
    pub fn left_out(&self, named: &[usize]) -> usize {
        self.steps
            .iter()
            .filter(|s| s.approval && !named.contains(&s.n))
            .count()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map<const N: usize>(f: [(&str, Value); N]) -> Value {
        Value::Map(f.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
    }

    fn with(mut v: Value, k: &str, x: Value) -> Value {
        if let Value::Map(m) = &mut v {
            m.insert(k.to_owned(), x);
        }
        v
    }

    fn set(n: u64, node: &str, level: &str, approval: bool) -> Value {
        map([
            ("n", Value::UInt(n)),
            ("set", Value::from(node)),
            ("value", Value::Float(1.0)),
            ("level", Value::from(level)),
            ("approval", Value::Bool(approval)),
            ("check", Value::from("now")),
        ])
    }

    fn invoke(n: u64, node: &str, action: &str, level: &str) -> Value {
        map([
            ("n", Value::UInt(n)),
            ("invoke", Value::from(node)),
            ("action", Value::from(action)),
            ("args", Value::Float(1.0)),
            ("level", Value::from(level)),
            ("approval", Value::Bool(true)),
        ])
    }

    /// A record whose `plan_hash` is the hash of its steps, as an honest link writes it.
    fn record(state: &str, steps: Vec<Value>) -> Value {
        map([
            ("state", Value::from(state)),
            ("plan_hash", Value::from(plan_hash(&steps).unwrap())),
            ("plan", Value::Array(steps)),
        ])
    }

    const A: &str = "wy/s/downstream/m/a";
    const B: &str = "wy/s/downstream/m/b";
    const C: &str = "wy/s/downstream/m/c";

    fn plan() -> Plan {
        let mut p = Plan::parse(
            &record(
                "awaiting_approval",
                vec![
                    set(1, A, "write", true),
                    invoke(2, B, "go", "config"),
                    set(3, C, "write", false),
                    map([
                        ("n", Value::UInt(4)),
                        ("expect", Value::from(A)),
                        ("equals", Value::Float(1.0)),
                        ("level", Value::from("read")),
                        // a link that says a proof needs a human is not believed
                        ("approval", Value::Bool(true)),
                    ]),
                    // two steps on one key are two steps
                    set(5, A, "write", true),
                ],
            ),
            "s",
        )
        .unwrap();
        p.hash = "h1".into();
        p
    }

    fn ask(steps: &[usize], plan: &str) -> Ask {
        Ask {
            steps: steps.to_vec(),
            plan: plan.to_owned(),
        }
    }

    /// Approving is a human act on a task of an agent link: a session of an MCP client gets
    /// no token even where its user's grants reach every step (review of ADR 0049: the
    /// connector's `allow_config` switch looks at the level of `approve`, not of the steps).
    #[test]
    fn only_a_person_approves_and_only_a_task_of_an_agent_link() {
        assert!(gate(true, true).is_ok());
        for (human, task, want) in [
            (false, true, "for a person"),
            (true, false, "agent link"),
            (false, false, "for a person"),
        ] {
            let e = gate(human, task).unwrap_err();
            assert_eq!(e.status, Status::PermissionDenied);
            assert!(e.message.contains(want), "{}", e.message);
        }
    }

    #[test]
    fn the_client_names_steps_and_nothing_else() {
        let steps = |s: Vec<Value>| ("steps", Value::Array(s));
        let h = ("plan", Value::from("h1"));
        let ok = map([steps(vec![Value::UInt(2), Value::UInt(1)]), h.clone()]);
        assert!(asks_for_tokens(&ok));
        assert_eq!(Ask::parse(&ok).unwrap(), ask(&[2, 1], "h1"));
        for bad in [
            Value::Null,
            map([steps(vec![Value::UInt(1)])]),
            map([steps(Vec::new()), h.clone()]),
            map([steps(vec![Value::UInt(1), Value::UInt(1)]), h.clone()]),
            map([steps(vec![Value::UInt(0)]), h.clone()]),
            map([
                steps(vec![Value::from("wy/s/downstream/m/a/~set")]),
                h.clone(),
            ]),
            map([
                steps(vec![Value::UInt(1)]),
                h.clone(),
                ("skip", Value::Null),
            ]),
        ] {
            let e = Ask::parse(&bad).unwrap_err();
            assert_eq!(e.status, Status::InvalidParameter, "{bad:?}");
        }
        // a caller with its own tokens: the gateway adds nothing and takes nothing away
        let own = map([
            steps(vec![Value::UInt(1)]),
            ("approvals", map([("1", Value::Bytes(vec![1]))])),
        ]);
        assert!(!asks_for_tokens(&own));
        assert!(!asks_for_tokens(&map([(
            "approvals",
            Value::Map(BTreeMap::new())
        )])));
    }

    #[test]
    fn a_stored_step_is_a_request_on_a_node_of_the_site() {
        let p = plan();
        assert_eq!(p.steps.len(), 5);
        let r = |i: usize| p.steps[i].request.as_ref().unwrap();
        assert_eq!(r(0).key, format!("{A}/~set"));
        assert_eq!(
            (r(1).key.as_str(), r(1).level, p.steps[1].approval),
            ("wy/s/downstream/m/b/~act/go", Perm::Config, true)
        );
        // the body is what the run sends: a `~set` wraps its value, an action does not
        assert_ne!(r(0).body, r(1).body);
        assert_eq!(r(0).body, r(2).body);
        assert_eq!((&p.steps[3].request, p.steps[3].approval), (&None, false));
        for step in [
            set(1, "wy/other/downstream/m/a", "write", true),
            set(1, "wy/s/downstream/*/a", "write", true),
            set(1, "wy/s/downstream/**", "write", true),
            set(1, "wy/s/downstream/m/a/~set", "write", true),
            invoke(1, "wy/s/downstream/m/~act/x", "go", "write"),
            invoke(1, A, "*", "write"),
            invoke(1, A, "a/b", "write"),
            set(1, A, "read", true),
            set(1, A, "admin", true),
            set(2, A, "write", true),
            map([("n", Value::UInt(1)), ("deploy", Value::from(A))]),
        ] {
            let doc = record("awaiting_approval", vec![step.clone()]);
            let e = Plan::parse(&doc, "s").unwrap_err();
            assert_eq!(e.status, Status::InternalError, "{step:?}");
        }
        // not a task of a link that knows step numbers and `plan`
        let old = map([
            ("state", Value::from("awaiting_approval")),
            ("plan", Value::Array(Vec::new())),
        ]);
        assert_eq!(
            Plan::parse(&old, "s").unwrap_err().status,
            Status::NotSupported
        );
        assert_eq!(
            Plan::parse(&Value::Null, "s").unwrap_err().status,
            Status::NotSupported
        );
    }

    /// The link's word is not taken for the hash: a record that shows one plan under the
    /// hash of another is refused.
    #[test]
    fn the_hash_is_made_from_the_plan_as_read() {
        let honest = record("awaiting_approval", vec![set(1, A, "write", true)]);
        let p = Plan::parse(&honest, "s").unwrap();
        // the same vector as links/agent (tools tests) and dart/wyrm_client
        let vector = [map([
            ("n", Value::UInt(1)),
            ("set", Value::from("wy/s/downstream/m/p")),
            ("value", Value::Float(1.0)),
            ("level", Value::from("write")),
        ])];
        assert_eq!(
            plan_hash(&vector).unwrap(),
            "08900496afc130ee83048251cb224b679cbfd06491270fa67d386c7dcc6cd60d"
        );
        // other arguments under the old hash
        let Value::Map(mut m) = honest else {
            unreachable!()
        };
        let other = with(set(1, A, "write", true), "value", Value::Float(9999.0));
        m.insert("plan".into(), Value::Array(vec![other]));
        let e = Plan::parse(&Value::Map(m), "s").unwrap_err();
        assert_eq!(e.status, Status::InternalError);
        assert!(e.message.contains("plan_hash"), "{}", e.message);
        // the model's words, the checks and the run's results are not part of it; the
        // dependencies are
        let mut reworded = set(1, A, "write", false);
        for (k, v) in [
            ("reason", Value::from("because")),
            ("warn", Value::from("at the limit")),
            ("check", Value::from("at_run")),
            ("result", map([("status", Value::from("ok"))])),
        ] {
            reworded = with(reworded, k, v);
        }
        let q = Plan::parse(&record("done", vec![reworded.clone()]), "s").unwrap();
        assert_eq!(q.hash, p.hash);
        let after = with(reworded, "after", Value::Array(vec![Value::UInt(1)]));
        let q = Plan::parse(&record("done", vec![after]), "s").unwrap();
        assert_ne!(q.hash, p.hash);
    }

    #[test]
    fn only_ticked_steps_within_the_users_rights_are_signed() {
        let p = plan();
        let config = |_: &str| Perm::Config;
        let write = |_: &str| Perm::Write;
        let numbers = |s: &[(usize, &Request)]| s.iter().map(|(n, _)| *n).collect::<Vec<_>>();

        let sign = p.select(&ask(&[1, 2, 5], "h1"), config).unwrap();
        assert_eq!(numbers(&sign), [1, 2, 5]);
        // a step the agent would run itself may be signed too (a user who is not the asker)
        let sign = p.select(&ask(&[3], "h1"), write).unwrap();
        assert_eq!(numbers(&sign), [3]);
        assert_eq!(p.left_out(&[1, 2, 5]), 0);
        // steps left out get no token; the one that needs no human is not one of them
        let sign = p.select(&ask(&[1], "h1"), write).unwrap();
        assert_eq!(numbers(&sign), [1]);
        assert_eq!(p.left_out(&[1]), 2);

        // a `config` step for a user with `write`: refused whole, the step and the right named
        let e = p.select(&ask(&[1, 2], "h1"), write).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert_eq!(
            e.message,
            "step 2 needs config on wy/s/downstream/m/b/~act/go; you have write"
        );
        // a step outside the user's grants
        let only_b = |k: &str| {
            if k.starts_with(B) {
                Perm::Config
            } else {
                Perm::Read
            }
        };
        let e = p.select(&ask(&[1, 2], "h1"), only_b).unwrap_err();
        assert_eq!(e.status, Status::PermissionDenied);
        assert!(e.message.starts_with("step 1 needs write"), "{}", e.message);

        // an unknown step, steps that need no human, a changed plan, a task not waiting
        for (a, want) in [
            (ask(&[9], "h1"), "no step 9"),
            (ask(&[4], "h1"), "sends nothing"),
            (ask(&[1], "h2"), "read it again"),
        ] {
            let e = p.select(&a, config).unwrap_err();
            assert_eq!(e.status, Status::InvalidParameter);
            assert!(e.message.contains(want), "{}", e.message);
        }
        let mut done = p.clone();
        done.state = "running".into();
        let e = done.select(&ask(&[1], "h1"), config).unwrap_err();
        assert_eq!(e.status, Status::InvalidParameter);
        // a plan a follow-up replaced: nothing of it is signed, and the answer names the
        // task to approve, even if the record still said it waits
        let Value::Map(mut rec) = record("awaiting_approval", vec![set(1, A, "write", true)])
        else {
            unreachable!()
        };
        rec.insert("replaced_by".into(), Value::from("t2-2"));
        let replaced = Plan::parse(&Value::Map(rec), "s").unwrap();
        let e = replaced
            .select(&ask(&[1], &replaced.hash), config)
            .unwrap_err();
        assert_eq!(e.status, Status::InvalidParameter);
        assert!(e.message.contains("replaced by t2-2"), "{}", e.message);
    }
}
