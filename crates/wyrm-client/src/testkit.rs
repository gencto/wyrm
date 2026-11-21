//! Test hooks (feature `testkit`, dev only): the client's own machinery without a session.

use crate::{EventStream, ValEvent};
use zenoh::handlers::Callback;
use zenoh::sample::Sample;

/// The value stream of [`WyrmClient::subscribe`](crate::WyrmClient::subscribe) with no
/// session behind it: the callback is the handler the client gives its Zenoh subscriber
/// (it takes a `…/~val` sample as Zenoh delivers it), the stream is what the consumer
/// reads. No stored read; dropping the callback ends the stream like a closed session.
pub fn value_stream() -> (Callback<Sample>, EventStream<ValEvent>) {
    crate::streams::fed(std::sync::Arc::new(|_| true))
}

/// [`value_stream`] of only the node keys `keep` accepts, as
/// [`WyrmClient::subscribe_filtered`](crate::WyrmClient::subscribe_filtered) makes it:
/// `keep` runs in the callback, before anything is copied or buffered.
pub fn value_stream_filtered(
    keep: impl Fn(&str) -> bool + Send + Sync + 'static,
) -> (Callback<Sample>, EventStream<ValEvent>) {
    crate::streams::fed(std::sync::Arc::new(keep))
}
