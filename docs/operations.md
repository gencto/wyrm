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
| The audit journal | `audit/` | nothing already written; a link's records that the broker had received and not yet written (at most 1024, about one `fsync` of time); records a link put while the broker was away are not sent again (ADR 0029, decision 7) |

**The audit journal: what is durable when.** One thread writes the journal.
It takes the records that wait (at most 256) and writes them as one batch:
one write, one `fsync`, then the anchor (`state_anchor_dir`). The records,
their order, their CRC and their HMAC chain are the ones a write per record
makes; only the number of `fsync`s differs.

- A record the broker makes itself (an admin action, a login, a change of
  role, an update: everything but the next item) is on disk before the
  operation goes on. The caller waits for the `fsync` that covers its record;
  a failed write is logged as `audit write failed`.
- A record a link reports for its own `set`/`invoke` was never acknowledged:
  the link puts it after the command and does not wait (ADR 0029, decision
  7). The broker queues it in the order it arrived and writes it with the
  next batch. A failed write is logged.
- The queue holds 1024 records. When it is full, who adds a record waits;
  nothing is dropped to make room. (The limit of 50 records per second for a
  link over the network, ADR 0031 ADM-3, is apart and is itself audited as
  `audit_dropped`.)
- A stop (SIGTERM) writes the whole queue before the store closes. A kill
  loses only link records that were still in the queue.
- With `state_anchor_dir`, a batch of two or more records first writes the
  anchor as `<lsn> <mac> +<n>`: "`n` records follow this head". After the
  batch the anchor is the plain head again. A start after a kill inside a
  batch finds that announcement and accepts any whole prefix of the batch;
  no caller had an answer for those records. Without the announcement the
  rule is as before: at most one record after the anchor.
- **While the broker's own update is in its trial** (`update.json` says
  `trial`, §2: from the moment the update is staged until
  `update_confirmed`), the journal writes record by record: one write, one
  `fsync`, the anchor at the plain head, exactly as every earlier version
  did. A kill in a trial is followed by the previous version (the guard goes
  back), and that version must open what this one left; a version from
  before group commit does not read an announcement. So in a trial the
  files never hold one. This is a rule, not a case for one version: what a
  version in its trial leaves on disk is what the version before it opens.
  The journal takes about one `fsync` per record for those minutes (the
  rate of before); after the confirmation it writes batches again. The
  same holds from the moment `rollback_update` is asked for a confirmed
  update (`update.json` names who asked): the guard starts the previous
  version next, however this process ends. The action answers only after
  the switch holds: a batch that was being written is on disk and the
  anchor is the plain head.
- A downgrade by hand, outside a trial, to a version from before group
  commit: stop the broker first (a stop leaves the plain head). Only after
  a kill inside a batch can such a version refuse the anchor (`records
  behind the WAL`): start the newer version once, or run `wyrmd verify`
  and then `wyrmd init-anchors`.
- A write to a control-plane WAL that fails (all stores: registry, flows,
  users, audit) leaves no bytes behind: the file is cut back to the length
  it had, and the store goes on. If the cut fails too, or if it was the
  `fsync` that failed (what the disk holds is then not known), the store
  takes no more writes until the broker starts again: every later change
  is refused with `the store takes no more writes until it is opened
  again`, an audit record is logged as `audit write failed`. A start reads
  the file, drops a torn record and goes on. Nothing is appended after
  bytes the store does not know (before: the next record followed them,
  and the next start read a broken log).
- If the journal's writer thread ever ends by a panic, the queue is closed:
  every caller that waits, and every later one, gets an error (logged as
  `audit write failed`); nobody waits for ever. The broker's operations go
  on unaudited until a restart, and the log says so (`the audit writer
  ended by a panic`).

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
- `data_dir` must belong to the user the broker runs as. The broker makes
  it 0700 when `wyrmd keys import` writes `state.key` and the other key
  files into it, and a standby does the same when it copies `secrets.bin`
  and the replicated files; `data_dir/pki`, `links/<id>`, `links/<id>/data`,
  `operators`, the backups' and restore points' directories are made 0700
  too. Each of them must be a real directory owned by that user: one that
  is a symlink (below `data_dir`), or that another user owns, is refused
  with its path, and the broker does not write keys into it. `data_dir`
  itself may be a symlink the operator set up (`/var/lib/wyrm` →
  `/srv/wyrm`).
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

