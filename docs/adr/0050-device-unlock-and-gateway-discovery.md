# ADR 0050 — Biometric unlock with device keys, and finding a gateway on the local network

Status: proposed (2026-11-14, owner request). Design: canvas rows *Log in, part 2* (`Unlock*`, `UnlockApp`, `UnlockPlatforms`, `Discover*`). Studio side: `studio/docs/design/specs/unlock-discover.md`. Closes `docs/studio.md` §10 item 13 (gateway info before login).

## Context

Studio logs in to a gateway with a user and a password (`POST /api/login`, a session of `session_ttl`). It remembers the gateway URLs and the user, never the password, so every start asks for it. The owner asks (2026-11-14) for:
1. **Biometric login**, covering every case: Touch ID, Face ID, Windows Hello, Android fingerprint or face, computers with no biometrics, fingerprints that change, a device that is lost, and so on.
2. **Finding a broker on the local network** from the log-in page.

Two constraints come from the platform rules. First, biometrics must not become a weaker password: the gateway decides who is in, not the client (principle 6). Second, nothing on the wire carries secrets or opens the broker to people who could not reach it before. A cached password or a long session token in the OS keychain behind a biometric check would also work, but the gateway could not see or revoke it, and a copied keychain item would replay it. So both are refused.

## Decision

### 1. Device keys: the gateway checks a signature, the device checks the person

1. **Registration.** With a session that used the password within the last 5 minutes, Studio makes a P-256 key pair in the device's secure hardware: the Secure Enclave on macOS and iOS (access control `biometryCurrentSet`), the TPM through Windows Hello, or the Android Keystore with `BIOMETRIC_STRONG`, `setInvalidatedByBiometricEnrollment` and StrongBox when the device has it. Studio then calls `POST /api/devices {name, platform, public_key, attestation?}`. The gateway stores the record `{id, user, user_generation, name, platform, public_key, added, last_used, password_at}` in the users store (users SCHEMA 5), which the standby replicates (ADR 0036). It answers `{device}`.
2. **Unlock.** `POST /api/device/challenge {device}` → `{nonce, exp ≤ 60 s}` (single use, in memory). The OS prompt unlocks the key and Studio signs `wyrm-device-login/1 ‖ site ‖ gateway origin ‖ user ‖ device ‖ nonce`. Then `POST /api/device/login {device, nonce, signature}` → the same session as `/api/login`. The gateway refuses when:
   - the device is unknown or removed;
   - the user's generation moved (a password change signs every device out);
   - `password_at` is older than `password_every_days`;
   - devices are off.
   Each refusal is a distinct code (`device_removed`, `password_changed`, `password_due`, `devices_off`), so Studio can say why (board `UnlockSignedOut`).
