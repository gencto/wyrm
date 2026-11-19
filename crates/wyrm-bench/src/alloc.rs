//! A global allocator that counts: calls, frees, bytes allocated and bytes freed. It hands
//! every call to `System` unchanged.

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicU64, Ordering};

static CALLS: AtomicU64 = AtomicU64::new(0);
static FREES: AtomicU64 = AtomicU64::new(0);
static BYTES: AtomicU64 = AtomicU64::new(0);
static FREED: AtomicU64 = AtomicU64::new(0);

/// The counting allocator. Install it in the bench or test binary:
/// `#[global_allocator] static A: wyrm_bench::Counting = wyrm_bench::Counting;`.
/// Without it [`Allocs::read`] reads zeros ([`Allocs::active`] is `false`).
pub struct Counting;

fn size(l: Layout) -> u64 {
    u64::try_from(l.size()).unwrap_or(u64::MAX)
}

fn took(bytes: u64) {
    CALLS.fetch_add(1, Ordering::Relaxed);
    BYTES.fetch_add(bytes, Ordering::Relaxed);
}

fn gave(bytes: u64) {
    FREES.fetch_add(1, Ordering::Relaxed);
    FREED.fetch_add(bytes, Ordering::Relaxed);
}

// SAFETY: every method passes the caller's own arguments to `System`, which keeps the
// `GlobalAlloc` contract; the counters are atomics that touch no memory of the caller and
// never allocate.
#[allow(
    unsafe_code,
    reason = "a counting allocator: GlobalAlloc is an unsafe trait (docs/rust-rules.md §2)"
)]
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        took(size(l));
        // SAFETY: the caller's `alloc` contract (non-zero size) is passed on unchanged.
        unsafe { System.alloc(l) }
    }

    unsafe fn alloc_zeroed(&self, l: Layout) -> *mut u8 {
        took(size(l));
        // SAFETY: as `alloc`: the caller's layout is passed on unchanged.
        unsafe { System.alloc_zeroed(l) }
    }

    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        gave(size(l));
        // SAFETY: `p` came from this allocator, i.e. from `System`, with layout `l`.
        unsafe { System.dealloc(p, l) }
    }

    unsafe fn realloc(&self, p: *mut u8, l: Layout, new: usize) -> *mut u8 {
        // one call: the old block goes, a block of `new` bytes comes
        took(u64::try_from(new).unwrap_or(u64::MAX));
        FREED.fetch_add(size(l), Ordering::Relaxed);
        // SAFETY: `p` came from `System` with layout `l`; `new` is the caller's, non-zero by
        // the `realloc` contract.
        unsafe { System.realloc(p, l, new) }
    }
}

/// The counters at one moment; the difference of two is what happened between them.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Allocs {
    /// `alloc`, `alloc_zeroed` and `realloc` calls.
    pub calls: u64,
    /// `dealloc` calls.
    pub frees: u64,
    /// Bytes handed out (a `realloc` counts its new size).
    pub bytes: u64,
    /// Bytes given back (a `realloc` counts its old size).
    pub freed: u64,
}

impl Allocs {
    pub fn read() -> Self {
        Self {
            calls: CALLS.load(Ordering::Relaxed),
            frees: FREES.load(Ordering::Relaxed),
            bytes: BYTES.load(Ordering::Relaxed),
            freed: FREED.load(Ordering::Relaxed),
        }
    }

    /// `true` when this binary runs on [`Counting`] (something was counted).
    pub fn active() -> bool {
        CALLS.load(Ordering::Relaxed) > 0
    }

    /// What happened since `earlier`.
    pub fn since(self, earlier: Self) -> Self {
        Self {
            calls: self.calls.saturating_sub(earlier.calls),
            frees: self.frees.saturating_sub(earlier.frees),
            bytes: self.bytes.saturating_sub(earlier.bytes),
            freed: self.freed.saturating_sub(earlier.freed),
        }
    }

    /// Bytes allocated and not freed (negative when more was freed than allocated).
    pub fn live(self) -> i64 {
        let b = i64::try_from(self.bytes).unwrap_or(i64::MAX);
        let f = i64::try_from(self.freed).unwrap_or(i64::MAX);
        b.saturating_sub(f)
    }

    /// Calls per operation over `ops` operations.
    pub fn calls_per(self, ops: u64) -> f64 {
        if ops == 0 {
            return f64::NAN;
        }
        self.calls as f64 / ops as f64
    }

    /// Bytes per operation over `ops` operations.
    pub fn bytes_per(self, ops: u64) -> f64 {
        if ops == 0 {
            return f64::NAN;
        }
        self.bytes as f64 / ops as f64
    }
}
