# Operations: run, restart, back up and restore a broker

This page is for whoever keeps a `wyrmd` running: how to run it under a
supervisor, what a restart recovers on its own and how long that takes, and
what to copy for a backup. Design: ADR 0003 (the broker owns only itself),
ADR 0036 (fault tolerance; this page is its option 1, "supervised restart").

## 1. What a restart recovers

A broker that stops, for any reason, and starts again comes back whole from
its `data_dir` and from its links:

| What | Where it comes from after a start | Lost by a kill (SIGKILL, power) |
|---|---|---|
| Links, ACL, PKI, tokens, peers, profiles, flow definitions, users, history settings | the control-plane WAL (`state/`, `flows/`, `gateway/`, `audit/`), every append `fsync`ed; a snapshot only speeds the start up | nothing; a record cut off at the end (a crash while it was written) is dropped, `wyrmd verify` shows it as a torn last record |
| The node tree and `~val` | the links: each one re-declares its subtree and its last values when it sees the broker's liveliness token `wy/<site>/sys/broker` again | nothing; values are back as soon as each link polls again |
| Values of `storage`, scheduler events, alarm records, DQL queries, uplinks, runtime edits of drivers | their redb files and sealed stores in `data_dir` (every write is synced) | nothing |
| History rows | `history/days/*.redb` | the rows still in the write buffer: up to `buffer_flush_time` of each watch group (5 s by default) |
| Gateway sessions | nothing: users log in again (the explorer's client reconnects and reopens its streams) | all |
| A `set` or an action in flight | nothing: the caller gets an error and repeats it | that one request |
| The audit journal | `audit/` | nothing already written; records a link put while the broker was away are not sent again (ADR 0029, decision 7) |

So the broker needs no cluster to survive its own crash: it needs to be
started again, quickly, with the same `data_dir`. That is the supervisor's
job.

## 2. Run under a supervisor

### systemd

```ini
# /etc/systemd/system/wyrmd.service
[Unit]
Description=WYRM broker
After=network-online.target
Wants=network-online.target

[Service]
User=wyrm
Group=wyrm
ExecStart=/usr/local/bin/wyrmd -c /etc/wyrm/wyrmd.json5
WorkingDirectory=/var/lib/wyrm
# First start only: creates the gateway's first admin; remove the file after.
EnvironmentFile=-/etc/wyrm/first-admin.env
# A crash, a kill or an exit code: start again after one second.
Restart=always
RestartSec=1
# SIGTERM ends the broker cleanly (history flushed, links told to stop);
# the process links are in the same control group and die with it.
KillSignal=SIGTERM
KillMode=control-group
TimeoutStopSec=20
LimitNOFILE=16384
# data_dir holds the keys of the site: nobody else reads it.
UMask=0077
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/wyrm
PrivateTmp=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
```

Notes:
- `wyrmd` stops cleanly on SIGINT and SIGTERM. A clean stop flushes the
  historian's buffers and gives each process link its SIGTERM (10 s, then
  a kill). A process link whose broker vanished without a signal sees its
  parent go and exits by itself within a second, so a `KillMode` of
  `control-group` is a belt on top of braces.
- `Restart=always` with `RestartSec=1`: the broker refuses to start on a
  bad configuration or a port in use, and systemd will then retry for ever
  at that pace; `StartLimitIntervalSec`/`StartLimitBurst` in `[Unit]` stop
  that if you prefer a loud failure. `wyrmd -c … check` validates a
  configuration before a restart.
- `WYRM_GATEWAY_ADMIN_PASSWORD` is read once and cleared from the process
  environment; the file it came from is still on disk, so delete it after
  the first start (`EnvironmentFile=-` tolerates a missing file).
- A listener port still held by something else ends the broker with that
  error (Zenoh tries a listener once); with `Restart=always` the next
  attempt comes a second later, which covers a port the kernel releases
  late after a kill. A port held by another program stays an error in the
  journal.
- `wyrmd` as a container: one container per broker, `data_dir` on a volume,
  `restart: unless-stopped` (compose) or a restart policy of the orchestrator,
  `stop_grace_period` of 20 s so SIGTERM has time to flush. The process
  links run inside the same container.

### Recovery time

The recovery time (RTO) of a restart is the sum of:

1. the supervisor's delay (`RestartSec`);
2. the router build: the state is read from the snapshot and the WAL tail,
   the ACL generated, the listeners opened — one to three seconds;
3. embedded links: started at once with the router;
4. process links: spawned by the supervisor after the router is up, each
   opens its mTLS session and sends `hello`; `hello` is retried with a
   back-off of 1 s, ×2, capped at 5 s, which matters only for a link that
   starts before the broker answers (a link under its own supervisor, or on
   another host);
5. the first poll of every device, at that device's poll rate.

The e2e test `broker_restart_rto` measures 2–5 for one embedded and one
process mock link: a real `wyrmd` process is killed with SIGKILL and started
again at once; the clock stops when both links show `state` connected in
`sys/links` and each has published a live sample to a subscriber opened
after the restart. It also prints the resident memory of a broker that runs
no link. Run it on the target hardware:

```bash
cargo test --release -p wyrmd --test e2e broker_restart_rto -- --nocapture
```

Measured figures live in `docs/backlog.md` item 13 beside the `wyr bench`
numbers (first figure: 1.6 s from the start command to both links live, in
a debug build on an x86_64 container). Without a figure from the reference
board (4-core ARM64, 2 GB) assume ten seconds for the broker and add the
slowest device's poll period.

