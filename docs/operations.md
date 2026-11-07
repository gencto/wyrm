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

### Warm standby (ADR 0036, option 3, stage A)

Two brokers of one site on two hosts, one active, one following. The
standby copies the control plane (the registry, flow definitions, gateway
users), `secrets.bin`, the link tokens, the links' private data (the
sealed stores of the scheduler, alarm, DQL and uplink links, runtime edits
of drivers, the agent's store), the installed packages and the broker
storage and the historian's rows as they change, and takes over when
the active is away. It runs no router and polls no device until then.
What it does not copy: files over 64 MiB in a link's data or a package
(they are logged and skipped), and the audit journal (it stays on the
host that wrote it).

Set it up once:

1. Both `wyrmd.json5` files are the same but for the addresses, and both
   have a QUIC peer listener and a `standby` section naming the other host
   (`tls_names` must contain the host name or address the other side uses):
   ```json5
   peers: { listen: "quic/0.0.0.0:7449" },
   // host A
   standby: { peer: "quic/10.0.0.2:7449", takeover_s: 10, primary: true,
              witness: ["10.0.0.254:443", "10.0.1.10:502"] },
   // host B
   standby: { peer: "quic/10.0.0.1:7449", takeover_s: 10, primary: false,
              witness: ["10.0.0.254:443", "10.0.1.10:502"] },
   ```
   `primary: true` on one host only: it takes over after `takeover_s`,
   the other after three times that, and when both are active after a
   network split, the other steps down.

   `witness` is required: TCP addresses on the plant network that each
   host must reach to be active, typically the network gateway and one or
   two PLCs the site polls (any port that accepts a connection: 443 of a
   router, 502 of a Modbus device). Any one answering is enough. A host
   that reaches none of them is the side that is cut off: it does not take
   over, and an active broker that reaches none and no longer hears its
   standby steps down after half of `takeover_s`, before the other side
   can take over. Keep `takeover_s` at 10 or more, so that both sides see
   the split in time. List more than one witness: if every witness is down
   while the standby is down too, the active steps down and the site has
   no broker until a witness answers again.

   A witness cannot tell a host whether the other host is active. When
   both hosts reach a witness but not each other (a firewall between
   them, a hung process), both would be active. Add a lease arbiter on a
   third host to close that case (section "Lease arbiter" below):
   ```json5
   standby: { peer: "quic/10.0.0.2:7449", takeover_s: 10, primary: true,
              witness: ["10.0.0.254:443"], arbiter: ["10.0.0.3:7450"] },
   ```
   Without `arbiter` the broker logs a warning at start.
2. On the broker that has run (host A), export the site's keys with a
   passphrase of at least 12 characters, and carry the file to host B:
   ```bash
   WYRM_KEYS_PASSPHRASE='…' wyrmd -c wyrmd.json5 keys export site-keys.wykb
   ```
3. On host B, with an empty `data_dir`:
   ```bash
   WYRM_KEYS_PASSPHRASE='…' wyrmd -c wyrmd.json5 keys import site-keys.wykb
   ```
   then delete the file on both hosts: it is the site.
4. Start `wyrmd` on host B as on host A (section 2). It logs
   `standby: following`; host A shows `sys/standby_connected` 1 and
   `sys/standby_lag` 0 once it has caught up.

What happens at a failover: host A goes; after `takeover_s` (three
times that for a host that is not primary), and while a witness answers,
host B logs `standby: promoted`, opens the broker on the followed
`data_dir`, and the links, gateway clients and upstream brokers that know
both addresses (section "Several endpoints") come to it.

There is no automatic failback. When host A comes back it finds host B
active, follows it (`standby: following`) and stays the standby, primary
or not: a switch back would cost another gap. To make host A active
again, stop `wyrmd` on host B at a quiet moment; host A takes over after
`takeover_s` and host B, started again, follows it.

The primary rule matters only when both hosts became active across a split
that has healed: the one that is not primary sees the primary's broker
token, steps down and follows it. What it wrote while it was active is
moved aside on that host, not merged:
- registry, flow and user records: as `state.stale.<n>` (and
  `flows/state.stale.<n>`, `gateway/users.stale.<n>`);