### Gateway TLS from the site CA (ADR 0051 §3)

A gateway that listens beyond loopback needs TLS. Without a certificate of
your own, let the broker issue one from its site CA:

```json5
gateway: { listen: "0.0.0.0:8445", tls: "site_ca" },
```

- At each start, before the gateway opens, the broker asks its site CA
  (`data_dir/pki`, made on the first start) for a server certificate with
  CN `gateway:<site>` and writes it to `data_dir/gateway/tls.pem` and
  `tls.key` (0600).
- The certificate names `<hostname>.local`, `wyrm-<site>.local` (the name
  the DNS-SD announce gives) and the addresses clients use: every
  non-loopback address of the host (IPv4, and IPv6 except link-local) when
  `listen` is `0.0.0.0` or `[::]`, else only the listen address. The host
  name is cut at its first dot; a host whose name cannot be read uses
  `wyrm-<site>`. While the host has no usable address (before DHCP), the
  certificate names only the `.local` names; it is issued again when an
  address comes.
- A restart keeps the certificate as it is while it names exactly the same
  names and has more than 30 days left; otherwise the broker issues a new
  one from the same CA. A certificate that names more (an address the host
  no longer has) is issued again too. Clients pin the CA, not the
  certificate, so a new one needs nothing on their side.
- While the gateway serves, the broker reads the host's addresses every
  30 s. When the names differ from the names of the certificate it serves
  (an address from DHCP after the start, a new or lost address), or that
  certificate has less than 30 days left, it issues a certificate for the
  names and serves it from the next connection on, without a restart. A key
  that is not the certificate's (a power cut between the two writes) also
  makes a new pair. Open connections keep the old one. The log says
  `gateway: certificate issued for <n> names`. `GET /api/info` `names` and
  the device-key origins follow the new certificate at the same time.
- Clients trust `data_dir/pki/ca.pem`. `ca_fp` in `GET /api/info`, the
  `fp` key of the DNS-SD announce and `wyrmd ca fingerprint` are the code
  of that CA.
- Files of your own (`tls_cert`/`tls_key`) are read at the start and again
  at each router rebuild (an ACL change): a renewed pair is served from
  then on. A pair that cannot be read or does not match leaves the
  certificate in force, with a warning in the log.
- `tls` excludes `tls_cert`/`tls_key`. A certificate from a public CA (for
  the remote MCP connector, [claude.md](claude.md)) still goes in
  `tls_cert`/`tls_key`.

### First admin from a setup code (ADR 0051 §3)

A broker made from an image carries no password. Its first admin comes
from a one-time setup code; the image holds only the code's hash.

1. Make a code on any machine: `wyrmd setup-code`. It prints the code on
   the first line (`ABCD-EFGH-…`, 26 base32 characters) and its hash (64
   hex digits) on the second. It needs no `wyrmd.json5`.
2. Write the hash line into a file and name it in the configuration:

   ```json5
   gateway: { listen: "0.0.0.0:8445", tls: "site_ca", setup_file: "/etc/wyrm/setup" },
   ```

3. Give the code to the person who sets the broker up, apart from the
   image. Keep it secret: whoever has it makes the first admin.
4. Start the broker. While no user exists, it moves the hash into
   `data_dir/gateway/setup.hash` (0600) and deletes `setup_file`. The log
   says `gateway: setup code taken in`.
5. The person opens Studio. `GET /api/info` shows `setup: true`, and Studio
   asks for the code, an admin name and a password
   (`POST /api/setup {code, user, password}`). The right code makes that
   admin, and the setup is over: the code cannot be used again.

- The code may be typed in lower case, with spaces or `-` between the
  groups, or with none.
- Wrong codes count against the failed-login limits, as wrong passwords
  do: 5 failures per 60 s for one user name from one address, and 20
  failures per 60 s from one address over all user names (an IPv6 address
  counts by its /64). Logins and setup attempts share both budgets; past
  them the gateway answers `429`. They are audited as
  failed logins with the reason `setup_code_wrong`; the first admin as a
  user added by `setup`. Neither the code nor its hash is logged.
- Once a user exists, a setup is void. A `setup_file` is then ignored and
  deleted, and a `setup.hash` (a restored backup, a crash between the new
  admin and the removal) is deleted at the next start. `/api/setup`
  answers `409 no_setup`.
