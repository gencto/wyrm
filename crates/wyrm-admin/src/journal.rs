//! The writer of the audit journal: one thread owns the store and writes the records
//! that wait as one batch under one `fsync` (group commit, `Store::apply_batch`).
//!
//! What a caller may rely on (`docs/operations.md` §1, "The audit journal"):
//!
//! * [`Journal::write_record`] and [`Journal::write_blocking`] answer `Ok` only after the
//!   record is on disk (`fsync`ed, the anchor at it). An error is the caller's to
//!   report; nothing is answered `Ok` and lost.
//! * [`Journal::push_record`] is for a record nobody waits for (a link's own report of a
//!   `set`/`invoke`, which the link put without an acknowledgement: ADR 0029,
//!   decision 7). It returns when the record has a place in the queue; the writer
//!   logs a failed write. [`Journal::flush`] and [`Journal::close`] write all of them.
//! * Records are written in the order they entered the queue, and the queue is
//!   bounded ([`QUEUE`]): a caller waits for room, no record is dropped to make room.
//! * No file I/O runs on the caller's thread. A caller on a runtime waits as a task;
//!   a caller without `async` leaves its worker to the runtime while it waits
//!   (`block_in_place`).

use crate::audit::{AuditLog, AuditRecord, RECENT};
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Condvar, Mutex, MutexGuard};
use tokio::sync::{oneshot, Notify};
use tracing::{error, warn};
use wyrm_state::{StateError, Store};

/// Records that wait for the writer. A caller that finds the queue full waits.
pub(crate) const QUEUE: usize = 1024;
/// Most records of one batch, so of one `fsync`.
pub(crate) const BATCH: usize = 256;

type Answer = Result<u64, StateError>;

/// Where the answer for one record goes.
enum Ack {
    /// Nobody waits: the writer logs a failure.
    Log,
    /// A caller that waits on its thread.
    Thread(mpsc::SyncSender<Answer>),
    /// A caller that waits as a task.
    Task(oneshot::Sender<Answer>),
}

struct Item {
    /// `None`: nothing to write, the answer says everything before it is written.
    rec: Option<AuditRecord>,
    ack: Ack,
}

#[derive(Default)]
struct Queue {
    items: VecDeque<Item>,
    closed: bool,
    /// The most items the queue ever held.
    high: usize,
}

/// What readers see: the head and the last records, as of the last batch.
struct View {
    lsn: u64,
    recent: VecDeque<AuditRecord>,
}

struct Shared {
    queue: Mutex<Queue>,
    /// The writer waits here for records.
    work: Condvar,
    /// Callers that wait on their thread for room.
    room: Condvar,
    /// Callers that wait as a task for room.
    room_task: Notify,
    view: Mutex<View>,
    batches: AtomicU64,
    /// Tests set it to keep the writer from its next batch.
    #[cfg(test)]
    held: std::sync::atomic::AtomicBool,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|p| p.into_inner())
}

fn closed() -> StateError {
    StateError::Io(std::io::Error::other("the audit journal is closed"))
}

/// Run `f`, which waits, without holding a worker of a multi-thread runtime.
fn off_worker<T>(f: impl FnOnce() -> T) -> T {
    match tokio::runtime::Handle::try_current() {
        Ok(h) if h.runtime_flavor() == tokio::runtime::RuntimeFlavor::MultiThread => {
            tokio::task::block_in_place(f)
        }
        // no runtime, or one thread that runs everything: nothing to hand over
        _ => f(),
    }
}

pub(crate) struct Journal {
    shared: Arc<Shared>,
    writer: Mutex<Option<std::thread::JoinHandle<()>>>,
}

impl Journal {
    /// Start the writer thread on `store`.
    pub(crate) fn start(store: Store<AuditLog>) -> std::io::Result<Self> {
        let shared = Arc::new(Shared {
            queue: Mutex::new(Queue::default()),
            work: Condvar::new(),
            room: Condvar::new(),
            room_task: Notify::new(),
            view: Mutex::new(View {
                lsn: store.lsn(),
                recent: store.state().recent.clone(),
            }),
            batches: AtomicU64::new(0),
            #[cfg(test)]
            held: std::sync::atomic::AtomicBool::new(false),
        });
        let s = shared.clone();
        let writer = std::thread::Builder::new()
            .name("wyrm-audit".into())
            .spawn(move || run(&s, store))?;
        Ok(Self {
            shared,
            writer: Mutex::new(Some(writer)),
        })
    }

