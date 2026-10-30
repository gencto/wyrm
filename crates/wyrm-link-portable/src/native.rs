//! [`NativeEngine`]: an [`App`] compiled into the host. A panic in the app is a [`Fault`]; an endless
//! loop cannot be stopped (the runtime reports the link `stuck`), so only trusted code runs here.

use std::panic::{catch_unwind, AssertUnwindSafe};

use wyrm_core::{Status, Value};
use wyrm_link_api::buffer::BufferHost;
use wyrm_link_api::{App, AppError, Host};
use wyrm_link_sdk::{LinkCtx, LinkError};

use crate::engine::{Engine, Event, Fault, MakeEngine};
use crate::PortableConfig;

pub struct NativeEngine<A: App> {
    app: Option<A>,
}

impl<A: App> NativeEngine<A> {
    pub fn new() -> Self {
        Self { app: None }
    }
}

impl<A: App> Default for NativeEngine<A> {
    fn default() -> Self {
        Self::new()
    }
}

fn panic_text(p: Box<dyn std::any::Any + Send>) -> String {
    let what = p
        .downcast_ref::<&str>()
        .map(|s| (*s).to_owned())
        .or_else(|| p.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "unknown payload".to_owned());
    format!("panic: {what}")
}

fn guard<T>(f: impl FnOnce() -> T) -> Result<T, Fault> {
    catch_unwind(AssertUnwindSafe(f)).map_err(|p| Fault::Crash(panic_text(p)))
}

impl<A: App + Send + 'static> Engine for NativeEngine<A> {
    fn name(&self) -> String {
        A::NAME.to_owned()
    }

    fn version(&self) -> String {
        A::VERSION.to_owned()
    }

    fn start(
        &mut self,
        host: &mut BufferHost,
        config: &Value,
    ) -> Result<Result<(), AppError>, Fault> {
        self.app = None;
        let config = config.clone();
        let r = guard(|| A::start(host as &mut dyn Host, config))?;
        Ok(r.map(|app| self.app = Some(app)))
    }

    fn event(
        &mut self,
        host: &mut BufferHost,
        ev: Event,
    ) -> Result<Result<Option<Value>, AppError>, Fault> {
        let Some(app) = self.app.as_mut() else {
            return Ok(Err(AppError::new(Status::Busy, "the link is not running")));
        };
        let host = host as &mut dyn Host;
        let r = guard(|| match ev {
            Event::Set { path, value, who } => app.on_set(host, &path, value, &who).map(|()| None),
            Event::Invoke {
                path,
                action,
                args,
                who,
            } => app.on_invoke(host, &path, &action, args, &who).map(Some),
            Event::Timer(t) => {
                app.on_timer(host, t);
                Ok(None)
            }
            Event::Value(sub, key, sample) => {
                app.on_value(host, sub, &key, sample);
                Ok(None)
            }
            Event::Reply(req, result) => {
                app.on_reply(host, req, result);
                Ok(None)
            }
            Event::List(sub, key, change) => {
                app.on_list(host, sub, &key, change);
                Ok(None)
            }
            Event::Stop => {
                app.stop(host);
                Ok(None)
            }
        });
        if r.is_err() {
            // memory of an app that panicked half way is not trusted again
            self.app = None;
        }
        r
    }

    fn reset(&mut self) {
        self.app = None;
    }
}

impl<A: App + Send + 'static> MakeEngine for NativeEngine<A> {
    const NAME: &'static str = A::NAME;
    const VERSION: &'static str = A::VERSION;
    type E = Self;

    fn make(_cfg: &PortableConfig, _ctx: &LinkCtx) -> Result<Self, LinkError> {
        Ok(Self::new())
    }
}