- A `setup_file` that is not 64 hex digits (white space around them aside)
  stays where it is, with a warning in the log that names it. A
  `setup_file` that cannot be deleted is a warning too; it is void once a
  user exists.
- A damaged `data_dir/gateway/setup.hash` with no user is logged at start
  with its path and reason, and `/api/info` shows no `setup`. To recover,
  stop the broker, make a new code with `wyrmd setup-code`, write its hash
  into `setup_file`, and start again: the new hash replaces the damaged
  file.
- `WYRM_GATEWAY_ADMIN_PASSWORD` still works. When it creates an admin, a
  setup file of the same start is void.
- A warm standby (ADR 0036) does not receive `data_dir/gateway/setup.hash`:
  a pending setup belongs to its host. Make each host of a pair from an
  image with its own `setup_file`. Users replicate, so once the first admin
  exists on the active, the setup of the other host is void (it is dropped
  at its next start, as above).

### Seed packages (ADR 0051 §1)

A broker made from an image can install link packages on its first start.
The image cannot put them into `data_dir/packages`: `data_dir` is made at
the first start, and the broker removes a package directory that its
registry does not know. So the image carries the packages in a read-only
directory with a list:

```json5
packages: { seed_dir: "/usr/share/wyrm/seed" },
```

`/usr/share/wyrm/seed/seed.json`:

```json
{
  "format": "wyrm-seed/1",
  "links": [
    { "link": "modbus", "file": "modbus.zip", "accept": true },
    { "link": "mqtt", "file": "mqtt.zip" }
  ]
}
```

- `format` must be `wyrm-seed/1`. An unknown field is an error. `link` is
  the id of the new link. `file` is a package zip (as for `install_zip`) in the
  same directory. `accept` (default `false`) is the
  *Accept requested rights* of `install_zip`: without it, a package that
  asks for a network allowlist or grants is not installed.
