//! Node and action meta of a messenger link's tree (ADR 0039), paths relative to the link root;
//! what a platform cannot do (users, command buttons, blocks) is not declared:
//!
//! ```text
//! ""                      add_bot (config)
//! stats/…                 bots, sent, failed, rejected
//! <bot>                   attr kind
//!   status                no_token | checking | ready | waiting | failed | disabled
//!   error, username, sent, failed, dropped, queued, rejected, last_sent
//!   enabled               writable at config
//!   send (write); send_raw, add_recipient, add_template, invite_user (inbound platforms),
//!   set_token, test_connection, edit, remove (config)
//!   recipients/<r>        attrs chat, thread, commands; send (write); edit, remove (config)
//!   templates/<t>         attrs kind, format, to, values; send, preview (write); edit, remove (config)
//!   users/<u>             status, level, select, chat_id, paired, last_seen, commands;
//!                         new_code, enable, disable, edit, remove (config)
//! ```

use wyrm_core::meta::{
    ActionResult, ParamMeta, Writable, EDITOR_PASSWORD, EDITOR_TEXTAREA, GROUP_EDIT, GROUP_NEW,
};
use wyrm_core::{ActionMeta, NodeMeta, Perm, TypeCode, Value};

use crate::model::{Format, Kind, MsgKind, Recipient, Template, User};

pub const STATS: &str = "stats";
pub const STAT_NAMES: [&str; 4] = ["bots", "sent", "failed", "rejected"];

pub const BOT_LEAVES: [(&str, TypeCode, &str); 9] = [
    ("status", TypeCode::Enum, "no_token (Set token), checking, ready, waiting (after an error), failed (see error), disabled"),
    ("error", TypeCode::String, "The last error."),
    ("username", TypeCode::String, "The bot's own name on the platform."),
    ("sent", TypeCode::Number, "Messages delivered since the link started."),
    ("failed", TypeCode::Number, "Messages the platform refused."),
    ("dropped", TypeCode::Number, "Messages the full queue let go."),
    ("queued", TypeCode::Number, "Messages waiting to be sent."),
    ("rejected", TypeCode::Number, "Updates from chats or accounts that are not allowed."),
    ("last_sent", TypeCode::String, "UTC time of the last delivered message."),
];

pub const USER_LEAVES: [(&str, TypeCode, &str); 7] = [
    (
        "status",
        TypeCode::Enum,
        "pending (waits for /start <code>), active, disabled",
    ),
    (
        "level",
        TypeCode::String,
        "read: /get; write: /get, /set, /do.",
    ),
    ("select", TypeCode::String, "Keys its commands may name."),
    (
        "chat_id",
        TypeCode::String,
        "The paired chat account (its numeric id).",
    ),
    ("paired", TypeCode::String, "UTC time of pairing."),
    (
        "last_seen",
        TypeCode::String,
        "UTC time of the last command.",
    ),
    (
        "commands",
        TypeCode::Number,
        "Commands since the link started.",
    ),
];

pub fn stat(n: &str) -> String {
    format!("{STATS}/{n}")
}

pub fn leaf(path: &str, l: &str) -> String {
    format!("{path}/{l}")
}

pub fn recipient_path(bot: &str, r: &str) -> String {
    format!("{bot}/recipients/{r}")
}

pub fn template_path(bot: &str, t: &str) -> String {
    format!("{bot}/templates/{t}")
}

pub fn user_path(bot: &str, u: &str) -> String {
    format!("{bot}/users/{u}")
}

fn text(display: &str, about: &str) -> ParamMeta {
    ParamMeta::of(TypeCode::String)
        .display(display)
        .description(about)
}

fn number(display: &str, about: &str) -> ParamMeta {
    ParamMeta::of(TypeCode::Number)
        .display(display)
        .description(about)
}

fn flag(display: &str, about: &str) -> ParamMeta {
    ParamMeta::of(TypeCode::Bool)
        .display(display)
        .description(about)
}

fn choice(display: &str, values: &[&str], about: &str) -> ParamMeta {
    ParamMeta::of(TypeCode::Enum)
        .display(display)
        .enum_values(values.iter().copied())
        .description(about)
}

fn formats(kind: Kind) -> Vec<&'static str> {
    kind.format_names()
}

