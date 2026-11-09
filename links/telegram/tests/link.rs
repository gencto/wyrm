//! The Telegram link against a fake Bot API on loopback: templates and their escaping,
//! recipients, pairing and chat commands within three bounds, rate limits and markup fallbacks,
//! restarts.

use wyrm_link_telegram::TelegramLink;
use wyrm_messenger::testkit::{engineer, map, narrow, s, Api, TG_TOKEN};

type SimHost = wyrm_messenger::testkit::SimHost<TelegramLink>;
use serde_json::json;
use wyrm_core::{Status, Value};
use wyrm_link_api::Who;

/// A started host with a ready Telegram bot `ops` and a group recipient `team`.
fn telegram(api: &Api) -> SimHost {
    let mut h = SimHost::new(api.port);
    h.start();
    h.invoke(
        "",
        "add_bot",
        map(&[
            ("name", s("ops")),
            ("api_url", s(&api.url())),
            ("poll_s", Value::UInt(1)),
        ]),
    )
    .expect("add");
    assert_eq!(h.text("ops/status"), "no_token");
    h.invoke("ops", "set_token", map(&[("token", s(TG_TOKEN))]))
        .expect("token");
    h.until("ready", |h| h.text("ops/status") == "ready");
    assert_eq!(h.text("ops/username"), "plant_bot");
    h.invoke(
        "ops",
        "add_recipient",
        map(&[
            ("name", s("team")),
            ("chat", s("-1001234567890")),
            ("thread", s("7")),
        ]),
    )
    .expect("recipient");
    h
}

fn code_of(v: &Value) -> String {
    let Value::Map(m) = v else { panic!("{v:?}") };
    match m.get("code") {
        Some(Value::Str(c)) => c.clone(),
        _ => panic!("no code in {v:?}"),
    }
}

#[test]
fn a_template_fills_values_and_escapes_them() {
    let api = Api::start();
    let mut h = telegram(&api);
    h.invoke(
        "ops",
        "add_template",
        map(&[
            ("name", s("high_temp")),
            (
                "text",
                s("<b>{{who}}</b> on {{site}}: {{temp:.1}} °C ({{temp.q}}), limit {{limit}}"),
            ),
            (
                "values",
                s("temp = wy/s/downstream/mock/d1/temp\nwho = wy/s/downstream/mock/d1/name"),
            ),
            (
                "buttons",
                s("Trend | https://grafana.example/d/x ;; Ack | /do downstream/mock/d1 ack"),
            ),
            ("to", s("team")),
            ("silent", Value::Bool(true)),
        ]),
    )
    .expect("template");
    // the Send form takes the template's own variables
    let send = h.actions["ops/templates/high_temp"]
        .iter()
        .find(|(n, _)| n == "send")
        .map(|(_, a)| a.clone())
        .unwrap();
    assert!(send.params.iter().any(|(n, _)| n == "limit"));
    assert!(!send.params.iter().any(|(n, _)| n == "temp"));
    let r = h
        .invoke(
            "ops/templates/high_temp",
            "send",
            map(&[("limit", Value::UInt(80))]),
        )
        .expect("send");
    assert_eq!(
        r,
        map(&[
            ("queued", Value::UInt(1)),
            ("to", Value::Array(vec![s("team")]))
        ])
    );
    h.until("sent", |h| h.num("ops/sent") == 1);
    let m = &api.calls("sendMessage")[0].body;
    assert_eq!(m["chat_id"], json!(-1001234567890i64));
    assert_eq!(m["message_thread_id"], 7);
    assert_eq!(m["parse_mode"], "HTML");
    assert_eq!(m["disable_notification"], true);
    // the value's own markup is escaped; the template's is kept
    assert_eq!(
        m["text"],
        "<b>&lt;Boiler &amp; Co&gt;</b> on s: 21.5 °C (good), limit 80"
    );
    assert_eq!(
        m["reply_markup"]["inline_keyboard"][0][1]["callback_data"],
        "/do downstream/mock/d1 ack"
    );
    // a live change is used by the next send
    h.put_value("wy/s/downstream/mock/d1/temp", Value::Float(99.0));
    let p = h
        .invoke(
            "ops/templates/high_temp",
            "preview",
            map(&[("limit", Value::UInt(80))]),
        )
        .expect("preview");
    let Value::Map(p) = p else { panic!() };
    assert!(matches!(p.get("body"), Some(Value::Str(b)) if b.contains("99.0 °C")));
    assert_eq!(p.get("method"), Some(&s("sendMessage")));
    assert_eq!(h.num("stats/sent"), 1);
}

