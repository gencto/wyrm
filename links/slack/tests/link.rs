//! The Slack link against a fake Web API on loopback: the bearer token, a refused token,
//! mrkdwn and Block Kit templates with escaped values, raw requests only to recipient channels.

use wyrm_core::{Status, Value};
use wyrm_link_slack::SlackLink;
use wyrm_messenger::testkit::{map, s, Api, SLACK_TOKEN};

type SimHost = wyrm_messenger::testkit::SimHost<SlackLink>;

#[test]
fn slack_posts_with_the_bearer_token_and_block_kit() {
    let api = Api::start();
    let mut h = SimHost::new(api.port);
    h.start();
    h.invoke(
        "",
        "add_bot",
        map(&[("name", s("eng")), ("api_url", s(&api.url()))]),
    )
    .unwrap();
    // Slack bots only send for now
    assert!(h
        .invoke(
            "",
            "add_bot",
            map(&[
                ("name", s("x")),
                ("api_url", s(&api.url())),
                ("commands", Value::Bool(true))
            ])
        )
        .is_err());
    // nor has chat users, command buttons or user recipients
    assert!(!h.actions["eng"].iter().any(|(n, _)| n == "invite_user"));
    assert!(!h.nodes.contains_key("eng/users"));
    assert!(h
        .invoke(
            "eng",
            "add_recipient",
            map(&[("name", s("u")), ("chat", s("user:ann"))])
        )
        .is_err());
    assert!(h
        .invoke(
            "eng",
            "add_template",
            map(&[
                ("name", s("b")),
                ("text", s("x")),
                ("buttons", s("Ack | /do x y"))
            ])
        )
        .is_err());
    assert!(
        h.invoke(
            "eng",
            "add_recipient",
            map(&[("name", s("bad")), ("chat", s("-1001234567890"))])
        )
        .is_err(),
        "a Telegram chat id is no Slack channel"
    );
    h.invoke("eng", "set_token", map(&[("token", s("xoxb-wrong"))]))
        .unwrap();
    h.until("failed", |h| h.text("eng/status") == "failed");
    assert!(h.text("eng/error").contains("invalid_auth"));
    h.invoke("eng", "set_token", map(&[("token", s(SLACK_TOKEN))]))
        .unwrap();
    h.until("ready", |h| h.text("eng/status") == "ready");
    h.invoke(
        "eng",
        "add_recipient",
        map(&[("name", s("alerts")), ("chat", s("C0123ABCD"))]),
    )
    .unwrap();
    h.invoke(
        "eng",
        "add_template",
        map(&[
            ("name", s("card")),
            ("text", s("{{who}}: {{temp:.0}}")),
            ("blocks", s(r#"[{"type":"section","text":{"type":"mrkdwn","text":"*{{who}}* is at {{temp:.1}}"}}]"#)),
            ("values", s("temp = wy/s/downstream/mock/d1/temp")),
            ("to", s("alerts")),
        ]),
    )
    .unwrap();
    h.invoke(
        "eng/templates/card",
        "send",
        map(&[("who", s("Boiler \"A\""))]),
    )
    .unwrap();
    h.until("sent", |h| h.num("eng/sent") == 1);
    let c = &api.calls("chat.postMessage")[0];
    assert!(c
        .headers
        .iter()
        .any(|(k, v)| k == "authorization" && v == &format!("Bearer {SLACK_TOKEN}")));
    assert_eq!(c.body["channel"], "C0123ABCD");
    assert_eq!(
        c.body["blocks"][0]["text"]["text"],
        "*Boiler \"A\"* is at 21.5"
    );
    assert_eq!(c.body["text"], "Boiler \"A\": 21");
    // a raw request only to a recipient's channel, only offered methods
    let e = h
        .invoke(
            "eng",
            "send_raw",
            map(&[
                ("method", s("chat.postMessage")),
                ("params", s(r#"{"channel":"C999","text":"x"}"#)),
            ]),
        )
        .unwrap_err();
    assert_eq!(e.status, Status::PermissionDenied);
    assert!(h
        .invoke("eng", "send_raw", map(&[("method", s("users.list"))]))
        .is_err());
    let r = h
        .invoke(
            "eng",
            "send_raw",
            map(&[
                ("method", s("reactions.add")),
                (
                    "params",
                    s(r#"{"channel":"C0123ABCD","name":"eyes","timestamp":"1.2"}"#),
                ),
            ]),
        )
        .unwrap();
    let Value::Map(r) = r else { panic!() };
    assert_eq!(r.get("ok"), Some(&Value::Bool(true)));
}