fn bot_form(kind: Kind, add: bool) -> ActionMeta {
    let mut a = ActionMeta::new().level(Perm::Config);
    if add {
        a = a.param(
            "name",
            text("Name", "The bot's node name (a-z, 0-9, _ and -).").required(true),
        );
    }
    a = a
        .param("enabled", flag("Enabled", "Send and read updates."))
        .param(
            "api_url",
            text("API URL", "Default https://api.telegram.org or https://slack.com; a local Bot API server works too.")
                .placeholder(kind.default_api()),
        )
        .param(
            "ca_pem",
            text("CA (PEM)", "Trust only this CA for the API (else the system roots).")
                .editor(EDITOR_TEXTAREA),
        )
        .param("timeout_ms", number("Timeout (ms)", "Per request, 500…8000 (3000)."))
        .param(
            "format",
            choice("Default format", &formats(kind), "Markup of messages that name none."),
        )
        .param("queue_max", number("Queue", "Messages kept while the platform is slow (500)."));
    if kind.inbound {
        a = a
            .param(
                "commands",
                flag(
                    "Commands",
                    "Read updates and answer paired users (/get, /set, /do).",
                ),
            )
            .param(
                "poll_s",
                number("Poll (s)", "How often updates are read, 1…300 (3)."),
            )
            .param(
                "leave_unknown",
                flag(
                    "Leave unknown chats",
                    "Leave groups the bot was added to that are no recipient.",
                ),
            )
            .param(
                "rate_per_min",
                number("Commands per minute", "Per user (20)."),
            );
    }
    a
}

pub fn add_bot(kind: Kind) -> (String, ActionMeta) {
    (
        "add_bot".to_owned(),
        bot_form(kind, true)
            .display(wyrm_core::display::sentence(&format!(
                "Add {} bot",
                kind.display()
            )))
            .group(GROUP_NEW),
    )
}

fn recipient_form(kind: Kind, add: bool) -> ActionMeta {
    let mut a = ActionMeta::new().level(Perm::Config);
    if add {
        a = a.param(
            "name",
            text("Name", "The recipient's node name.").required(true),
        );
    }
    let chat_about = kind.chat_about;
    let thread_about = kind.thread_about;
    a = a
        .param("chat", text("Chat", chat_about).required(add))
        .param("thread", text("Thread", thread_about))
        .param("silent", flag("Silent", "Deliver without a sound."));
    if kind.inbound {
        a = a.param(
            "commands",
            flag(
                "Commands here",
                "Paired users may give commands in this group.",
            ),
        );
    }
    a
}

fn template_form(kind: Kind, add: bool) -> ActionMeta {
    let mut a = ActionMeta::new().level(Perm::Config);
    if add {
        a = a.param(
            "name",
            text("Name", "The template's node name.").required(true),
        );
    }
    let kinds: Vec<&str> = MsgKind::ALL.iter().map(|k| k.name()).collect();
    a = a
        .param("kind", choice("Kind", &kinds, "text, photo, document or location."))
        .param("format", choice("Format", &formats(kind), "Markup of the text."))
        .param(
            "text",
            text(
                "Text",
                "{{name}} from the send, {{alias}} of a value ({{alias:.1}}, {{alias.q}}, {{alias.t}}), {{site}}, {{bot}}, {{now}}; values are escaped for the format.",
            )
            .editor(EDITOR_TEXTAREA),
        )
        .param("media", text("Media", "Photo or document: an https:// URL (or the platform's file id)."))
        .param("lat", text("Latitude", "Location: a number or a placeholder."))
        .param("lon", text("Longitude", "Location: a number or a placeholder."))
        .param(
            "buttons",
            text(
                "Buttons",
                "One row per line, buttons split by ;; — Label | https://… (Label | /command where the platform takes commands)",
            )
            .editor(EDITOR_TEXTAREA),
        )
        .param(
            "values",
            text("Values", "One per line: alias = wy/<site>/… (live values the text may name).")
                .editor(EDITOR_TEXTAREA),
        )
        .param("to", text("To", "Recipients when a send names none, comma separated."))
        .param("silent", flag("Silent", "Deliver without a sound."))
        .param("protect", flag("Protect", "No forwarding or saving, where the platform offers it."))
        .param("preview", flag("Link preview", "Show link previews."));
    if kind.blocks {
        a = a.param(
            "blocks",
            text(
                "Blocks",
                "Block Kit JSON (an array); placeholders inside JSON strings.",
            )
            .editor(EDITOR_TEXTAREA),
        );
    }
    a
}