#[test]
fn a_template_keeps_its_authors_rights() {
    let api = Api::start();
    let mut h = telegram(&api);
    // values outside the author's rights are refused at Add
    let e = h
        .invoke_as(
            "ops",
            "add_template",
            map(&[
                ("name", s("x")),
                ("text", s("{{v}}")),
                ("values", s("v = wy/s/downstream/other/x")),
            ]),
            &narrow(),
        )
        .unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied);
    // a token without auth cannot define one at all
    let no_auth = Who {
        authority: None,
        ..engineer()
    };
    let e = h
        .invoke_as(
            "ops",
            "add_template",
            map(&[("name", s("y")), ("text", s("hi"))]),
            &no_auth,
        )
        .unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied);
    // sending only reaches recipients
    let e = h
        .invoke(
            "ops",
            "send",
            map(&[("to", s("nobody")), ("text", s("hi"))]),
        )
        .unwrap_err();
    assert!(e.msg.contains("no such recipient"), "{e}");
    let e = h
        .invoke(
            "ops",
            "send",
            map(&[("to", s("team")), ("text", s("{{x}}"))]),
        )
        .unwrap_err();
    assert!(e.msg.contains("use a template"), "{e}");
}

#[test]
fn markup_that_does_not_parse_goes_again_as_plain_text_and_429_holds() {
    let api = Api::start();
    let mut h = telegram(&api);
    api.script(400, r#"{"ok":false,"error_code":400,"description":"Bad Request: can't parse entities: unclosed tag"}"#);
    h.invoke(
        "ops/recipients/team",
        "send",
        map(&[("text", s("T < 5 <b"))]),
    )
    .expect("send");
    h.until("sent", |h| h.num("ops/sent") == 1);
    let calls = api.calls("sendMessage");
    assert_eq!(calls.len(), 2);
    assert_eq!(calls[0].body["parse_mode"], "HTML");
    assert!(calls[1].body.get("parse_mode").is_none());
    // too many requests: the bot waits as told, keeps the message
    api.script(
        429,
        r#"{"ok":false,"description":"Too Many Requests","parameters":{"retry_after":3}}"#,
    );
    h.invoke("ops/recipients/team", "send", map(&[("text", s("again"))]))
        .expect("send");
    h.until("held", |h| h.text("ops/status") == "waiting");
    let t0 = h.now();
    h.until("sent after the hold", |h| h.num("ops/sent") == 2);
    assert!(h.now() - t0 >= 2_500_000, "waited {} µs", h.now() - t0);
    // a refused chat is dropped and counted
    api.script(
        400,
        r#"{"ok":false,"description":"Bad Request: chat not found"}"#,
    );
    h.invoke("ops/recipients/team", "send", map(&[("text", s("x"))]))
        .expect("send");
    h.until("failed", |h| h.num("ops/failed") == 1);
    assert!(h.text("ops/error").contains("chat not found"));
    // the token is in the request path: no error, value or log line carries it
    let secret = TG_TOKEN.split(':').nth(1).unwrap();
    assert!(
        !h.logs.iter().any(|l| l.contains(secret)),
        "a log line holds the token"
    );
    assert!(
        !format!("{:?}", h.values).contains(secret),
        "a value holds the token"
    );
}

#[test]
fn chat_users_pair_with_a_one_time_code_and_stay_within_three_bounds() {
    let api = Api::start();
    let mut h = telegram(&api);
    // an unknown account hears "not authorized" once, then nothing
    api.private(555, "/get downstream/mock/d1/temp");
    api.private(555, "hello");
    h.until("rejected", |h| h.num("ops/rejected") == 2);
    h.until("nag sent", |_| api.texts_to(555).len() == 1);
    assert!(api.texts_to(555)[0].starts_with("Not authorized"));
    // invite: the code is shown once; only its hash is stored
    let r = h
        .invoke(
            "ops",
            "invite_user",
            map(&[
                ("name", s("ann")),
                ("level", s("read")),
                ("select", s("wy/s/downstream/mock")),
            ]),
        )
        .expect("invite");
    let code = code_of(&r);
    assert_eq!(h.text("ops/users/ann/status"), "pending");
    let stored = h.store_raw("u/ops/ann").unwrap();
    assert!(!String::from_utf8_lossy(&stored).contains(&code));
    // a wrong code, then the right one typed loosely
    api.private(42, "/start AAAAA-AAAAA");
    h.until("wrong code answered", |_| api.texts_to(42).len() == 1);
    assert!(api.texts_to(42)[0].contains("not valid"));
    api.private(
        42,
        &format!("/start {}", code.to_lowercase().replace('-', " ")),
    );
    h.until("paired", |h| h.text("ops/users/ann/status") == "active");
    assert_eq!(h.text("ops/users/ann/chat_id"), "42");
    h.until("pairing answered", |_| api.texts_to(42).len() == 2);
    assert!(api.texts_to(42)[1].starts_with("Paired as ann"));
    // the code works once: another account cannot reuse it
    api.private(43, &format!("/start {code}"));
    h.until("reuse refused", |_| api.texts_to(43).len() == 1);
    assert!(api.texts_to(43)[0].contains("not valid"));
    // /get within the user's keys
    api.private(42, "/get downstream/mock/d1/temp");
    h.until("value answered", |_| api.texts_to(42).len() == 3);
    assert!(api.texts_to(42)[2].starts_with("wy/s/downstream/mock/d1/temp = 21.456 (good"));
    // outside its keys, and over its level
    api.private(42, "/get downstream/other/x");
    api.private(42, "/set downstream/mock/d1/temp 5");
    h.until("refusals", |_| api.texts_to(42).len() == 5);
    assert!(api.texts_to(42)[3].contains("outside your keys"));
    assert!(api.texts_to(42)[4].contains("outside your keys or level (read"));
    assert!(h.requests.is_empty(), "nothing was written");
    assert_eq!(h.num("ops/users/ann/commands"), 3);
    // disabled: ignored like a stranger
    h.invoke("ops/users/ann", "disable", Value::Null)
        .expect("disable");
    let before = h.num("ops/rejected");
    api.private(42, "/get downstream/mock/d1/temp");
    h.until("rejected", |h| h.num("ops/rejected") == before + 1);
    assert_eq!(api.texts_to(42).len(), 5);
}

#[test]
fn a_writer_sets_and_runs_actions_within_the_inviters_rights() {
    let api = Api::start();
    let mut h = telegram(&api);
    // a narrow operator cannot hand out write
    let e = h
        .invoke_as(
            "ops",
            "invite_user",
            map(&[
                ("name", s("bob")),
                ("level", s("write")),
                ("select", s("wy/s/downstream/mock")),
            ]),
            &narrow(),
        )
        .unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied);
    let code = code_of(
        &h.invoke(
            "ops",
            "invite_user",
            map(&[
                ("name", s("bob")),
                ("level", s("write")),
                (
                    "select",
                    s("wy/s/downstream/mock\nwy/s/downstream/telegram"),
                ),
            ]),
        )
        .unwrap(),
    );
    api.private(77, &format!("/start {code}"));
    h.until("paired", |h| h.text("ops/users/bob/status") == "active");
    api.private(77, "/set downstream/mock/d1/temp 42.5");
    h.until("set answered", |_| api.texts_to(77).len() == 2);
    assert_eq!(
        api.texts_to(77)[1],
        "wy/s/downstream/mock/d1/temp set: done"
    );
    assert_eq!(
        h.requests[0],
        (
            "wy/s/downstream/mock/d1/temp".into(),
            None,
            Value::Float(42.5)
        )
    );
    // a button press runs its command for the presser
    api.push_update(json!({"callback_query": {
        "id": "cb1", "from": {"id": 77}, "data": "/do downstream/mock/d1 reset",
        "message": {"chat": {"id": 77, "type": "private"}},
    }}));
    h.until("button ran", |h| h.requests.len() == 2);
    assert_eq!(h.requests[1].1.as_deref(), Some("reset"));
    h.until("answered", |_| !api.calls("answerCallbackQuery").is_empty());
    // the messenger itself is never written from a chat
    api.private(77, "/set downstream/telegram/ops/enabled false");
    h.until("refused", |_| api.texts_to(77).len() == 4);
    assert!(api
        .texts_to(77)
        .last()
        .unwrap()
        .contains("not set from a chat"));
    assert_eq!(h.requests.len(), 2);
    // a stranger's button is answered "Not authorized" and runs nothing
    api.push_update(json!({"callback_query": {
        "id": "cb2", "from": {"id": 9}, "data": "/do downstream/mock/d1 reset",
        "message": {"chat": {"id": 9, "type": "private"}},
    }}));
    h.until("stranger answered", |_| {
        api.calls("answerCallbackQuery").len() == 2
    });
    assert_eq!(
        api.calls("answerCallbackQuery")[1].body["text"],
        "Not authorized"
    );
    assert_eq!(h.requests.len(), 2);
    // rate: 20 a minute
    for _ in 0..25 {
        api.private(77, "/whoami");
    }
    h.until("rate limited", |_| {
        api.texts_to(77).iter().any(|t| t.contains("Too many"))
    });
    // disabling needs no rights; enabling hands bob's write back, so a caller below it may not
    h.invoke_as("ops/users/bob", "disable", Value::Null, &narrow())
        .expect("disable");
    assert_eq!(h.text("ops/users/bob/status"), "disabled");
    let e = h
        .invoke_as("ops/users/bob", "enable", Value::Null, &narrow())
        .unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied);
    assert_eq!(h.text("ops/users/bob/status"), "disabled");
    let mut no_auth = engineer();
    no_auth.authority = None;
    let e = h
        .invoke_as("ops/users/bob", "enable", Value::Null, &no_auth)
        .unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied);
    h.invoke_as("ops/users/bob", "enable", Value::Null, &engineer())
        .expect("enable");
    assert_eq!(h.text("ops/users/bob/status"), "active");
}