- files the active does not hold or holds otherwise (sealed stores of the
  scheduler, alarm, DQL and uplink links, driver edits, packages): into
  `standby/stale/<t_ms>/files/`;
- a broker storage tree that differs from the active's: exported as
  `standby/stale/<t_ms>/storage.json` (the format of the storage's
  `export` action, for `import`).

The active writes one audit record `standby_forked` per set (the detail
names the place on the other host) and counts them in
`sys/standby_forks`. A value above 0 means: look at what the other host
moved aside, and enter again what must stay.

History-sync links (ADR 0026) go on from where they were after a
failover: the standby carries each sink's confirmed cursor over in its own
journal numbers. A sink sends again at most the last page it had not
confirmed (≤ 2 000 rows); the targets replace on `(key, t)`. A former
active whose sinks had not confirmed all of its own rows keeps their
cursors until it is active again: then it sends those rows, and the rows
it copied after them, again.

A router rebuild on the active (a link installed, a peer added, new
signing keys) closes its listeners for a moment; the active first tells
its standby to wait (up to 60 s, released as soon as the router is up),
so a rebuild never looks like a failure. With a standby connected each
rebuild starts 2.5 s later, for the standby to read that.

Each change of role is an audit record by `system`: `promoted`, or
`demoted` with the reason (the primary is back; cut off; another broker
holds the arbiters' lease; the lease ran out and the standby is quiet).

#### Lease arbiter

An arbiter is `wyrmd` in a mode of its own on a third host (any small
machine on the network of both brokers: the upstream site's host, a
gateway PC). It holds one lease per site in memory and grants it to one
broker at a time:
- the standby takes over only once a majority of `standby.arbiter` grants
  it the lease, so a running active keeps the role however the two hosts
  see each other;
- the active renews the lease every second; told that another host holds
  it, it steps down at once; when it cannot reach the arbiters, it runs
  on while its standby still follows it, and steps down when the lease
  has run out and the standby is quiet;
- the lease lasts half of `takeover_s` (3 s at least, 30 s at most); a
  started arbiter grants nothing for 30 s, since a lease it forgot may
  still run on a broker.

Set it up:
1. On a broker of the pair, write the arbiter's files (the site CA, a
   certificate `arbiter:<site>` for the address the brokers dial, the site
   name):
   ```bash
   wyrmd -c wyrmd.json5 arbiter issue --host 10.0.0.3 --out arbiter-demo
   ```
2. Copy the directory to the third host and run the arbiter under a
   supervisor, as `wyrmd` itself:
   ```bash
   wyrmd arbiter serve --dir arbiter-demo --listen 0.0.0.0:7450
   ```
3. Add `arbiter: ["10.0.0.3:7450"]` to the `standby` section on both
   hosts and start them again, one after the other.

The arbiter checks that a broker's certificate is `standby:<site>` from
the site's CA; nobody else (links, downstream brokers) can take the
lease. Its directory holds no private key of the site, only its own.

Caution: one arbiter is a single point: when it is down while the
standby is down too, the active steps down. Run three arbiters on three
hosts for a site that must ride out that (a majority of two decides).
With one arbiter down the pair keeps working, and a failover still needs
a majority.

Rules of thumb:
- Keep the two `wyrmd.json5` files the same. A link named in host A's
  `links` and not in host B's is gone after a failover.
- The standby's `data_dir` is as sensitive as the active's: it holds the
  site's keys.
- The standby follows asynchronously: the operation made in the second the
  active died may be lost; the administrator sees it missing.
- The links the broker supervises (`mode: "process"`) die with it and are
  started again by the new active; links run by hand and external links
  need both addresses in `WYRM_ENDPOINT`.
- With `state_anchor_dir` on the standby, the follower keeps the anchors
  at its head; a history that forked (a record the standby never got) is
  moved aside as `state.stale.<n>` and copied again from the active.

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
