# ADR 0027 — File store links (S3, Google Drive, WebDAV, local directories) on the raw layer

**Status:** accepted · 2026-10-31 (owner request: links to popular file stores — S3, MinIO, Google Drive and other providers — that connect to a bucket, create folders, read the tree of folders and files, build it as nodes, and upload files; separate links where the stores need different code).

## Context
The driver framework (ADR 0004) is `Connection → Device → Point`: people configure every node, the framework polls points. A file store is the other way round: people configure one connection (a bucket, a drive folder, a WebDAV collection), and the nodes below it are whatever the store holds, found by reading it. Points do not fit either: a file has a size, a time and bytes, read on demand, not a value polled every second.

The stores differ in protocol, auth and model: S3 has flat keys and Signature V4; Google Drive has ids, duplicate names, OAuth 2 (service-account JWTs, refresh tokens); WebDAV has real collections, `PROPFIND` multistatus XML and basic or bearer auth.

## Decision
- **Three links, one toolkit.** `links/s3` (AWS S3 and the S3-compatible stores: MinIO, Ceph RGW, Cloudflare R2, Wasabi, Backblaze B2, DigitalOcean Spaces, Google Cloud Storage with HMAC keys), `links/gdrive` (Drive API v3), `links/webdav` (Nextcloud, ownCloud, Synology, …). Each implements `wyrm_filestore::Backend` (probe, scan, mkdir, put, get, delete) and runs as `FileStore<B>`, a raw-layer `Link` in `crates/wyrm-filestore`. Each is its own driver, package and process binary; none adds a dependency the workspace did not have (SigV4 and the JWT on `ring`, XML by a small reader in the toolkit, Drive JSON on `serde_json` as store data, not the wire).
- **Raw layer, the framework's conventions.** Connections come from `add_connection` (the backend's params plus `refresh_s`, `max_entries`, `max_depth`, `max_upload_mib`, `max_download_kib`; one form built from `#[derive(Params)]`), `edit` (secrets left empty keep the stored ones while the `dest` fields stay the same, as the framework's `keep_secrets`), `remove`, `stop`/`start`. They are kept sealed in `data_dir/filestore.conns` with the link's store key, bootstrap params win when they change — the framework's `persist`, reimplemented on the public `seal`. A connection node has the framework's `status` enum leaf (`wy:df-status`) and the `error` leaf while there is one, and `entries`, `total_bytes`, `last_refresh`.
- **The tree is the store's, re-declared on every read** (principle 3). `<conn>/files` is the root folder; a folder node per folder, a leaf per file (value = size in bytes, at the file's time; `attr` `name`, `path`, `modified`, `etag`, `content_type`). What a read does not report is removed. A node keeps its key while its entry exists; a name that is not a key segment gets a safe form with a stable hash, the real name is `display`.
- **Bounded reads.** A read stops at `max_entries` (≤ 9 000) and `max_depth` (≤ 12) and says `truncated`; S3 reads at most 500 pages, a whole read at most 10 minutes. Uploads at most 64 MiB (the gateway's `POST /api/invoke` body), downloads at most 16 MiB.
- **Levels.** Reads (`refresh`, `download`) at `read`, changes of the store (`create_folder`, `upload`, `delete`) at `write`, connections at `config`. I/O of an action runs on a task of its own, so a slow upload never holds the link's other calls.
- **Failures.** The probe (an S3 list of one key, Drive `files.get` of the root, WebDAV `PROPFIND Depth: 0`) failing, or a read failing, fails the connection; it reconnects with the framework's backoff. A request of an action that shows the store is down (connect, 5xx, timeout) wakes the connection task, which probes again. A refused request of one object (403, 404, a taken name) fails that action only.
- **No silent overwrite.** An upload without `overwrite` sends `If-None-Match: *` (S3, WebDAV) or creates a new Drive file only when the tree has none of that name.
- **Credentials never leave in clear:** `http://` with credentials only to loopback unless `insecure_plaintext`; Drive's API and token URLs must be `https://` off loopback.

## Consequences
- Big buckets show in part (`truncated`); people set `prefix` (S3) or a subfolder URL (WebDAV) or folder id (Drive) as the connection's root to see the part they need.
- File contents are not values: no history, no flows on them. A flow can invoke `upload` (a report) or `download` through `invoke` sinks like any action.
- Google Docs files have no bytes to download (export is not built); S3 uploads are one PutObject (no multipart upload, so up to the 64 MiB cap).
- Each link has an in-crate simulator (`wyrm-s3-sim`, `wyrm-gdrive-sim`, `wyrm-webdav-sim`) and runs one shared scenario (`wyrm_filestore::testkit`); SigV4 is checked against the AWS test vectors. Not yet verified against the real services.

## Alternatives
- **The driver framework with devices as folders:** people would add every folder by hand, and files are not polled points.
- **One link with a `provider` enum:** one package pulls in every store's code and params; the owner asked for separate links.
- **The AWS and Google SDKs:** large dependency trees, aws-lc (refused, see the rustls pin), and three async runtimes' worth of HTTP stacks for what is a handful of requests.

## Amendment 2026-10-31 — local directories (`links/localfs`)
Owner request: local storage too, working in as many places as possible.
- **`std::fs` only**, every call on the blocking pool under `timeout_ms`: one link for Linux, macOS, Windows and the BSDs, embedded or as a process link on the host that has the disk. Mounted storage (NFS, SMB, sshfs, USB/SD, NAS) needs nothing of its own.
- **Confinement**: names checked one by one (portable names: what Windows refuses is refused everywhere), the parent resolved and checked inside the resolved root before every change, symlinks out of the root never shown or followed, `remove_dir_all` (which does not follow links) for folders.
- **`Backend::check_place`** (default: nothing): called with the link's `data_dir` on add, edit and start; `localfs` refuses a root that overlaps the broker's data directory (`<data_dir>/links/<id>/data` → `<data_dir>`) in either direction.
- Atomic overwrite (temporary file + rename), `create_new` otherwise, `fsync` of the file and its folder by default, `read_only`.
- Not done: Windows ACLs and hidden attributes (only names starting with `.` are hidden).

## Amendment 2026-10-31 — review of gencto/wyrm#7 (owner)
Renumbered 0025 → 0027 (0025 is the DQL link on another branch, 0026 history sync).
- **Delete asks the store.** `Backend::delete(e, below, recursive)`: without `recursive` the backend checks the store itself (localfs `remove_dir`, S3 a list of two keys under the prefix, WebDAV `PROPFIND Depth: 1`, Drive the folder's children) and answers "not empty"; the tree may miss hidden names, deep levels, entries over `max_entries` and new files.
- **`localfs` needs `allowed_roots`** (`Backend::link_options`: bootstrap params beside `connections`, set by the admin; checked by `store::validate::<B>` in `wyrmd` and on start). Empty = no directory; `/proc`, `/sys`, `/dev` never; `Backend::check_place(data_dir, options)` also runs before every probe. Built-in roles with `config` on `downstream/**` (`engineer`) can no longer point it at any host path.
- **Bounded concurrency.** One tree read per connection (`busy` otherwise), two transfers per connection; upload bytes are taken out of the args, not copied.
- **One hung call per connection** (`localfs` `Gate`): while a timed-out blocking call still runs, new calls answer `timeout` at once.
- **Files by their real name** (`View::child_named`): Overwrite never patches another file whose path form is the same (Drive `a/b.txt` vs `a_b.txt`); an entry a request made whose path another id holds gets the id in its path; Drive lists by `name,createdTime` and gives a duplicate of a suffixed path the whole id.
- **An older read never undoes an action** (`View::gen`/`touched`): entries an action created or deleted after a read started are left as the action made them.
- Smaller: a failed `create_new` write removes only the file it made; hidden names are not written while not shown; the temporary name is short and keeps the old permissions; more Windows reserved names; `refresh_s` 0 or ≥ 5; a short Drive token life is renewed halfway; a header that cannot be set fails the request (never sent unauthenticated); WebDAV bearer tokens checked; names a store sends that are `.`/`..`/empty/control are left out; a stored connection the link cannot show is skipped, not the link.
- Still open: action tasks outlive Stop/Remove/Edit (no cancel token yet); `localfs` resolve-then-act races on shared mounts (`openat2(RESOLVE_BENEATH)` / `O_NOFOLLOW` are Linux-only and not used).