- `file` is a plain name: no `/` or `\`, no leading `.`, not empty. The
  broker opens it without following a symlink. The seed directory itself
  may be a symlink. A zip is bounded as for `install_zip` (64 MiB).
- On the first start, once the router listens, the broker installs each
  entry as `sys/links ▸ install_zip` does, with the same checks, as the
  subject `broker:seed` (in the audit journal). An entry whose link exists
  already (a restored backup) is skipped before its file is read: the seed
  never changes that link or updates its package. A new link of a package
  that is installed at another version is an update, as with
  `install_zip`: the package moves to the seed's version, with every link
  that runs it ([links.md](links.md) §5a).
- One entry that fails does not stop the others. When every entry was
  tried, the broker writes `data_dir/seed.done` (0600, written whole) and
  never runs the seed again. The file holds the time and, per link, `ok`,
  `skipped: the link exists`, `started and not finished: …` (below), or
  the message of the failure. The log says `seed: link <id> installed`,
  `… skipped (exists)`, or a warning with the message.
- The seed runs at the first start that finds `seed.json` and no
  `seed.done`. Normally that is the first start. A broker that has run
  for a long time without a seed (a `seed_dir` with no `seed.json`) also
  installs the links of a `seed.json` that an image update adds, at its
  next start.
- To run the seed again, delete both `data_dir/seed.done` and
  `data_dir/seed.progress.json` and restart. Links that exist are skipped,
  failed entries are tried again. With `seed.progress.json` left in place,
  entries that have an outcome in it are not tried again.
- Each install is one operation of its own: a router rebuild (an ACL
  change, a process link that the seed installed) waits for the install in
  progress, not for the whole seed. While a rebuild holds the broker, the
  seed waits (up to 60 s). If the broker closes meanwhile, the seed stops
  without `seed.done` and goes on when the admin starts again.
- `data_dir/seed.progress.json` (written whole) records, per link, when its
  install started and its outcome; it goes when `seed.done` is written. A
  run that stops before `seed.done` (a rebuild, a stop, a power cut) goes
  on at the next start from this file:
  - an entry with an outcome keeps it and is not tried again;
  - an entry that started and has no outcome was cut short during its
    install. Its link or package may be half made (a link without its
    grants). The broker logs a warning, writes `started and not finished: …`
    in `seed.done` and does not install it again. Check the link and its
    package: install it again with `install_zip`, or remove it;
  - the other entries are tried.
- A warm standby (ADR 0036) receives `seed.done` and `seed.progress.json`
  with the other replicated files. A promoted standby never runs a
  finished seed again, so links that the operator removed do not come back;
  an unfinished seed goes on where the active stopped. The standby copies
  the files and the registry WAL in separate polls, so the two can differ
  by a poll at a failover. A link the active was installing just before
  the failover can then show as `skipped: the link exists` (the registry
  has the link, the copied progress file does not) or as `started and not
  finished` on the promoted host. Check such a link as above.
- An entry whose install succeeded but whose outcome could not be written
  to `seed.progress.json` (a full disk) shows as `started and not finished`
  at the next run. The link is there; check it as above.
- A `seed.json` that is missing or cannot be read (bad JSON, another
  `format`, a link listed twice, more than 256 links) installs nothing and
  writes no `seed.done`. The broker logs a warning and tries again at every
  start. A `seed.progress.json` that cannot be read does the same.

### Recovery time

The recovery time (RTO) of a restart is the sum of:

1. the supervisor's delay (`RestartSec`);
2. the router build: the state is read from the snapshot and the WAL tail,
   the ACL generated, the listeners opened — one to three seconds;
3. embedded links: started at once with the router;
4. process links: spawned by the supervisor when the admin attaches, which
   is before the listeners open, so a link's first connect is usually
   refused (one `cannot connect` warning per start) and its next one comes
   1 s later; then it opens its mTLS session and sends `hello`. A refused
   connect and `hello` are retried with a back-off of 1 s, ×2, capped at
   5 s, which matters more for a link that starts before the broker
   answers (a link under its own supervisor, or on another host);
5. the first poll of every device, at that device's poll rate.

The e2e test `broker_restart_rto` measures 2–5 for one embedded and one
process mock link: a real `wyrmd` process is killed with SIGKILL and started
again at once; the clock stops when both links show `state` connected in
`sys/links` and each has published a live sample to a subscriber opened
after the restart. It also prints the resident memory of a broker that runs
no link. A failed wait names its phase (first start or start after
SIGKILL) and shows what the test's session and a new session see, the link
processes and the last output of the link process. Run it on the target
hardware:

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
broker's addresses; with a standby broker (option 3, "Warm standby"
below) it is both brokers, and nothing on the client side changes at a
failover.

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

### Warm standby (ADR 0036, option 3)

Two brokers of one site on two hosts, one active, one following. The
standby copies the control plane (the registry, flow definitions, gateway
users), `secrets.bin`, the link tokens, the links' private data (the
sealed stores of the scheduler, alarm, DQL and uplink links, runtime edits
of drivers, the agent's store), the installed packages, the seed's
`seed.done` and `seed.progress.json`, and the broker storage and the
historian's rows as they change, and takes over when
the active is away. It runs no router and polls no device until then.
What it does not copy: files over 64 MiB in a link's data or a package
(they are logged and skipped), the audit journal (it stays on the
host that wrote it), and a pending setup code (`gateway/setup.hash`,
"First admin from a setup code" above).

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
the site's CA, and the brokers check that the arbiter's is
`arbiter:<site>`; nobody else (links, downstream brokers) can take or
grant the lease. Its directory holds no private key of the site, only its
own; its certificate lasts 20 years. The active shows the seconds left of
its lease as `sys/arbiter_lease_s` (0: none) and logs a warning when no
arbiter answers.

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

### A broker that updates itself (ADR 0048 §2)

By default a broker is updated by hand: replace the binary, restart
(`updates.mode: "off"`). Two other modes are set on the host, in
`wyrmd.json5`:

```json5
updates: {
  mode: "self",                       // "off" (default), "external", "self"
  channel: "https://…/releases.json", // the signed channel file; optional for "self"
  keys: ["<Ed25519 public key, hex>"],// release keys trusted besides the built-in ones
  trial_s: 180,                       // 10 to 3600: how long a new version has to prove itself
  keep_days: 7,                       // 1 to 90: how long a confirmed update can be rolled back
}
```

- `external` (a container, a distribution package): the broker reads the
  index and shows `sys/latest`, `sys/update_available` and, in
  `sys/update_hint`, what to run. It never replaces itself: `update` is
  refused with that text. Change the image tag where the container is
  defined and run `docker compose pull && docker compose up -d`, or install
  the new package and `systemctl restart wyrmd`. Make a backup first
  (section 3).
- `self`: `sys/~act/update` replaces the broker and takes the new version
  back when it does not prove itself. It needs the layout and the unit
  below. Linux and macOS only.

`updates.channel` is a public URL: `https://` (plain `http://` only to a
loopback address, for a mirror on the broker host). A URL with a user or
password, a query string or a fragment is refused when the configuration
is read: the channel is shown in `sys` and in the config copy of a
backup, so it must hold no credential. A private mirror is reached
through the network (a VPN, a mirror on the plant network), not through a
token in the URL.