#[test]
fn groups_are_recipients_or_left_and_codes_sent_there_are_void() {
    let api = Api::start();
    let mut h = telegram(&api);
    let code = code_of(
        &h.invoke("ops", "invite_user", map(&[("name", s("cy"))]))
            .unwrap(),
    );
    // the bot is added to a group nobody registered: it leaves
    api.push_update(json!({"my_chat_member": {"chat": {"id": -999, "type": "group"}}}));
    h.until("left", |_| !api.calls("leaveChat").is_empty());
    assert_eq!(api.calls("leaveChat")[0].body["chat_id"], -999);
    // a code posted in a group is void at once
    api.group(-1001234567890, 31, &format!("/start {code}"));
    h.until("voided", |h| h.logs.iter().any(|l| l.contains("voided")));
    // the group, a recipient, is told
    h.until("told", |_| api.texts_to(-1001234567890).len() == 1);
    assert!(api.texts_to(-1001234567890)[0].contains("void"));
    api.private(31, &format!("/start {code}"));
    h.until("refused", |_| api.texts_to(31).len() == 1);
    assert!(api.texts_to(31)[0].contains("not valid"));
    assert_eq!(h.text("ops/users/cy/status"), "pending");
    // a new code, paired in private; commands in the group only where the recipient allows them
    let code = code_of(&h.invoke("ops/users/cy", "new_code", Value::Null).unwrap());
    api.private(31, &format!("/start {code}"));
    h.until("paired", |h| h.text("ops/users/cy/status") == "active");
    api.group(-1001234567890, 31, "/get downstream/mock/d1/temp");
    h.advance_ms(3000);
    assert_eq!(
        api.texts_to(-1001234567890).len(),
        1,
        "commands are off in team"
    );
    h.invoke(
        "ops/recipients/team",
        "edit",
        map(&[("commands", Value::Bool(true))]),
    )
    .unwrap();
    api.group(-1001234567890, 31, "/get downstream/mock/d1/temp");
    h.until("answered in the group", |_| {
        api.texts_to(-1001234567890).len() == 2
    });
    // and a stranger in the same group is not answered
    api.group(-1001234567890, 32, "/get downstream/mock/d1/temp");
    h.advance_ms(3000);
    assert_eq!(api.texts_to(-1001234567890).len(), 2);
    // a recipient that names a paired user
    h.invoke(
        "ops",
        "add_recipient",
        map(&[("name", s("cy_dm")), ("chat", s("user:cy"))]),
    )
    .unwrap();
    h.invoke(
        "ops",
        "send",
        map(&[("to", s("cy_dm")), ("text", s("hi {{bot}}"))]),
    )
    .unwrap();
    h.until("dm", |_| api.texts_to(31).iter().any(|t| t == "hi ops"));
}

