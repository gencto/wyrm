# File store links: S3, Google Drive, WebDAV

Three links show a file store as a tree of folders and files, keep it
fresh, and let people (and flows) create folders, upload, download and
delete files:

| Link (driver, package) | Stores | Crate |
|---|---|---|
| `s3` | AWS S3, MinIO, Ceph RGW, Cloudflare R2, Wasabi, Backblaze B2, DigitalOcean Spaces, Google Cloud Storage (HMAC keys) | `links/s3` |
| `gdrive` | Google Drive: My Drive, a folder shared with a service account, a shared drive | `links/gdrive` |
| `webdav` | Nextcloud, ownCloud, Synology, QNAP, Apache/nginx DAV, rclone serve, pCloud, Yandex Disk, … | `links/webdav` |

All three run on `crates/wyrm-filestore` (ADR 0025): the same tree, the
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
| folder | Delete `{recursive?}` | write | a folder that is not empty needs `recursive` |
| file | Download `{text?}` | read | the bytes (or UTF-8 text with `text`) |
| file | Delete | write | |

Uploads take a `file` (the explorer's file picker; larger than a WebSocket
frame goes through the gateway's `POST /api/invoke`) or `text`. The
content type comes from the name's extension when not given.

Common connection params (all three links):

| Param | Default | Range | |
|---|---|---|---|
| `refresh_s` | 300 | 0–86 400 | 0 = only on Refresh |
| `max_entries` | 2000 | 1–9000 | more are left out; the connection says `truncated` |
| `max_depth` | 8 | 1–12 | folder levels shown |
| `max_upload_mib` | 32 | 1–64 | |
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

## 6. Failures

- The probe (S3: a list of one key; Drive: the root folder; WebDAV:
  `PROPFIND Depth: 0`) or a tree read failing marks the connection
  `Failed` with the `error` leaf; it reconnects with backoff (1 s … 60 s).
  The tree stays as last read meanwhile.
- An action whose request shows the store is down (no connection, a 5xx,
  a timeout) answers `disconnected` or `timeout` and makes the connection
  probe again at once.
- A request refused for one object (403, 404, a name taken) fails that
  action only (`invalid_parameter`, `not_found`).

## 7. Simulators

Each link has a simulator binary (feature `bin`) for demos:

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