The release key: this version of `wyrmd` has **no built-in release key**.
A broker trusts only the keys in `updates.keys`; with none, every update
is refused. `packaging/wyrmd/README.md` says how a key is made.

#### Layout and unit

```
/opt/wyrm/versions/0.1.0/wyrmd       one directory per version
/opt/wyrm/versions/0.2.0/release.json, release.sig   the signed release a version came from
/opt/wyrm/current -> versions/0.1.0  a symbolic link, switched by one rename
/opt/wyrm/bin/wyrmd-guard            a copy of the previous version's binary
/opt/wyrm/bin/trusted.json           versions put there by hand, with the SHA-256 of each binary
```

1. As root, make the layout from the binary you have:
   `wyrmd install-layout /opt/wyrm`. It prints the unit lines and names
   that binary in `bin/trusted.json`.
2. Set the owners. The broker writes new versions and switches `current`;
   it must not be able to change the guard:
   ```bash
   chown root:wyrm /opt/wyrm && chmod 1775 /opt/wyrm     # sticky: the broker cannot move bin/ away
   chown -R root:root /opt/wyrm/bin && chmod 755 /opt/wyrm/bin
   chown -R wyrm:wyrm /opt/wyrm/versions
   chown -h wyrm:wyrm /opt/wyrm/current
   chown root:wyrm /etc/wyrm/wyrmd.json5 && chmod 640 /etc/wyrm/wyrmd.json5
   ```
3. Change the unit of section 2:
   ```ini
   # as the broker's user: takes a failed update back, verifies what starts
   ExecStartPre=/opt/wyrm/bin/wyrmd-guard -c /etc/wyrm/wyrmd.json5 update-guard
   # as root ("+"): keeps the guard the verified binary of the current version
   ExecStartPre=+/opt/wyrm/bin/wyrmd-guard -c /etc/wyrm/wyrmd.json5 guard-refresh
   ExecStart=/opt/wyrm/current/wyrmd -c /etc/wyrm/wyrmd.json5
   ReadWritePaths=/var/lib/wyrm /opt/wyrm
   Restart=always
   ```
   `Restart=always` is needed: a new version that gives its trial up ends
   with code 76, and the guard acts at the next start. Do not list 76 in
   `RestartPreventExitStatus`, and do not set a start limit
   (`StartLimitBurst`) below 8 starts: an update that fails uses up to
   three starts of the new version and three of the old one.
4. `systemctl daemon-reload && systemctl restart wyrmd`. `sys/update_hint`
   is empty when the layout and the guard are in place; else it says what
   is missing, and `update` is refused with the same text.

CAUTION: without `ExecStartPre` a failed update is not taken back. The
broker checks that the guard ran before it started and refuses `update`
when it did not.

