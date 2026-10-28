//! The `Echo` app of `tests/app.rs` as a WASM component (`wyrm:app/app`).

mod echo;

wyrm_link_guest::export!(echo::Echo);
