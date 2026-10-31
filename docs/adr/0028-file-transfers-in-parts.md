# ADR 0028 — File transfers in parts (file store links)

**Status:** accepted · 2026-10-31 (owner request: files of 1 GB and more through the brokers and the file store links of ADR 0027).

## Context
ADR 0027 moves a file as one action: `upload` takes it as one argument, `download` returns it as one reply. Every hop holds it whole (the args, the Zenoh query, the HTTP body to the store), so the links cap uploads at 64 MiB (the gateway's `POST /api/invoke` body) and downloads at 16 MiB. A file of 1 GB would take several times its size in memory on a board with 2 GB, and one query of that size through a chain of brokers.

## Decision
- **Uploads in parts, spooled on the link's disk** (`wyrm_filestore::parts`). A folder's `upload_begin {name, size, part_size?, content_type?, overwrite?, sha256?}` (level write) answers `{upload, part_size, parts}`. The connection's `upload_part {upload, index, data}` writes one part at its offset into a sparse spool file (`<data_dir>/uploads/c-<conn>/<id>.part`, 0700; the prefix keeps a connection named `.` or `..` below `uploads`). Parts may come in any order, and again after a cut; `upload_status {upload}` lists the missing ones (at most 1000). `upload_commit {upload}` answers `committing` at once and sends the spool file to the store in the background (a large file takes longer than a request may wait); `upload_status` then says `done` with the Upload File answer, or `failed` with why. `upload_abort` drops it. Parts are 64 KiB … 16 MiB (default 4 MiB); a file is at most `max_file_mib` (default 4 GiB, at most 1 TiB).
- **To the store as it is read**: `Backend::put_file(parent, name, src, size, …)`:
  - S3: CreateMultipartUpload, parts of `multipart_mib` (default 16 MiB, at least 5 MiB, larger for files over 10 000 parts), CompleteMultipartUpload with `If-None-Match: *` unless it overwrites, AbortMultipartUpload on a failure.
  - Drive: a resumable session (`uploadType=resumable`, PATCH to replace), chunks of `upload_chunk_kib` (a multiple of 256 KiB) with `Content-Range`, resumed from Drive's `Range` on 308. The session URL must be on the API's origin.
  - WebDAV: one `PUT` whose body is streamed from the spool file (`http::Request::file_body`).
  - localfs: a copy from the spool file, through the same temporary file and rename as an overwrite.

  One part (S3, Drive) or one 256 KiB read buffer (WebDAV, the HTTP client) is in memory at a time.
- **Downloads in parts**: a file's `download_part {offset, length?}` (level read, length ≤ 16 MiB, default 4 MiB) answers `{data, offset, size, eof}`, through `Backend::get_range`: an HTTP `Range` request (S3, Drive, WebDAV; a store that ignores `Range` for an offset past 0 is refused rather than read whole), a seek and a read (localfs).
- **Ownership and bounds.** An upload belongs to the `ptok` subject that began it: another subject's request answers `not_found`. At most 4 uploads hold a spool file per connection (receiving, committing, or failed and kept for another commit; counted and taken under one lock), so the spool is at most 4 × `max_file_mib`; parts, downloads and commits share the connection's two transfer slots. An upload idle for an hour is dropped with its spool file; so are all of a connection's when it stops or is edited, and all spool files on the link's start. A `sha256` given at begin is checked before the file goes to the store.
- **Same path through the brokers**: each part is an ordinary action, so a chain of brokers carries it as any other (one query per part, at most 16 MiB). A client sends parts through the gateway's `POST /api/invoke` (a WebSocket frame holds 64 KiB).

## Consequences
- Memory no longer grows with the file: a 512 MiB transfer in parts of 8 MiB (debug build, the link, the client and Zenoh in one process) peaked at 133 MiB of resident memory.
- The link's disk holds a file in progress whole (sparse at first); `max_file_mib` bounds it, and `upload_begin` refuses a file larger than the free space of the spool's disk minus 1 GiB (`resource_exhausted`), checked again at each part for the bytes still to come (ADR 0029, decision 11).
- A connection's uploads in progress are lost when it stops or the link restarts (the spool is not kept; the client begins again).
- Not done: presigned URLs (bytes past the brokers when a client can reach the store); a server-side copy between connections; a hash of a download (the client checks it against the store's `etag` where that is a digest).

## Alternatives
- **Parts straight to the store at each `upload_part`** (S3 parts, Drive chunks): no spool, but parts must come in order for Drive and WebDAV, S3 parts must be at least 5 MiB, and a retry from the client has to match the store's rules. The spool takes parts in any order for every store.
- **A stream action for downloads**: one request, but a stream reply cannot be resumed at an offset after a cut, and the gateway's HTTP invoke returns the last item only.