A simpler unit (one `ExecStartPre`, everything under `/opt/wyrm` owned by
the broker's user) works too: the broker then replaces the guard itself.
It gives up the protection of the next section.

#### What is verified, and what that does not stop

With `updates.mode: "self"` the guard verifies the version that `current`
names before every start, and the broker verifies its own binary when it
starts: the SHA-256 of `versions/<v>/wyrmd` must be the one a release
document names that a key of `updates.keys` (or the built-in key) signed
and that is kept beside the binary, or the one `bin/trusted.json` names
for a version put there by hand. A binary that fails is never started.
The guard makes the other version of the update current if that one
verifies; else it ends with code 1 and the journal says why.

A `bin/trusted.json` that cannot be read (damaged, not a plain file, more
than 1 MiB) trusts nothing: a version put there by hand is then not
verified, the refusal names the file, and the log has an error line with
it. `wyrmd install-layout` refuses to write such a file again, because it
would lose the versions the file named. To recover, as root: look at the
file; put it back from a copy, or remove it and run
`<prefix>/versions/<v>/wyrmd install-layout <prefix>` with the binary of
each version that was put there by hand (a version with a signed release
needs no entry).

CAUTION: each such run also makes its own version the current one and
puts its own binary in place of the guard. Do it with the broker stopped
and not during a trial. Run the version that must stay current last. If
the current version has a signed release and so needs no entry, note
where `current` points before you start and put it back afterwards
(`ln -sfn versions/<v> <prefix>/current.new && mv -T <prefix>/current.new
<prefix>/current`); the unit's `guard-refresh` step then makes the guard
the binary of that version again at the next start. A wrong order starts
an older binary on the data of a newer one at the next restart. In the
layout of step 2, set the owners again afterwards (`chown -R wyrm:wyrm
<prefix>/versions`, `chown -h wyrm:wyrm <prefix>/current`): what root made
the broker cannot replace at its next update.

The pre-update backup is sealed for this broker (`how: broker`): the guard
checks its manifest with the key of `secrets.key`, every file against the
manifest, and the file's SHA-256 against `update.json`.

What this stops, with the owners of step 2: a process that runs as the
broker's user (a process link, a package) cannot make the host run a
binary of its own by replacing `versions/<v>/wyrmd` or by pointing
`current` at a directory it made. It cannot replace the guard,
`bin/trusted.json` or the configuration with its keys.

What it does not stop:
- Without the owners of step 2 (everything owned by the broker's user),
  the same process can replace the guard or `bin/trusted.json`, and then
  nothing is verified.
- It can point `current` at another release that the key did sign and
  that is still in `versions/` (an older one, with a known fault). The
  check proves that a binary is a signed release, not which one.
- It owns `data_dir`: the keys of the site, the control plane, the
  backups. It needs no binary to change a link or a user.
- A process link runs under the broker's uid: it is inside the trust
  boundary until links get a uid of their own. Install packages you trust.

#### What `update` does

`sys/~act/update {version, confirm_site}` (config; `confirm_site` is the
site name). It answers at once; follow `sys/update_state` and
`sys/update_last`.

1. The release document is checked against the pinned keys. A version
   that is not newer, that needs a newer starting version (`min_from`),
   that has no build for this host, that writes an older SCHEMA than
   `data_dir` holds or that names a store this version does not know is
   refused.
2. The archive is fetched (https only; plain http only to loopback) and
   its size and SHA-256 are compared with the signed document. Then it is
   unpacked into `versions/<v>`: plain files only, the broker's own modes.
   The binary's own SHA-256 must be the one the document names. The
   document and its signature are kept beside it.
3. The new binary is asked what it is (`wyrmd release-info`) and run
   against a copy of the control plane
   (`wyrmd -c <config> check --state <copy>`). It runs with an empty
   environment. The live `data_dir` is not touched.
4. A backup of the control plane is made (`sys/backups`, kind
   `pre-update`, sealed for this broker, kept while a rollback is
   possible).
5. `data_dir/update.json` is written, `current` is switched, the broker
   stops with code 0, and systemd starts the new version.
6. The trial lasts `trial_s` seconds of **run time** of the new version.
   The version writes how long it has run every 5 s. Time the host is
   off, or the broker is down, is not part of a trial: a host that was
   off for a day comes back into the trial it left. At its end the
   version is confirmed when the admin answers, the gateway listens and
   every link that was connected before is connected again.
   `sys/update_state` is then `confirmed`.
7. Else the new version ends with code 76 and the guard, at the next
   start, restores the control plane from the pre-update backup where the
   update moved a SCHEMA, points `current` back, and the old version
   serves: `sys/update_state` is `rolled_back`, `sys/update_last.reason`
   says why. The same happens after three starts that did not end the
   trial. The clock is not asked.

CAUTION: where an update moved a SCHEMA, a rollback restores the control
plane of the moment before the update. Changes made under the new version
(links, users, flows, tokens) are lost; the directories it replaced stay
in `data_dir/update.aside` until the next rollback. A store that did not
exist before the update (the gateway's users on a broker that had no
gateway) is moved there too.

The guard does not leave the broker without a version to start:
- When the control plane cannot be restored (the backup is gone or was
  changed, a file cannot be written), the old version is started on the
  state as it is. `sys/update_state` is `failed`, the reason is in
  `sys/update_last.reason` and in the audit (`update_rollback` with an
  error status).
- When the version that a rollback made current does not come up in three
  starts, the guard makes the other version current, and so on, until one
  comes up.
- When the old version's directory is gone, the new version stays
  (`failed`).
- The one case in which nothing starts: no binary that verifies (the
  section above). The guard ends with code 1; read
  `journalctl -u wyrmd`.

A new version that hangs without ending (no exit, no restart) is not seen
by the guard. Add `WatchdogSec=` to the unit only if you also accept a
kill of a slow start; the broker sends no watchdog pings.

`sys/~act/rollback_update {confirm_site}` goes back on purpose, while the
old version and the backup are kept: `keep_days` after the update was
confirmed. A host without a clock battery may start with a wrong time, so
one reading of the clock removes nothing: the time must be past
`keep_until` at two starts of the broker, or for a full hour of one run.
`rollback_update` is refused for a session that reaches the site through
an upstream. `update` itself is allowed through an upstream with
`allow_config`: what may run is decided by the keys this host pinned.

An update is refused with `busy` while a backup is made or sent, a
restore is staged, a package or a link is being installed, updated or
restored, or another update runs. With `state_anchor_dir` set, a release
that moves a SCHEMA is refused: update that broker by hand, then run
`wyrmd init-anchors`.

The channel file holds the releases index and its signature. Each entry
of the index is a release document with its own signature, and the index
carries a sequence number: a broker refuses an index older than one it
has read (`data_dir/update.seen`), so an old index that is put back hides
no release. A read that fails is tried again after 5 minutes; the index
read before stays in use.

`update.seen` holds that sequence as one decimal number. A host that has
no such file starts at 0. A file that is there and cannot be told (not
readable by the broker's user, not a plain file, more than 32 bytes, not
a number) refuses every index: the broker does not guess 0, because then
any old index would pass. `sys/update_hint` and the answer of
`check_updates` name the file (`releases index: … update.seen …`). The
broker runs on, an index read before in this run stays in use, and a
signed archive brought by hand is still taken. To recover:

1. Look at the file: `ls -l <data_dir>/update.seen` and its content. It
   must be a plain file of the broker's user, mode 0600, with one number.
2. If only the owner or the mode is wrong, set them right.
3. If the content is lost, write the sequence of the index that the
   channel serves now (the `sequence` in its `index` text), when you
   trust that the channel is current. Then run `check_updates`.
4. Or remove the file. **Removing it drops this guard once:** the next
   index that verifies is taken whatever its sequence, also an old one
   that was put back, and the broker counts from there. Before you
   remove it, check that the channel serves the newest index.

#### Without a releases index

There is no published index yet. Bring a signed archive:

1. Upload `wyrmd-<v>-<target>.tar.gz` in parts:
   `sys/backups/~act/restore_begin {size}`, then `restore_part {upload,
   offset, data}`.
2. Call `sys/~act/update {upload, release, signature, confirm_site}` with
   the text of `wyrmd-<v>.release.json` and of its `.sig` file.

#### A standby pair

The standby goes first. It runs no router, so the active carries the
order:

1. Set `updates.mode: "self"`, the same `updates.keys`, the layout and
   the unit on both hosts.
2. On the active, call `update {target: "standby", upload, release,
   signature, confirm_site}`. The standby fetches the archive from the
   active, checks the signature with its own keys, proves the binary and
   restarts on it. `sys/standby_update` shows `ordered <v>`, then
   `<v> trial`, then `<v> confirmed` (or `rolled_back` / `failed`), and
   `sys/standby_version` the version it runs.
3. When the standby is confirmed, call `update` for the active (the same
   arguments without `target`). It is refused while the standby runs
   another version or is not confirmed. `without_standby: true` updates
   the active alone when the standby is not connected.

While the active restarts, the standby waits up to 120 s. If the new
version does not come up in that time the standby, already on it, takes
over. A release that changes the replication protocol cannot be done this
way: stop the standby, update both hosts by hand, start the active first.

### Several sites

A site does not depend on its upstream: it keeps polling, recording and
alarming while the upstream is away, and the upstream catches up through the
history and alarm sinks (`next {after, max}`) when the link is back. A
restart of the upstream therefore costs the downstream nothing but a gap in
what the upstream saw live. The same holds the other way round: the upstream
shows the downstream site as not connected and serves everything else.

`downstream/<d>/connected` (and `upstream/<u>/connected` on the other side)
is true when queries reach the peer, not only when its broker token
`wy/<peer>/sys/broker` is there. After the token comes, the broker sends a
probe to the peer's `sys/signing_keys` (3 s timeout; 50 ms between probes,
doubled up to 5 s) and sets `connected` when a probe has an answer. A router
that has just connected has its token routed before queries to it are, so
the token alone can be true up to about 100 ms before any query answers
(`docs/backlog.md` §6). When the token goes, `connected` is false at once.

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
| `packages/`, `peers/`, `operators/` | installed link packages (and the previous version of an updated one), certificates issued for downstream brokers, operator certificates | reinstall, reissue |
| `update.json`, `update.guard`, `update.seen`, `update.aside/` | the state of the broker's own update (ADR 0048 §2), when the guard ran last, the highest sequence of a releases index read, and the control-plane directories a rollback replaced | a rollback of a confirmed update is not possible |
| `restore/<link>/` | restore points of links taken before a package update or a restore from a backup (docs/links.md §5a): link backups (`.wyrm-link`) sealed with a key derived from `secrets.key`, and their `.meta` | a rollback of an update restores no private data |

How to take a backup:
- **Online, from the broker itself (ADR 0048).** `sys/backups/~act/create
  {sections, passphrase}` makes a `.wyrm-backup` while the broker runs: the
  WALs as of one sequence number, the storage at one revision, each history
  file inside one read transaction, keys and secrets sealed with the
  passphrase. Read it with `download_part`, or let the broker write it into
  a file store with `send` (the host names the link and the folder in
  `backups.send_links`). One link goes with `sys/links/<id>/~act/backup`.
  The keys section and a passphrase need `backups.export_secrets: true` on
  the host; without it a backup holds no keys and its link secrets open
  only on a broker with this site's keys. Restore with
  `sys/backups/~act/restore_check` and `restore_apply`: `mode: add` works
  live; `mode: replace` restarts the broker once, is refused for a caller
  that comes through an upstream, and restores keys only with
  `export_secrets`, the passphrase and, for keys that differ from this
  broker's, `replace_keys`. Sections, limits and the restore of a link are
  in [backups.md](backups.md). This is the way for a broker that runs; the
  two ways below stay for a broker that does not start.
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
warm standby: see "Warm standby" in section 2.

### Official links offline

`packages: { repository: "official" }` (ADR 0043, docs/links.md §12a) makes
the broker fetch the official index from github.com at each start and
rebuild. It is off by default. A broker that cannot reach github.com logs
`repository index: …` and starts as usual. For a site without internet
access, mirror one release on a host that the broker reaches:

1. On a computer with internet access, download all assets of one release
   `links-v…` (the zips, `official.json`, `SHA256SUMS`):
   `gh release download links-v… --repo gencto/wyrm --dir mirror`.
2. Check the files: `(cd mirror && sha256sum -c SHA256SUMS)`.
3. Write an index with relative URLs:
   `wyr repo index --manifest mirror/official.json --zips mirror --out mirror/index.json`.
4. Copy `mirror/` to a web server on the plant network. Serve it over HTTPS,
   or over HTTP on the broker host itself (plain HTTP only to loopback).
5. Set `packages: { repository: "https://<mirror>/index.json" }` and restart
   the broker.

The broker checks every zip against the SHA-256 of the mirror's index, as
it does for the official one.

## 4. Checks

- `wyrmd -c … check`: the configuration parses and validates; exit code 1
  otherwise. Run it before a restart with a changed file. With
  `--state <dir>` it also opens every control-plane store of a copy of a
  `data_dir` with this binary (what a broker does with a newer version
  before it updates to it); it never opens the live `data_dir`.
- `wyrmd release-info`: what this binary is (version, target, the SCHEMA
  of each store, the replication protocol).
- `wyrmd -c … verify`: every control-plane store offline (broker stopped).
- Running: `wy/<site>/sys/uptime`, `links_total`, `links_connected`,
  `quarantined`, `acl_denied`, `cpu`, `memory`, `disk_free`, `data_size`
  (`wyr list wy/<site>/sys`), `sys/links/<id>/state` and `error` per link,
  `sys/history/disk_space_remaining`; per flow `dataflows/<id>` (`~val`:
  `state` and the counters `stats.samples_in`, `dropped`, `commands.error`,
  ADR 0045, [flow-blocks.md](flow-blocks.md)). The liveliness token
  `wy/<site>/sys/broker` is what links and peers watch; a monitor can watch
  it too (`wyr sub`).
- `sys/~act/get_log` and per-link `get_log` hold the recent log ring; the
  level is `sys/log_level` (`RUST_LOG` at start).