fn user_form(add: bool) -> ActionMeta {
    let mut a = ActionMeta::new().level(Perm::Config);
    if add {
        a = a.param(
            "name",
            text("Name", "The user's node name (who it is).").required(true),
        );
    }
    a.param(
        "level",
        choice(
            "Level",
            &crate::model::LEVELS,
            "read: /get; write: also /set and /do.",
        ),
    )
    .param(
        "select",
        text(
            "Keys",
            "Full keys its commands may name, one per line (wy/<site>/downstream)",
        )
        .editor(EDITOR_TEXTAREA),
    )
}

fn ad_hoc_send(kind: Kind) -> ActionMeta {
    let kinds: Vec<&str> = MsgKind::ALL.iter().map(|k| k.name()).collect();
    ActionMeta::new()
        .display("Send message")
        .level(Perm::Write)
        .param(
            "to",
            text("To", "Recipient names, comma separated.").required(true),
        )
        .param(
            "text",
            text(
                "Text",
                "The message; {{site}}, {{bot}}, {{now}} are filled in.",
            )
            .editor(EDITOR_TEXTAREA),
        )
        .param(
            "kind",
            choice("Kind", &kinds, "text (default), photo, document, location."),
        )
        .param(
            "format",
            choice("Format", &formats(kind), "The bot's default when empty."),
        )
        .param("media", text("Media", "Photo or document URL."))
        .param("lat", text("Latitude", ""))
        .param("lon", text("Longitude", ""))
        .param("silent", flag("Silent", ""))
        .result(ActionResult::Type(TypeCode::Map))
}

pub fn bot_actions(kind: Kind) -> Vec<(&'static str, ActionMeta)> {
    let mut out = vec![
        ("send", ad_hoc_send(kind)),
        (
            "forget_update",
            ActionMeta::new()
                .display("Forget updated message")
                .level(Perm::Write)
                .param(
                    "update",
                    text(
                        "Update",
                        "The name a template's send kept a message up to date with: its next send posts a new message.",
                    )
                    .required(true),
                ),
        ),
        (
            "send_raw",
            ActionMeta::new()
                .display("Send raw request")
                .level(Perm::Config)
                .param("method", text("Method", kind.raw_about).required(true))
                .param(
                    "params",
                    text("Parameters", "JSON object; the chat must be a recipient's.")
                        .editor(EDITOR_TEXTAREA),
                )
                .result(ActionResult::Type(TypeCode::Map)),
        ),
        (
            "add_recipient",
            recipient_form(kind, true)
                .display("Add recipient")
                .group(GROUP_NEW),
        ),
        (
            "add_template",
            template_form(kind, true)
                .display("Add template")
                .group(GROUP_NEW),
        ),
        (
            "set_token",
            ActionMeta::new()
                .display("Set token")
                .group(GROUP_EDIT)
                .level(Perm::Config)
                .param(
                    "token",
                    ParamMeta::of(TypeCode::String)
                        .display("Token")
                        .editor(EDITOR_PASSWORD)
                        .description(kind.secret_about()),
                ),
        ),
        (
            "test_connection",
            ActionMeta::new()
                .display("Test connection")
                .level(Perm::Config)
                .result(ActionResult::Type(TypeCode::Map)),
        ),
        (
            "edit",
            bot_form(kind, false).display("Edit").group(GROUP_EDIT),
        ),
        (
            "remove",
            ActionMeta::new()
                .display("Remove")
                .group(GROUP_EDIT)
                .level(Perm::Config),
        ),
    ];
    if kind.inbound {
        out.push((
            "invite_user",
            user_form(true)
                .display("Invite user")
                .group(GROUP_NEW)
                .result(ActionResult::Type(TypeCode::Map)),
        ));
    }
    out
}

pub fn bot_node(kind: Kind) -> NodeMeta {
    NodeMeta::folder()
        .display(format!("{} Bot", kind.display()))
        .attr("kind", kind.name())
}

pub fn bot_status() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Enum)
        .enum_values([
            "no_token", "checking", "ready", "waiting", "failed", "disabled",
        ])
        .attr("description", BOT_LEAVES[0].2)
}

pub fn enabled_node() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Bool).writable(Writable::Config)
}