3. **Step-up.** When `step_up: config`, every request at `config` level needs a session confirmed in the last 5 minutes. `POST /api/device/confirm {nonce, signature over the request hash}` confirms with the device key; `POST /api/confirm {password}` confirms with the password. A refused request answers `confirm_required` and Studio shows `UnlockStepUp`, then sends the request again.
4. **Idle lock.** Local to Studio: after `lock_after_min` (the gateway's `idle_lock_max_min` caps it), Studio hides the tree and values. Unlocking signs a fresh challenge with `POST /api/device/login {…, session}`, which keeps the session. Without a device key it asks for the password.
5. **Visible and revocable.**
   - `GET /api/devices` lists the user's own devices.
   - `DELETE /api/devices/<id>` removes one, for the user or an admin.
   - `/api/users/<u>/devices` gives an admin everyone's.
   - Studio shows the user's devices in Account › Security and everyone's in Access › Users.
   - Audit records: `device_added`, `device_login`, `device_refused`, `step_up`, `device_removed`.
6. **Policy** (`wyrmd.json5` `gateway.devices`):

   ```json5
   {
     enabled: true,
     max_per_user: 5,
     password_every_days: 30,
     idle_lock_max_min: 30,
     step_up: "config" | "none",
     allow_device_credential: false
   }
   ```

   `GET /api/info` carries it so the log-in page knows what to offer before login. With `allow_device_credential: false`, an Android screen PIN or a Mac's login password never stands in for biometrics; Windows Hello PIN counts as Hello. `enabled: false` does not delete records; it refuses device logins, and Studio removes its key after the refusal.
7. **Never offered:** Linux (no system prompt binds a key), kiosk sessions (no person), and devices whose biometrics are weak (class 2 face on Android) or not enrolled. A future web build uses passkeys (WebAuthn) against the same records: the record format leaves room for that.
8. **Downstream sites** are reached through the gateway of the upstream site, as today. A device key is per gateway, user and device. A standby gateway accepts it because the users store is replicated, and its origin is listed with the main one.

### 2. The gateway announces itself; the log-in page finds it

1. **Announce.** `wyrmd` advertises its gateway by DNS-SD on every non-loopback interface the gateway listens on: service `_wyrm._tcp`, instance name = site. Config `gateway.announce: {enabled: true, interfaces?: [...]}`; hardened sites turn it off. The TXT record has no users and no secrets:

   | TXT key | Value |
   |---|---|
   | `v` | wyrmd version |
   | `site` | site name |
   | `tls` | `1` or `0` |
   | `fp` | first 16 bytes, in hex, of the SHA-256 of the CA certificate the gateway's certificate chains to |
   | `role` | `active` or `standby` (ADR 0036) |
   | `pair` | the other host's `host:port` |
   | `up` | upstream site, when this broker is a downstream |

   The crate is `mdns-sd` (pure Rust, no Avahi or Bonjour dependency). The announcement stops on SIGTERM and moves with a takeover (the new active announces `role=active`).
2. **`GET /api/info`** (public, rate-limited like `/api/login`): `{site, version, tls, ca_fp, role, pair, devices: {enabled, step_up}, min_studio}`. It serves the probe of `login.md` §6, the trust step and the range probe.
3. **Studio finds.**
   - **Find on this network** browses `_wyrm._tcp` for 8 s. It shows one row per site: an active and its standby merge into one row, and `up` shows downstream sites. Each row is checked with `/api/info`.
   - Rows Studio cannot use are shown greyed with the reason: plain `http` off loopback (`insecure_plaintext`), or a wyrmd version older than `min_studio`.
   - Picking a row fills the gateway and its standby.
   - **Trust.** A gateway whose CA the device does not know shows its CA code (`ca_fp` in 8 groups of 4). The person compares it with System › Gateway › *Certificate code* on the broker, or with `wyrmd ca fingerprint` (a new subcommand). Only after that does Studio pin that CA for that origin. Anything on the network can announce a name, so finding never means trusting.
   - **Nothing found.** Studio says why it may be: multicast blocked, local-network permission off, announce off. It offers **Probe a range**: an opt-in `GET /api/info` per address of a CIDR on one port, 16 at a time, at most 1 024 addresses. It also offers typing the address, or a code from the broker's System page.
4. **Platform permissions:**
   - iOS: `NSLocalNetworkUsageDescription` and `NSBonjourServices = [_wyrm._tcp]`.
   - macOS 15: the Local Network prompt.
   - Android: `CHANGE_WIFI_MULTICAST_STATE` and a multicast lock while browsing.
   - Windows and Linux: none (browsing is outbound).

   Flutter package: `bonsoir` (all five platforms).

## Consequences

- Gateway: `devices.rs` (records, challenge cache, verify P-256 ECDSA with `ring::signature::ECDSA_P256_SHA256_ASN1`, `ring` is already in the tree), routes in `http.rs`, users SCHEMA 5, `info` route, `confirm_required` on config requests when `step_up` is on, audit records.
- `wyrmd`: `gateway.devices`, `gateway.announce` with `mdns-sd`, `wyrmd ca fingerprint`; System › Gateway shows the certificate code and a QR (`wyrm://<host:port>?fp=…`).
- Studio: a platform channel per OS for the key (the `local_auth` package alone cannot bind a key; Studio uses a thin plugin over Security.framework, `KeyCredentialManager` and `BiometricPrompt` + Keystore), `bonsoir`, pinned CAs per origin in `storage`.
- Tests:
  - device register and login, plus every refusal code;
  - a password change signs devices out;
  - step-up refused, then confirmed;
  - challenge reuse refused;
  - announce TXT content and its absence with `enabled: false`;
  - `/api/info` without a session;
  - a standby accepts a device registered on the active.

## Not decided here

- Hardware attestation checks (Apple App Attest, Android Key Attestation) as a policy option: recorded when sent, not required.
- Passkeys for a web build.
- Discovery across subnets (an mDNS reflector is the network's job).
