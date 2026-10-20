/* WYRM C ABI (crates/wyrm-ffi). See src/lib.rs for the full contract.
 *
 * Requests return at once; their replies and stream events arrive through
 * wyrm_next_event as canonical CBOR maps in the gateway WebSocket frame
 * format: {id, ok: true, result?} | {id, ok: false, error: {status, message}}
 * | {id, event: {type, ...}}. Values cross the boundary as CBOR.
 *
 * Ownership: a handle lives from wyrm_open* to wyrm_free (call
 * wyrm_shutdown first, then wyrm_free when no thread uses it). Event
 * buffers: wyrm_buf_free(ptr, len). Error strings: wyrm_string_free.
 * Input pointers are borrowed for the call only. No panic crosses the ABI.
 */
#ifndef WYRM_H
#define WYRM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WYRM_OK 0             /* success; wyrm_next_event: timeout */
#define WYRM_EVENT 1          /* wyrm_next_event: one event written */
#define WYRM_ERR_ARG (-1)     /* null or malformed argument */
#define WYRM_ERR_CLOSED (-2)  /* handle is shut down */
#define WYRM_ERR_PANIC (-3)   /* panic caught */
#define WYRM_ERR_DUPLICATE (-4) /* a stream with this id is open */

typedef struct WyrmHandle WyrmHandle;

/* Zenoh client session to `endpoint` ("tcp/127.0.0.1:7447"); plaintext on
 * loopback only. `seed`: null or 32-byte Ed25519 seed trusted by the broker;
 * then `site` is required. Null on failure, with *err set (free with
 * wyrm_string_free). */
WyrmHandle *wyrm_open(const char *endpoint, const uint8_t *seed, const char *site, char **err);

/* As wyrm_open, over mTLS ("tls/host:port" or "quic/..."): `ca` is the
 * broker CA, `cert`/`key` a client certificate it issued (PEM file paths). */
WyrmHandle *wyrm_open_tls(const char *endpoint, const char *ca, const char *cert, const char *key,
                          const uint8_t *seed, const char *site, char **err);

/* Feature "test-harness" only: in-process isolated peer + mock link. */
WyrmHandle *wyrm_open_test_mock(uint32_t points, double rate_hz, char **err);

int32_t wyrm_shutdown(const WyrmHandle *h);
void wyrm_free(WyrmHandle *h);
void wyrm_buf_free(uint8_t *p, size_t len);
void wyrm_string_free(char *s);
const char *wyrm_version(void);

/* Blocks up to timeout_ms. One thread at a time; not on a UI thread. */
int32_t wyrm_next_event(const WyrmHandle *h, uint32_t timeout_ms, uint8_t **out, size_t *out_len);

int32_t wyrm_meta(const WyrmHandle *h, uint64_t id, const char *key);
int32_t wyrm_children(const WyrmHandle *h, uint64_t id, const char *key);
int32_t wyrm_list(const WyrmHandle *h, uint64_t id, const char *key);
int32_t wyrm_subscribe(const WyrmHandle *h, uint64_t id, const char *pattern);
int32_t wyrm_unsubscribe(const WyrmHandle *h, uint64_t id, uint64_t sub);
int32_t wyrm_set(const WyrmHandle *h, uint64_t id, const char *key, const uint8_t *value, size_t len);
int32_t wyrm_invoke(const WyrmHandle *h, uint64_t id, const char *key, const char *action,
                    const uint8_t *args, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* WYRM_H */