    /// Records written so far (the journal's LSN).
    pub(crate) fn lsn(&self) -> u64 {
        lock(&self.shared.view).lsn
    }

    /// The last `n` records written.
    pub(crate) fn tail(&self, n: usize) -> Vec<AuditRecord> {
        let v = lock(&self.shared.view);
        v.recent
            .iter()
            .skip(v.recent.len().saturating_sub(n))
            .cloned()
            .collect()
    }

    /// Batches written so far: one `fsync` of the WAL each.
    #[cfg(any(test, feature = "testkit"))]
    pub(crate) fn batches(&self) -> u64 {
        self.shared.batches.load(Ordering::Relaxed)
    }

    /// Put `item` in the queue, as a task that waits for room.
    async fn enqueue(&self, item: Item) -> Result<(), StateError> {
        let mut item = Some(item);
        loop {
            let room = self.shared.room_task.notified();
            tokio::pin!(room);
            // registered before the queue is read: a wake-up between the two is kept
            room.as_mut().enable();
            {
                let mut q = lock(&self.shared.queue);
                if q.closed {
                    return Err(closed());
                }
                if q.items.len() < QUEUE {
                    if let Some(item) = item.take() {
                        q.items.push_back(item);
                        q.high = q.high.max(q.items.len());
                    }
                    self.shared.work.notify_one();
                    return Ok(());
                }
            }
            room.await;
        }
    }

    /// Put `item` in the queue, waiting on this thread for room.
    fn enqueue_blocking(&self, item: Item) -> Result<(), StateError> {
        let mut q = lock(&self.shared.queue);
        while !q.closed && q.items.len() >= QUEUE {
            q = self.shared.room.wait(q).unwrap_or_else(|p| p.into_inner());
        }
        if q.closed {
            return Err(closed());
        }
        q.items.push_back(item);
        q.high = q.high.max(q.items.len());
        self.shared.work.notify_one();
        Ok(())
    }

    /// Queue `rec` for the writer and return: nobody waits for this record, and
    /// the writer logs it if the write fails. `Err` only when the journal is closed.
    pub(crate) async fn push_record(&self, rec: AuditRecord) -> Result<(), StateError> {
        self.enqueue(Item {
            rec: Some(rec),
            ack: Ack::Log,
        })
        .await
    }

    /// Write `rec`: `Ok(lsn)` when it is on disk.
    pub(crate) async fn write_record(&self, rec: AuditRecord) -> Answer {
        let (tx, rx) = oneshot::channel();
        self.enqueue(Item {
            rec: Some(rec),
            ack: Ack::Task(tx),
        })
        .await?;
        rx.await.unwrap_or_else(|_| Err(closed()))
    }

    /// Write `rec` from code that is not `async`: `Ok(lsn)` when it is on disk.
    /// The write runs on the writer thread; this thread only waits, and on a
    /// multi-thread runtime its worker goes on with other tasks meanwhile.
    pub(crate) fn write_blocking(&self, rec: AuditRecord) -> Answer {
        off_worker(|| {
            let (tx, rx) = mpsc::sync_channel(1);
            self.enqueue_blocking(Item {
                rec: Some(rec),
                ack: Ack::Thread(tx),
            })?;
            rx.recv().unwrap_or_else(|_| Err(closed()))
        })
    }

    /// Wait until every record queued before this call is written.
    pub(crate) async fn flush(&self) -> Result<(), StateError> {
        let (tx, rx) = oneshot::channel();
        self.enqueue(Item {
            rec: None,
            ack: Ack::Task(tx),
        })
        .await?;
        rx.await.unwrap_or_else(|_| Err(closed())).map(|_| ())
    }

