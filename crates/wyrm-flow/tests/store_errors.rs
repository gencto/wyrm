//! Audit T7 (docs/rust-rules.md §8): the flow host's stores answer with typed
//! errors. Each text is the one the error had while it was a boxed error or a
//! `String`: it reaches `wyrmd`'s start line and the refusals of
//! `put_artifact` and `deploy`.

use std::error::Error as _;
use std::path::PathBuf;
use wyrm_flow::artifacts::Artifacts;
use wyrm_flow::{ArtifactError, FlowHost, HostError};
use wyrm_state::StateError;

const SITE: &str = "plant";

fn temp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("wyrm-flow-errors-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

/// The error of an open, `None` when the host opened.
fn refused(dir: &std::path::Path) -> Option<HostError> {
    FlowHost::open(dir, b"flow-test-hmac-key", SITE).err()
}

/// A store held by another host is `InUse`, so a caller that waits for a
/// closing broker matches the variant, not the text; the cause is the
/// `wyrm-state` error, and the text is the cause's own, as it was.
#[test]
fn a_held_store_is_in_use_with_the_old_text() {
    let dir = temp("held");
    let first = FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap();
    let Some(e) = refused(&dir) else {
        panic!("the host opened in {}", dir.display());
    };
    assert!(matches!(&e, HostError::InUse(_)), "{e:?}");
    assert_eq!(
        e.to_string(),
        format!(
            "{} is in use by another process",
            dir.join("state").display()
        )
    );
    let cause = e.source().and_then(|s| s.downcast_ref::<StateError>());
    assert!(matches!(cause, Some(StateError::InUse(_))), "{cause:?}");
    // let go, it opens again
    drop(first);
    FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap();
    let _ = std::fs::remove_dir_all(dir);
}

/// What else keeps a host from opening is not "in use".
#[cfg(unix)]
#[test]
fn other_causes_keep_their_texts() {
    // a flow key that is no key
    let dir = temp("key");
    drop(FlowHost::open(&dir, b"flow-test-hmac-key", SITE).unwrap());
    std::fs::write(dir.join("flow.key"), "zz\n").unwrap();
    let Some(e) = refused(&dir) else {
        panic!("the host opened in {}", dir.display());
    };
    assert!(matches!(e, HostError::Key), "{e:?}");
    assert_eq!(e.to_string(), "flow.key: expected 32 bytes hex");
    // the host's place is a file
    let file = temp("file");
    std::fs::write(&file, b"not a directory").unwrap();
    let Some(e) = refused(&file) else {
        panic!("the host opened in {}", file.display());
    };
    assert!(matches!(e, HostError::Io(_)), "{e:?}");
    assert_eq!(e.to_string(), "File exists (os error 17)");
    // the store's place is a file: the store's own error, not `InUse`
    let state = temp("state");
    std::fs::create_dir_all(&state).unwrap();
    std::fs::write(state.join("state"), b"not a directory").unwrap();
    let Some(e) = refused(&state) else {
        panic!("the host opened in {}", state.display());
    };
    assert!(matches!(e, HostError::State(StateError::Io(_))), "{e:?}");
    assert_eq!(e.to_string(), "io: File exists (os error 17)");
    assert!(e.source().is_some());
    let _ = std::fs::remove_dir_all(dir);
    let _ = std::fs::remove_file(file);
    let _ = std::fs::remove_dir_all(state);
}

/// The artifact store: every refusal has its variant and its old text.
#[test]
fn artifact_errors_keep_their_texts() {
    let dir = temp("artifacts");
    let store = Artifacts::new(&dir);
    let Err(e) = store.get("ABC") else {
        panic!("a name that is no hash was taken");
    };
    assert!(matches!(e, ArtifactError::Name), "{e:?}");
    assert_eq!(
        e.to_string(),
        "artifact: expected 64 lowercase hex characters"
    );
    let missing = "0".repeat(64);
    let Err(e) = store.get(&missing) else {
        panic!("an artifact nobody stored was found");
    };
    assert!(
        matches!(&e, ArtifactError::NotFound { sha, .. } if *sha == missing),
        "{e:?}"
    );
    assert_eq!(e.to_string(), format!("artifact: no artifact {missing}"));
    // the cause is kept now (it was dropped by a `map_err(|_| …)`)
    let cause = e.source().and_then(|s| s.downcast_ref::<std::io::Error>());
    assert_eq!(
        cause.map(std::io::Error::kind),
        Some(std::io::ErrorKind::NotFound)
    );
    // a file whose bytes are not the ones of its name
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join(format!("{missing}.wasm")), b"other bytes").unwrap();
    let Err(e) = store.get(&missing) else {
        panic!("a changed artifact was loaded");
    };
    assert!(matches!(e, ArtifactError::Changed { .. }), "{e:?}");
    assert_eq!(
        e.to_string(),
        format!("artifact: {missing}: content does not match its hash")
    );
    // bytes that are no component: the host's text alone, as before
    let Err(e) = store.put(b"not wasm") else {
        panic!("bytes that are no component were stored");
    };
    let ArtifactError::Component(cause) = &e else {
        panic!("{e:?}");
    };
    assert!(matches!(cause, wyrm_wasm_host::Error::Invalid(_)), "{e:?}");
    assert_eq!(e.to_string(), cause.to_string());
    assert!(e.to_string().starts_with("invalid component: "), "{e}");
    let _ = std::fs::remove_dir_all(dir);
}
