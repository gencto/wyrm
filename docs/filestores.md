# File store links: S3, Google Drive, WebDAV, local directories

Four links show a file store as a tree of folders and files, keep it
fresh, and let people (and flows) create folders, upload, download and
delete files:

| Link (driver, package) | Stores | Crate |
|---|---|---|
| `s3` | AWS S3, MinIO, Ceph RGW, Cloudflare R2, Wasabi, Backblaze B2, DigitalOcean Spaces, Google Cloud Storage (HMAC keys) | `links/s3` |
| `gdrive` | Google Drive: My Drive, a folder shared with a service account, a shared drive | `links/gdrive` |
| `webdav` | Nextcloud, ownCloud, Synology, QNAP, Apache/nginx DAV, rclone serve, pCloud, Yandex Disk, … | `links/webdav` |
| `localfs` | a directory of the host: a local disk, a USB stick or SD card, an NFS / SMB / sshfs mount, a NAS volume, a sync folder | `links/localfs` |

All four run on `crates/wyrm-filestore` (ADR 0027): the same tree, the
same actions, the same limits. They run embedded in `wyrmd` or as
processes (`wyrmd link s3`, or the packages' binaries).

## 1. The tree

```
downstream/<link>/
  <connection>         one bucket / drive folder / collection
    status             Unknown, Connecting, Connected, Failed, Stopped
    error              while there is one (also "truncated: …")
    entries            files and folders shown
    total_bytes        sum of the file sizes (B)
    last_refresh       when the whole tree was read (UTC)
    files/             the connection's root folder
      reports/         a folder
        2026/
          october.csv  a file: value = size (B), at the file's time
```

- A **file** is a leaf whose value is its size in bytes, timestamped with
  its last change. Its `attr` holds `name`, `path` (below the root),
  `modified`, `etag` and `content_type` when the store reports them.
- A node's key is the file's name when that is a valid key segment
  (letters, digits, `_`, `-`, `.`). Other names (`a b (1).txt`, `Звіт.pdf`)
  get a safe key with a stable hash (`a_b_1_.txt_1f2e3d4c`); the real name
  is the node's display name. A node keeps its key while its file exists,
  so history watches and flows on it keep working.
- The tree is read at start, every `refresh_s` (default 300 s; 0 = only
  on Refresh) and on Refresh. What the store no longer has is removed.

## 2. Actions

| Node | Action | Level | What it does |
|---|---|---|---|
| root | Add S3 Bucket / Google Drive / WebDAV Folder (`add_connection`) | config | a new connection: its `name` and params (below) |
| connection | Edit, Remove, Stop / Start | config | secrets left empty in Edit keep the stored ones (while the destination stays the same) |
| connection | Refresh | read | read the whole tree again → `{entries, truncated}` |
| folder (and `files`) | Refresh | read | read this folder again |
| folder (and `files`) | Create Folder `{name}` | write | → `{path, node}` |
| folder (and `files`) | Upload File `{name, file \| text, content_type?, overwrite?}` | write | → `{path, node, size}`; without `overwrite` a file of that name is refused |
| folder | Delete `{recursive?}` | write | without `recursive` the store itself is asked whether the folder is empty (not the tree, which may miss hidden names, deep levels and new files) |
| file | Download `{text?}` | read | the bytes (or UTF-8 text with `text`) |
| file | Delete | write | |

Uploads take a `file` (the explorer's file picker; larger than a WebSocket
frame goes through the gateway's `POST /api/invoke`) or `text`. The
content type comes from the name's extension when not given. A file is
found by its real name (Overwrite replaces the file called that, not
another whose key looks the same).

Each connection runs one tree read at a time (a Refresh while one runs
answers `busy`) and two uploads or downloads at a time (a third answers
`busy`): the bytes of a transfer are held in memory.
Stop, Remove and Edit of a connection cut its actions in flight: they
answer `disconnected` and send nothing more to the store.

Without `overwrite` an upload never replaces a file: S3 and WebDAV send
`If-None-Match: *`, `localfs` creates the file new. Some servers ignore
that header (nginx `dav`, some Ceph RGW versions, Wasabi, Backblaze B2,
the GCS XML API): there a file made by someone else after the last refresh
can be replaced.

Common connection params (all four links):

| Param | Default | Range | |
|---|---|---|---|
| `refresh_s` | 300 | 0, 5–86 400 | 0 = only on Refresh |
| `max_entries` | 2000 | 1–9000 | more are left out; the connection says `truncated` |
| `max_depth` | 8 | 1–12 | folder levels shown |
| `max_upload_mib` | 32 | 1–64 | Upload File in one request |
| `max_file_mib` | 4096 | 1–1 048 576 | a file uploaded in parts |
| `max_download_kib` | 1024 | 1–16 384 | |

Connections and their secrets are kept sealed in the link's `data_dir`
(`filestore.conns`, the link's store key), never shown in `~meta` or
replies. Bootstrap params (`wyrmd.json5`) may list connections too:
`params: {connections: {<name>: {…}}}`; when they change, they replace
what was added at runtime.

## 3. S3 (`s3`)

| Param | Default | |
|---|---|---|
| `endpoint` | `https://s3.amazonaws.com` | AWS `https://s3.<region>.amazonaws.com`; MinIO `https://minio:9000`; R2 `https://<account>.r2.cloudflarestorage.com`; GCS `https://storage.googleapis.com` |
| `region` | `us-east-1` | R2 and GCS: `auto` |
| `bucket` | — | |
| `addressing` | `auto` | `auto` = virtual-hosted on `*.amazonaws.com`, path-style elsewhere; `path`, `virtual` |
| `prefix` | — | the connection's root inside the bucket (`site1/reports`) |
| `access_key_id`, `secret_access_key` (secret), `session_token` (secret) | — | empty keys: unsigned requests (a public bucket) |
| `timeout_ms` | 10000 | |
| `ca_pem`, `insecure_skip_verify`, `insecure_plaintext` | | TLS; keys over `http://` only to loopback unless `insecure_plaintext` |

S3 has keys, not folders: every `/` in a key is a folder level, and Create
Folder stores the empty marker `<folder>/` as the S3 consoles do. Delete
of a folder deletes every key below it (at most 10 000). The bucket needs
the list, get, put and delete permissions (`s3:ListBucket`, `s3:GetObject`,
`s3:PutObject`, `s3:DeleteObject`). A bucket in another region than
`region` fails with the region the store names.

MinIO example:

```json5
links: [{ id: "minio", driver: "s3", params: { connections: { reports: {
  endpoint: "https://minio.plant.local:9000", bucket: "reports",
  access_key_id: "wyrm", secret_access_key: "…", refresh_s: 600 } } } }]
```

Better: leave the secret out of `wyrmd.json5` and add the connection at
runtime (Add S3 Bucket), where the key is sealed.

## 4. Google Drive (`gdrive`)

| Param | Default | |
|---|---|---|
| `auth` | `service_account` | or `refresh_token` |
| `service_account_json` (secret) | — | the whole JSON key file of a service account |
| `subject` | — | Workspace domain-wide delegation: act as this user |
| `client_id`, `client_secret` (secret), `refresh_token` (secret) | — | `auth: refresh_token`: an OAuth client and a user's refresh token (scope `https://www.googleapis.com/auth/drive`) |
| `folder_id` | `root` | the connection's root: `root` (My Drive) or the id in the folder's URL (`…/folders/<id>`) |
| `shared_drive_id` | — | a shared drive; with `folder_id: root` its top |
| `trash` | `true` | Delete moves to the trash; `false` deletes for good |
| `timeout_ms` | 15000 | |
| `api_url`, `token_url` | Google's | a proxy or the simulator |
| `ca_pem` | — | a TLS-inspecting proxy |

A service account sees only what is shared with it: share the folder with
its `client_email`, and use that folder's id. Drive allows two files of one
name in a folder and `/` in names; the tree shows both (the second with a
part of its id in the key), with the real names. Google Docs, Sheets and
Slides show with size 0 and their type; they cannot be downloaded (export
is not supported).

## 5. WebDAV (`webdav`)

| Param | Default | |
|---|---|---|
| `url` | — | the collection: Nextcloud `https://<host>/remote.php/dav/files/<user>/<folder>` |
| `auth` | `basic` | `none`, `basic`, `bearer` |
| `username`, `password` (secret) | — | Nextcloud and ownCloud: an app password |
| `token` (secret) | — | `auth: bearer` |
| `timeout_ms` | 10000 | |
| `ca_pem`, `insecure_skip_verify`, `insecure_plaintext` | | as S3 |

The tree is read folder by folder with `PROPFIND Depth: 1` (servers often
refuse `Depth: infinity`); folders are real collections (`MKCOL`).

## 6. Large files: transfers in parts

Upload File and Download carry a file in one request (at most 64 MiB and
16 MiB). Larger files go in parts (ADR 0028):

| Node | Action | Level | |
|---|---|---|---|
| folder (and `files`) | Upload in Parts (`upload_begin {name, size, part_size?, content_type?, overwrite?, sha256?}`) | write | → `{upload, part_size, parts}` |
| connection | `upload_part {upload, index, data}` | write | one part, from index 0; any order, again after a cut |
| connection | `upload_status {upload}` | write | `state` (`receiving`, `committing`, `done` with `result`, `failed` with `error`), `missing` parts |
| connection | `upload_commit {upload}` | write | → `committing`; the file goes to the store in the background |
| connection | `upload_abort {upload}` | write | drops it and its parts |
| file | `download_part {offset, length?}` | read | → `{data, offset, size, eof}`, up to 16 MiB a part |

- Parts are 64 KiB … 16 MiB (4 MiB by default); every part but the last
  has `part_size` bytes. A file is at most `max_file_mib` (4 GiB by
  default). Send parts through the gateway's `POST /api/invoke`.
- The link keeps the parts in a spool file on its own disk
  (`<data_dir>/uploads/`) until the commit, so its disk needs room for the
  file. The commit sends it to the store as it reads it: S3 multipart
  (`multipart_mib`, 16 MiB parts), a Drive resumable upload
  (`upload_chunk_kib`, 8 MiB chunks), one streamed WebDAV `PUT`, a copy for
  `localfs`. Memory holds one part, not the file.
- An upload belongs to whoever began it; at most 4 per connection; one
  idle for an hour is dropped. Stopping or editing the connection, or
  restarting the link, drops its uploads: begin again.
- Give `sha256` at begin to have the parts checked before the file goes
  to the store.

A client loop: `upload_begin`, then `upload_part` for each index (several
at once is fine, two run at a time), `upload_status` to find what is
missing after a cut, `upload_commit`, then `upload_status` until `done`.
A download: `download_part` from offset 0 until `eof`.

## 7. Local directory (`localfs`)

The link's own params (set by the broker's admin in `sys/links` or
`wyrmd.json5`, not by Add Local Directory) list the directories its
connections may use:

```json5
links: [{ id: "files", driver: "localfs", params: {
  allowed_roots: "/srv/plant\n/mnt/usb" } }]
```

One absolute path per line; a connection's `root` must be one of them or
below one. Empty (the default) allows none: an embedded `localfs` reads and
writes with the broker's permissions, so a user with `config` on the link
must not choose any path of the host. `/proc`, `/sys` and `/dev` are never
allowed. The check runs on add, edit, start and before every probe. A
directory that does not exist yet is checked where it would be made (its
existing part resolved, links followed), so a link inside an allowed
directory that leads out does not take a new `root` with `create_root` out
with it. The params are read when the link starts: narrowing
`allowed_roots` takes effect on the link's next restart (the admin's
`update` restarts it).

| Param | Default | |
|---|---|---|
| `root` | — | an absolute path: `/srv/plant/reports`, `/mnt/usb`, `/Volumes/NAS/share`, `D:\reports`, `\\nas\share` |
| `create_root` | `false` | create it (and its parents) when missing |
| `read_only` | `false` | refuse Create Folder, Upload File and Delete |
| `show_hidden` | `false` | show names starting with `.`; while off they are not written either |
| `follow_symlinks` | `false` | show symbolic links that resolve inside `root` (others are never shown) |
| `fsync` | `true` | sync each upload and its folder (power loss; slower on SD cards) |
| `timeout_ms` | 10000 | bound on each file system call (a hung network mount) |

Where it runs: `std::fs` only, so the same link on Linux, macOS, Windows
and the BSDs, on x86-64 and ARM boards, embedded in `wyrmd` or as a process
link (`wyrm-link-localfs`, package `localfs`). A process link on another
host shows that host's directory: run it on the machine with the disk.
Anything the operating system mounts works the same way (NFS, SMB/CIFS,
sshfs, a USB or SD card, a cloud drive's sync folder).

What it guarantees:

- Nothing outside `root`: paths are built name by name below it, and
  before every change the folder is resolved and must still be inside the
  resolved root (a folder swapped for a symlink to elsewhere is refused).
  Symbolic links out of `root` are never shown or followed; deleting a
  link deletes the link, not its target.
- `root` may not overlap the broker's data directory (registry, keys, link
  data), nor contain it. The link reads and writes with the permissions of
  its process: for least privilege run it as a process link under its own
  OS user that may see only the directories it serves.
- Names for new files and folders are valid on every system: no `/ \ < >
  : " | ? *`, no `CON`, `NUL`, `COM1` …, no `.` or space at the end.
- An upload with `overwrite` goes to a hidden temporary file
  (`.wyrm-<id>.tmp`) and is renamed over the old file, so readers never
  see half a file; the old file's permissions stay (its owner and extended
  attributes do not). Without it the file is created new and a file made
  meanwhile is never replaced; a failed write removes only what it made.
