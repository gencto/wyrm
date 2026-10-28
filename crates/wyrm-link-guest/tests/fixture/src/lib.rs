//! The smallest app: one point that takes a `set` and echoes an `invoke`.

use wyrm_core::{NodeMeta, Quality, Sample, Value};
use wyrm_link_api::{App, AppError, Host, Who};

struct Echo;

impl App for Echo {
    const NAME: &'static str = "echo";
    const VERSION: &'static str = "0.0.0";

    fn start(host: &mut dyn Host, _config: Value) -> Result<Self, AppError> {
        host.declare_node("p", NodeMeta::default());
        Ok(Echo)
    }

    fn on_set(
        &mut self,
        host: &mut dyn Host,
        path: &str,
        value: Value,
        _who: &Who,
    ) -> Result<(), AppError> {
        let t = host.now_us();
        host.update(
            path,
            Sample {
                v: value,
                q: Quality::Good,
                t,
            },
        );
        Ok(())
    }

    fn on_invoke(
        &mut self,
        _host: &mut dyn Host,
        _path: &str,
        _action: &str,
        args: Value,
        _who: &Who,
    ) -> Result<Value, AppError> {
        Ok(args)
    }
}

wyrm_link_guest::export!(Echo);
