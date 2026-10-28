//! The `Echo` app of `tests/app.rs` as a WASM component (`wyrm:app/app`). With the feature `v2`
//! it also declares `v2`: the "new code" of the hot start tests.

mod echo;

#[cfg(not(feature = "v2"))]
wyrm_link_guest::export!(echo::Echo);

#[cfg(feature = "v2")]
mod v2 {
    use wyrm_core::{NodeMeta, Sample, Value};
    use wyrm_link_api::{App, AppError, Host, ReqId, SubId, TimerId, Who};

    use crate::echo::Echo;

    /// `Echo` plus a node `v2`.
    pub struct V2(Echo);

    impl App for V2 {
        const NAME: &'static str = "echo";
        const VERSION: &'static str = "0.2.0";

        fn start(host: &mut dyn Host, config: Value) -> Result<Self, AppError> {
            let e = Echo::start(host, config)?;
            host.declare_node("v2", NodeMeta::number());
            Ok(V2(e))
        }

        fn on_set(
            &mut self,
            host: &mut dyn Host,
            path: &str,
            value: Value,
            who: &Who,
        ) -> Result<(), AppError> {
            self.0.on_set(host, path, value, who)
        }

        fn on_invoke(
            &mut self,
            host: &mut dyn Host,
            path: &str,
            action: &str,
            args: Value,
            who: &Who,
        ) -> Result<Value, AppError> {
            self.0.on_invoke(host, path, action, args, who)
        }

        fn on_timer(&mut self, host: &mut dyn Host, timer: TimerId) {
            self.0.on_timer(host, timer)
        }

        fn on_value(&mut self, host: &mut dyn Host, sub: SubId, key: &str, sample: Sample) {
            self.0.on_value(host, sub, key, sample)
        }

        fn on_reply(&mut self, host: &mut dyn Host, req: ReqId, result: Result<Value, AppError>) {
            self.0.on_reply(host, req, result)
        }

        fn stop(&mut self, host: &mut dyn Host) {
            self.0.stop(host)
        }
    }
}

#[cfg(feature = "v2")]
wyrm_link_guest::export!(v2::V2);