#[test]
fn definitions_and_the_token_survive_a_restart_and_a_moved_endpoint_drops_the_token() {
    let api = Api::start();
    let mut h = telegram(&api);
    h.invoke(
        "ops",
        "add_template",
        map(&[("name", s("t")), ("text", s("x {{a}}")), ("to", s("team"))]),
    )
    .unwrap();
    let code = code_of(
        &h.invoke("ops", "invite_user", map(&[("name", s("dee"))]))
            .unwrap(),
    );
    api.private(64, &format!("/start {code}"));
    h.until("paired", |h| h.text("ops/users/dee/status") == "active");
    let offset = h.store_raw("offset/ops").unwrap();
    h.restart();
    h.until("ready again", |h| h.text("ops/status") == "ready");
    assert!(h.nodes.contains_key("ops/templates/t"));
    assert!(h.nodes.contains_key("ops/recipients/team"));
    assert_eq!(h.text("ops/users/dee/status"), "active");
    assert_eq!(
        h.store_raw("offset/ops").unwrap(),
        offset,
        "updates are not read twice"
    );
    h.invoke("ops/templates/t", "send", map(&[("a", s("1"))]))
        .unwrap();
    h.until("sent", |h| h.num("ops/sent") == 1);
    // the same API: the token stays; another one: it goes
    h.invoke("ops", "edit", map(&[("poll_s", Value::UInt(5))]))
        .unwrap();
    assert!(h.store_has("secret/ops"));
    let other = Api::start();
    let mut net = h.params.clone();
    if let Value::Map(m) = &mut net {
        m.insert(
            "net".into(),
            s(&format!("127.0.0.1:{}, 127.0.0.1:{}", api.port, other.port)),
        );
    }
    h.params = net;
    h.restart();
    h.invoke("ops", "edit", map(&[("api_url", s(&other.url()))]))
        .unwrap();
    assert!(!h.store_has("secret/ops"));
    assert_eq!(h.text("ops/status"), "no_token");
    // a host outside the link's net is refused at Add
    let e = h
        .invoke("", "add_bot", map(&[("name", s("x"))]))
        .unwrap_err();
    assert!(e.msg.contains("net allowlist"), "{e}");
    // removing a bot removes its store
    h.invoke("ops", "remove", Value::Null).unwrap();
    assert!(!h.store_has("b/ops") && !h.store_has("u/ops/dee") && !h.store_has("rights/u/ops/dee"));
}