### Several endpoints (ADR 0036, option 2)

A client or a link may name several broker endpoints, comma-separated, in
the order to try. Today a site has one broker, so the list is the one
broker's addresses; with a standby broker (option 3, not built yet) it is
both brokers, and nothing on the client side changes at a failover.

- `wyr --connect tls/a:7448,tls/b:7448`, `wyrm_open("tcp/…,tcp/…")` in the
  C API and Dart FFI: Zenoh's client mode connects to the first endpoint it
  reaches and tries the list again when the connection drops.
- Links run by hand (external links, a package on another host):
  `WYRM_ENDPOINT` takes the list. The link opens one session per endpoint
  and serves a router only while the site's broker is behind it, told by
  the liveliness token `wy/<site>/sys/broker`: a router without the token,
  or whose token has been gone for `WYRM_BROKER_WAIT_S` (15 s), is left for
  the next endpoint. The token is one key, so two brokers that claim one
  site are never both served by a link. Links the broker supervises get
  the broker's own endpoint and die with it, so they need no list.
- Gateway clients: the Dart `WyrmGateway.loginAny([url1, url2], …)` logs
  in on the first gateway that answers and keeps the credentials, so its
  `client()` logs in again on the next gateway when the one in use is gone
  or does not know the session (each broker holds its own sessions).

### Several sites

A site does not depend on its upstream: it keeps polling, recording and
alarming while the upstream is away, and the upstream catches up through the
history and alarm sinks (`next {after, max}`) when the link is back. A
restart of the upstream therefore costs the downstream nothing but a gap in
what the upstream saw live. The same holds the other way round: the upstream
shows the downstream site as not connected and serves everything else.

## 3. Back up and restore

Everything the broker owns is under `data_dir`. What cannot be regenerated:

| Path | What it is | Without it |
|---|---|---|
| `state/`, `state.key` | the control-plane WAL and the key of its HMAC chain | no links, ACL, peers, tokens, history settings; the WAL of a backup is refused with another `state.key` |
| `pki/` | the site CA and its key, the broker's certificates | every link, operator, downstream broker and process link needs a new certificate; upstreams must trust the new CA |
| `secrets.bin`, `secrets.key` | link secrets, store keys of every link, the keys of sealed peers | links lose their credentials; the sealed stores of links and runtime driver edits cannot be opened |
| `gateway/` | users, roles, the gateway's signing key | users gone; whoever holds `gateway.key` is an administrator, so the backup is as sensitive as `data_dir` |
| `flows/`, `flows.key` | flow definitions and their signing key | flows gone |
| `links/<id>/` | each link's certificate, token and private data (`data/`: runtime edits, portable stores) | the link starts from its registry parameters |
| `history/`, `storage/` | the historian's day files and index, broker storage | history and stored values gone |
| `audit/` | the audit journal | the record of who did what |
| `packages/`, `peers/`, `operators/` | installed link packages, certificates issued for downstream brokers, operator certificates | reinstall, reissue |

How to take a backup:
- **Stopped broker (simplest, consistent).** `systemctl stop wyrmd`, copy
  `data_dir` whole, keep its modes (`cp -a`, `tar --same-permissions`), start
  again. `wyrmd -c … verify` on the copy checks the WALs (CRC, HMAC chain,
  anchors) offline.
- **Running broker.** Take a filesystem snapshot (LVM, btrfs, ZFS, a cloud
  volume snapshot) and copy from the snapshot. The WALs are append-only and
  a torn last record is dropped at open; the redb files are transactional and
  a snapshot sees a committed state. A plain `cp` of a running `data_dir`
  may copy a redb file in the middle of a write: do not restore from such a
  copy without `verify` and a look at the history.
- The backup holds the site's keys: encrypt it and keep it where only the
  broker's administrators can read it.

How to restore:
1. Stop the broker; move the damaged `data_dir` aside.
2. Copy the backup to the configured `data_dir`, owner the broker's user,
   mode 0700 for the directory and the key files.
3. `wyrmd -c … verify`. With `state_anchor_dir` set (the WAL head anchors on
   another medium), a backup older than the anchors is refused at start as a
   rolled-back WAL, which is what the anchors are for; if the older state is
   what you want, run `wyrmd -c … init-anchors` once, with the broker
   stopped, on a store you trust.
4. Start the broker. Links that were installed after the backup are not in
   the registry and do not come back: the links re-declare only what the
   registry starts. Runtime driver edits made after the backup are gone with
   `links/<id>/data`.

What a backup does not replace: a second host that holds the same keys and
follows the WAL while the first one runs. That is option 3 of ADR 0036, the
warm standby, which is not built yet.

## 4. Checks

- `wyrmd -c … check`: the configuration parses and validates; exit code 1
  otherwise. Run it before a restart with a changed file.
- `wyrmd -c … verify`: every control-plane store offline (broker stopped).
- Running: `wy/<site>/sys/uptime`, `links_total`, `links_connected`,
  `quarantined`, `acl_denied`, `cpu`, `memory`, `disk_free`, `data_size`
  (`wyr list wy/<site>/sys`), `sys/links/<id>/state` and `error` per link,
  `sys/history/disk_space_remaining`. The liveliness token
  `wy/<site>/sys/broker` is what links and peers watch; a monitor can watch
  it too (`wyr sub`).
- `sys/~act/get_log` and per-link `get_log` hold the recent log ring; the
  level is `sys/log_level` (`RUST_LOG` at start).