pub fn recipient_node(r: &Recipient) -> NodeMeta {
    let mut n = NodeMeta::folder()
        .attr("chat", r.chat.as_str())
        .attr("commands", r.commands)
        .attr("silent", r.silent);
    if let Some(t) = &r.thread {
        n = n.attr("thread", t.as_str());
    }
    n
}

pub fn recipient_actions(kind: Kind) -> Vec<(&'static str, ActionMeta)> {
    vec![
        (
            "send",
            ActionMeta::new()
                .display("Send message")
                .level(Perm::Write)
                .param(
                    "text",
                    text("Text", "The message.")
                        .required(true)
                        .editor(EDITOR_TEXTAREA),
                )
                .param(
                    "format",
                    choice("Format", &formats(kind), "The bot's default when empty."),
                )
                .param("silent", flag("Silent", ""))
                .result(ActionResult::Type(TypeCode::Map)),
        ),
        (
            "edit",
            recipient_form(kind, false)
                .display("Edit")
                .group(GROUP_EDIT),
        ),
        (
            "remove",
            ActionMeta::new()
                .display("Remove")
                .group(GROUP_EDIT)
                .level(Perm::Config),
        ),
    ]
}

pub fn template_node(t: &Template) -> NodeMeta {
    let values: Vec<Value> = t
        .values
        .iter()
        .map(|(a, k)| Value::Str(format!("{a} = {k}")))
        .collect();
    NodeMeta::folder()
        .attr("kind", t.kind.name())
        .attr("format", t.format.name())
        .attr(
            "to",
            Value::Array(t.to.iter().cloned().map(Value::Str).collect()),
        )
        .attr("values", Value::Array(values))
}

/// Send and Preview of a template take its variables as parameters of their own.
pub fn template_actions(kind: Kind, vars: &[String]) -> Vec<(&'static str, ActionMeta)> {
    let with_vars = |mut a: ActionMeta| {
        for v in vars {
            a = a.param(
                v.as_str(),
                ParamMeta::of(TypeCode::Dynamic)
                    .display(wyrm_core::display::humanize(v))
                    .description(format!("Template variable {{{{{v}}}}}")),
            );
        }
        a
    };
    vec![
        (
            "send",
            with_vars(
                ActionMeta::new()
                    .display("Send")
                    .level(Perm::Write)
                    .param(
                        "to",
                        text("To", "Recipient names; the template's when empty."),
                    )
                    .param(
                        "update",
                        text(
                            "Update",
                            "A name for one message kept up to date: the first send with it posts the message, later ones edit it in place at each recipient (text, captions, Block Kit). Empty: a new message each time.",
                        ),
                    ),
            )
            .result(ActionResult::Type(TypeCode::Map)),
        ),
        (
            "preview",
            with_vars(ActionMeta::new().display("Preview").level(Perm::Write))
                .result(ActionResult::Type(TypeCode::Map)),
        ),
        (
            "edit",
            template_form(kind, false).display("Edit").group(GROUP_EDIT),
        ),
        (
            "remove",
            ActionMeta::new()
                .display("Remove")
                .group(GROUP_EDIT)
                .level(Perm::Config),
        ),
    ]
}

pub fn user_node(u: &User) -> NodeMeta {
    NodeMeta::folder().attr("level", u.level.name())
}

pub fn user_status() -> NodeMeta {
    NodeMeta::leaf(TypeCode::Enum)
        .enum_values(["pending", "active", "disabled"])
        .attr("description", USER_LEAVES[0].2)
}

pub fn user_actions() -> Vec<(&'static str, ActionMeta)> {
    let plain = |d: &str| ActionMeta::new().display(d).level(Perm::Config);
    vec![
        (
            "new_code",
            plain("New pairing code")
                .group(GROUP_EDIT)
                .result(ActionResult::Type(TypeCode::Map)),
        ),
        ("enable", plain("Enable").group(GROUP_EDIT)),
        ("disable", plain("Disable").group(GROUP_EDIT)),
        ("edit", user_form(false).display("Edit").group(GROUP_EDIT)),
        ("remove", plain("Remove").group(GROUP_EDIT)),
    ]
}

pub fn format_names(kind: Kind) -> String {
    kind.formats()
        .iter()
        .map(|f: &Format| f.name())
        .collect::<Vec<_>>()
        .join(", ")
}