    /// Take no more records, write the queued ones and close the store. Returns
    /// when the store is closed (its lock file is free).
    pub(crate) fn close(&self) {
        {
            let mut q = lock(&self.shared.queue);
            q.closed = true;
        }
        self.shared.work.notify_all();
        self.shared.room.notify_all();
        self.shared.room_task.notify_waiters();
        let writer = lock(&self.writer).take();
        if let Some(w) = writer {
            if off_worker(|| w.join()).is_err() {
                error!("the audit writer ended by a panic: queued records may not be written");
            }
        }
    }
}

impl Drop for Journal {
    fn drop(&mut self) {
        self.close();
    }
}

/// The writer thread: batches until the queue is closed and empty.
fn run(shared: &Shared, mut store: Store<AuditLog>) {
    loop {
        let batch: Vec<Item> = {
            let mut q = lock(&shared.queue);
            while q.items.is_empty() {
                if q.closed {
                    return;
                }
                q = shared.work.wait(q).unwrap_or_else(|p| p.into_inner());
            }
            let n = q.items.len().min(BATCH);
            q.items.drain(..n).collect()
        };
        shared.room.notify_all();
        shared.room_task.notify_waiters();
        #[cfg(test)]
        while shared.held.load(Ordering::SeqCst) {
            std::thread::sleep(std::time::Duration::from_millis(1));
        }

        let mut recs = Vec::with_capacity(batch.len());
        // per item: its place in `recs` (none for a flush), and where its answer goes
        let mut acks = Vec::with_capacity(batch.len());
        for item in batch {
            let at = item.rec.map(|r| {
                recs.push(r);
                recs.len() - 1
            });
            acks.push((at, item.ack));
        }
        let mut answers: Vec<Option<Answer>> = if recs.is_empty() {
            Vec::new()
        } else {
            shared.batches.fetch_add(1, Ordering::Relaxed);
            store.apply_batch(&recs).into_iter().map(Some).collect()
        };
        // readers see the batch before its callers are answered
        {
            let mut v = lock(&shared.view);
            let new = usize::try_from(store.lsn().saturating_sub(v.lsn)).unwrap_or(usize::MAX);
            if new > 0 {
                let recent = &store.state().recent;
                for r in recent.iter().skip(recent.len().saturating_sub(new)) {
                    if v.recent.len() == RECENT {
                        v.recent.pop_front();
                    }
                    v.recent.push_back(r.clone());
                }
                v.lsn = store.lsn();
            }
        }
        for (at, ack) in acks {
            let answer = match at {
                None => Ok(store.lsn()),
                Some(i) => answers
                    .get_mut(i)
                    .and_then(Option::take)
                    .unwrap_or_else(|| Err(closed())),
            };
            match ack {
                Ack::Log => {
                    if let Err(e) = answer {
                        warn!("audit write failed: {e}");
                    }
                }
                // a caller that went away gets no answer; its record is written
                Ack::Thread(tx) => {
                    if tx.try_send(answer).is_err() {
                        warn!("an audit record's caller did not wait for the answer");
                    }
                }
                Ack::Task(tx) => {
                    if tx.send(answer).is_err() {
                        warn!("an audit record's caller did not wait for the answer");
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audit::AuditOp;
    use std::path::{Path, PathBuf};
    use std::time::Duration;

    const KEY: &[u8] = b"journal-test-key";

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("wyrm-journal-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    fn rec(sub: &str, n: u64) -> AuditRecord {
        AuditRecord {
            t: n,
            sub: sub.to_owned(),
            op: AuditOp::Invoke.into(),
            key: "wy/s/downstream/l/~act/a".into(),
            status: 0,
            detail: n.to_string(),
        }
    }

    impl Journal {
        /// Keep the writer from its next batch, or let it go on.
        fn hold(&self, on: bool) {
            self.shared.held.store(on, Ordering::SeqCst);
        }
    }

    fn open(d: &Path) -> Journal {
        Journal::start(Store::open(d, KEY).unwrap()).unwrap()
    }

    fn copy_dir(from: &Path, to: &Path) {
        std::fs::create_dir_all(to).unwrap();
        for e in std::fs::read_dir(from).unwrap() {
            let e = e.unwrap();
            if e.file_name() != "LOCK" {
                std::fs::copy(e.path(), to.join(e.file_name())).unwrap();
            }
        }
    }

    /// N tasks × M records at once: every record is written once, each task's records
    /// in the order it sent them, the chain verifies, and the records shared `fsync`s.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn records_of_many_tasks_keep_their_order_and_the_chain() {
        const TASKS: u64 = 16;
        const EACH: u64 = 200;
        let d = dir("order");
        let j = Arc::new(open(&d));
        let mut tasks = Vec::new();
        for t in 0..TASKS {
            let j = j.clone();
            tasks.push(tokio::spawn(async move {
                let mut lsns = Vec::new();
                for n in 0..EACH {
                    lsns.push(j.write_record(rec(&format!("user:{t}"), n)).await.unwrap());
                }
                lsns
            }));
        }
        let mut all = Vec::new();
        for t in tasks {
            let lsns = t.await.unwrap();
            assert!(lsns.windows(2).all(|w| w[0] < w[1]), "a task's order");
            all.extend(lsns);
        }
        all.sort_unstable();
        assert_eq!(all, (1..=TASKS * EACH).collect::<Vec<_>>());
        assert_eq!(j.lsn(), TASKS * EACH);
        assert!(
            j.batches() < TASKS * EACH,
            "{} batches for {} records",
            j.batches(),
            TASKS * EACH
        );
        // readers see the last records in the order of the journal
        let tail = j.tail(RECENT);
        assert_eq!(tail.len(), RECENT);
        j.close();
        let report = wyrm_state::verify(&d, KEY, None).unwrap();
        assert_eq!(report.records, TASKS * EACH);
        assert!(!report.torn_tail);
        let store = Store::<AuditLog>::open(&d, KEY).unwrap();
        assert_eq!(store.state().count, TASKS * EACH);
        assert_eq!(store.state().recent, tail);
        // per task, the numbers it sent only go up
        let mut last = std::collections::HashMap::new();
        for r in &store.state().recent {
            if let Some(prev) = last.insert(r.sub.clone(), r.t) {
                assert!(prev < r.t, "{}: {prev} before {}", r.sub, r.t);
            }
        }
    }

    /// With the writer held, the queue takes `QUEUE` records and no more: the next
    /// caller waits, and none is dropped.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_full_queue_makes_callers_wait() {
        let d = dir("full");
        let j = Arc::new(open(&d));
        j.hold(true);
        let mut sent = 0u64;
        // the writer may hold one batch it took before the gate
        loop {
            let push = j.push_record(rec("user:a", sent));
            match tokio::time::timeout(Duration::from_millis(200), push).await {
                Ok(r) => {
                    r.unwrap();
                    sent += 1;
                    assert!(sent <= (QUEUE + BATCH) as u64, "the queue has no bound");
                }
                Err(_) => break,
            }
        }
        assert!(sent >= QUEUE as u64, "{sent}");
        assert_eq!(lock(&j.shared.queue).items.len(), QUEUE);
        assert_eq!(j.lsn(), 0, "nothing is written while the writer is held");
        // a caller without async waits too
        let j2 = j.clone();
        let blocked = std::thread::spawn(move || j2.write_blocking(rec("user:b", 0)));
        let waiting = tokio::spawn({
            let j = j.clone();
            async move { j.write_record(rec("user:c", 0)).await }
        });
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(!blocked.is_finished() && !waiting.is_finished());
        j.hold(false);
        waiting.await.unwrap().unwrap();
        tokio::task::spawn_blocking(move || blocked.join().unwrap().unwrap())
            .await
            .unwrap();
        j.flush().await.unwrap();
        assert_eq!(j.lsn(), sent + 2);
        assert!(lock(&j.shared.queue).high <= QUEUE);
        j.close();
        assert_eq!(wyrm_state::verify(&d, KEY, None).unwrap().records, sent + 2);
    }

    /// Close writes everything that was queued, and only then frees the store.
    #[tokio::test]
    async fn close_writes_what_is_queued() {
        let d = dir("close");
        let j = open(&d);
        j.hold(true);
        for n in 0..700 {
            j.push_record(rec("user:a", n)).await.unwrap();
        }
        assert_eq!(j.lsn(), 0);
        j.hold(false);
        j.close();
        // closed: a record is refused, not taken and lost
        assert!(j.push_record(rec("user:a", 700)).await.is_err());
        assert!(j.write_blocking(rec("user:a", 701)).is_err());
        let store = Store::<AuditLog>::open(&d, KEY).unwrap();
        assert_eq!(store.lsn(), 700);
        assert_eq!(store.state().recent.back().unwrap().t, 699);
    }

    /// The same when the journal is dropped with records in the queue.
    #[tokio::test]
    async fn drop_writes_what_is_queued() {
        let d = dir("drop");
        let j = open(&d);
        for n in 0..300 {
            j.push_record(rec("user:a", n)).await.unwrap();
        }
        drop(j);
        assert_eq!(wyrm_state::verify(&d, KEY, None).unwrap().records, 300);
    }

    /// A caller that waited for its record finds it on disk at once: a copy of the
    /// directory taken at the answer (the process "dies" there) holds the record.
    #[tokio::test]
    async fn an_answered_record_is_on_disk() {
        let d = dir("durable");
        let j = Arc::new(open(&d));
        j.hold(true);
        let w = tokio::spawn({
            let j = j.clone();
            async move { j.write_record(rec("user:a", 7)).await }
        });
        tokio::time::sleep(Duration::from_millis(100)).await;
        assert!(!w.is_finished(), "answered before the write");
        j.hold(false);
        assert_eq!(w.await.unwrap().unwrap(), 1);
        let copy = dir("durable-copy");
        copy_dir(&d, &copy);
        let store = Store::<AuditLog>::open(&copy, KEY).unwrap();
        assert_eq!(store.lsn(), 1);
        assert_eq!(store.state().recent.back().unwrap().t, 7);
        // and through the blocking form, from a task of a one-thread runtime
        assert_eq!(j.write_blocking(rec("user:a", 8)).unwrap(), 2);
        assert_eq!(j.tail(1)[0].t, 8);
    }

    /// The blocking form from a worker of a multi-thread runtime and from a plain thread.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn the_blocking_form_works_on_every_kind_of_thread() {
        let d = dir("threads");
        let j = Arc::new(open(&d));
        assert_eq!(j.write_blocking(rec("user:a", 1)).unwrap(), 1);
        let j2 = j.clone();
        let on_worker = tokio::spawn(async move { j2.write_blocking(rec("user:a", 2)) });
        assert_eq!(on_worker.await.unwrap().unwrap(), 2);
        let j2 = j.clone();
        let plain = std::thread::spawn(move || j2.write_blocking(rec("user:a", 3)));
        let lsn = tokio::task::spawn_blocking(move || plain.join().unwrap())
            .await
            .unwrap();
        assert_eq!(lsn.unwrap(), 3);
    }

    /// A write that fails is answered as failed to the caller that waits.
    #[tokio::test]
    async fn a_failed_write_is_answered_as_failed() {
        let d = dir("failed");
        let heads = dir("failed-heads");
        std::fs::create_dir_all(&heads).unwrap();
        let store = Store::<AuditLog>::open(&d, KEY)
            .unwrap()
            .with_anchor(heads.join("audit.head"))
            .unwrap();
        let j = Journal::start(store).unwrap();
        assert_eq!(j.write_record(rec("user:a", 1)).await.unwrap(), 1);
        // the anchor's medium goes away: the head can no longer be kept
        std::fs::remove_dir_all(&heads).unwrap();
        assert!(j.write_record(rec("user:a", 2)).await.is_err());
        assert!(j.write_record(rec("user:a", 3)).await.is_err());
        // it is back: the journal goes on
        std::fs::create_dir_all(&heads).unwrap();
        assert!(j.write_record(rec("user:a", 4)).await.is_ok());
    }
}
