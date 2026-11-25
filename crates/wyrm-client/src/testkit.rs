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

/// [`value_stream`] with its stored read in flight, as a
/// [`subscribe`](crate::WyrmClient::subscribe) is once its subscriber is declared: the
/// first callback is the live handler, the second the handler of the stored read (it takes
/// the sample of each reply; dropping it ends the read, as Zenoh does after the last
/// reply), the stream is what the consumer reads.
pub fn value_stream_stored() -> (Callback<Sample>, Callback<Sample>, EventStream<ValEvent>) {
    crate::streams::fed_stored()
}