- A hung mount fails the call after `timeout_ms` (and the connection
  probes again); the blocking thread stays until the kernel returns, and
  while it does the next calls on that directory answer `timeout` at once
  (also after a Stop and Start or an Edit), so one hung mount holds one
  thread, not one per retry. The place check runs on that pool too.
- The root is pinned where the probe resolved it; a root swapped for a
  link after that is refused on the next change, and the probe checks the
  new place before it pins it again.
- The temporary file of an overwrite has a name no other process can
  guess and is removed only when this upload made it; the old file's
  permission bits stay, without setuid, setgid or sticky.
- Left: the checks resolve a path, then act on it. On a shared NFS/SMB
  mount another writer could swap a folder for a link between the two.
- Names that are not UTF-8 (possible on Linux) are left out; sockets,
  devices and FIFOs are not shown.

## 8. Failures

- The probe (S3: a list of one key; Drive: the root folder; WebDAV:
  `PROPFIND Depth: 0`) or a tree read failing marks the connection
  `Failed` with the `error` leaf; it reconnects with backoff (1 s … 60 s).
  The tree stays as last read meanwhile.
- An action whose request shows the store is down (no connection, a 5xx,
  a timeout) answers `disconnected` or `timeout` and makes the connection
  probe again at once.
- A request refused for one object (403, 404, a name taken) fails that
  action only (`invalid_parameter`, `not_found`).

## 9. Simulators

The network links have a simulator binary (feature `bin`) for demos; `localfs` needs none (its tests run on temporary directories):

```bash
cargo run -p wyrm-link-s3 --features bin --bin wyrm-s3-sim -- --listen 127.0.0.1:9100
```

```bash
cargo run -p wyrm-link-gdrive --features bin --bin wyrm-gdrive-sim -- --listen 127.0.0.1:9101
```

```bash
cargo run -p wyrm-link-webdav --features bin --bin wyrm-webdav-sim -- --listen 127.0.0.1:9102
```

- S3: bucket `plant`, keys `AKIASIM` / `sim-secret-key`, path-style
  (`endpoint: http://127.0.0.1:9100`).
- Drive: `api_url: http://127.0.0.1:9101`, `token_url:
  http://127.0.0.1:9101/token`, `auth: refresh_token`, `client_id:
  sim-client`, `client_secret: sim-client-secret`, `refresh_token:
  sim-refresh-token`.
- WebDAV: `url: http://127.0.0.1:9102/dav/files/alice`, user `alice`,
  password `sim-password`.

Not yet verified against the real services: the tests run the simulators,
and S3 signing is checked against the AWS Signature V4 test vectors.