#[test]
fn send_raw_names_only_listed_methods_and_known_chats() {
    let api = Api::start();
    let mut h = telegram(&api);
    let raw = |h: &mut SimHost, method: &str, params: &str| {
        h.invoke(
            "ops",
            "send_raw",
            map(&[("method", s(method)), ("params", s(params))]),
        )
    };
    // a recipient's chat: sent
    let r = raw(
        &mut h,
        "sendPoll",
        r#"{"chat_id": -1001234567890, "question": "q", "options": ["a", "b"]}"#,
    );
    assert!(r.is_ok(), "{r:?}");
    assert_eq!(api.calls("sendPoll").len(), 1);
    // the chat in a secondary field: forwarding out of a chat the bot does not know
    let e = raw(
        &mut h,
        "forwardMessage",
        r#"{"chat_id": -1001234567890, "from_chat_id": -555, "message_id": 1}"#,
    )
    .unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied, "{e}");
    // an account named beside a known chat
    let e = raw(
        &mut h,
        "sendMessage",
        r#"{"chat_id": -1001234567890, "user_id": 555, "text": "x"}"#,
    )
    .unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied, "{e}");
    // the method's chat missing, an inline message, a method outside the list
    let e = raw(
        &mut h,
        "forwardMessage",
        r#"{"chat_id": -1001234567890, "message_id": 1}"#,
    )
    .unwrap_err();
    assert_eq!(e.status, Status::InvalidParameter, "{e}");
    let e = raw(
        &mut h,
        "editMessageText",
        r#"{"inline_message_id": "x", "text": "y"}"#,
    )
    .unwrap_err();
    assert_eq!(e.status, Status::InvalidParameter, "{e}");
    for m in ["deleteWebhook", "deleteMyCommands", "setChatTitle"] {
        let e = raw(&mut h, m, r#"{"chat_id": -1001234567890}"#).unwrap_err();
        assert_eq!(e.status, Status::InvalidParameter, "{m}: {e}");
    }
    assert!(api.calls("forwardMessage").is_empty() && api.calls("sendMessage").is_empty());
    assert!(api.calls("deleteWebhook").is_empty() && api.calls("editMessageText").is_empty());
}
