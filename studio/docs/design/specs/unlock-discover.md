# Biometric unlock and finding a gateway

Boards (canvas row *Log in, part 2*, y 20760):
- `UnlockOffer`, `Unlock` (clickable: unlock → system prompt → in), `UnlockPrompt` (macOS), `UnlockWindows`, `UnlockFallback`, `UnlockChanged`, `UnlockSignedOut` (four reasons, clickable), `UnlockLinux`;
- `UnlockLock`, `UnlockStepUp`, `UnlockApp` (Account › Security, clickable), `UnlockPlatforms`;
- `Discover` (clickable), `DiscoverScan`, `DiscoverTrust`, `DiscoverNone`.

`Unlock` takes `platform` = `mac | windows | linux | ios | android`; names, icons and prompts follow it.

Broker side: **ADR 0050** (proposed). This spec adds to `login.md`; the hero, motion and the existing states stay as they are there.

## 1. Platforms
| Platform | Called | Key | Prompt | Offered when |
|---|---|---|---|---|
| macOS | Touch ID | Secure Enclave P-256, `biometryCurrentSet` | LocalAuthentication | a Touch ID sensor with at least one finger |
| Windows | Windows Hello | TPM via `KeyCredentialManager` | Windows Security | Hello set up (face, finger or Hello PIN) |
| iOS, iPadOS | Face ID / Touch ID (by the device) | Secure Enclave, `biometryCurrentSet` | system sheet; `NSFaceIDUsageDescription` | biometrics enrolled |
| Android | Fingerprint / Face (by what is strong) | Keystore (StrongBox if any), `BIOMETRIC_STRONG`, invalidated by enrollment | BiometricPrompt | a class 3 biometric enrolled |
| Linux | — | — | — | never: `UnlockLinux` says so once, then never again |
| Kiosk, web | — | — | — | never (web: passkeys later) |

One plugin in a new package `device_key` (a Flutter plugin package, see *Decided while building*) with a platform channel per OS: `isAvailable() → {kind, name}`, `create(alias) → publicKey`, `sign(alias, bytes, reason) → signature | cancelled | lockout | invalidated`, `delete(alias)`. `local_auth` is not enough: it answers yes/no and cannot bind a key. `invalidated` (fingerprints changed) is its own result. Nothing else in Studio calls the OS.

### Decided while building (2026-11-14, ADR 0029)
- **Package.** `frx add-package` makes only `models`, `http_client` and `storage`, so `studio/device_key` was made by `flutter create --template=plugin --org uk.gencto` and then made a workspace member by hand (`resolution: workspace`, root `workspace:` list). `business` depends on it (the code that calls it) and `app` too (so the app registers the native side). No example app, no pigeon: one `MethodChannel` `uk.gencto.device_key`. `frx doctor` accepts it. CI tests it with the other packages.
- **Dart API.** `DeviceKey` is an interface and `DeviceKey()` gives the platform's. Linux, web and other platforms get `NoDeviceKey` (`none`) in Dart and never call the channel. `create` throws `DeviceKeyException` (`cancelled | lockout | unavailable | failed`). `sign` returns `Signed | SignCancelled | SignLockout | SignInvalidated | SignUnavailable | SignFailed` and never throws. Tests use `FakeDeviceKey` from `package:device_key/testing.dart`: real P-256 keys in Dart (`pointycastle`) and answers that a test sets.
- **macOS, iOS.** CryptoKit `SecureEnclave.P256.Signing.PrivateKey` with `.privateKeyUsage` and `.biometryCurrentSet` (`.userPresence` with `allowDeviceCredential`). The enclave gives the key as `dataRepresentation`, a blob that only this device's enclave can open. The plugin keeps that blob in UserDefaults, not as a keychain item. A permanent keychain key needs `keychain-access-groups`, so it needs a provisioning profile, and the ad-hoc signed build gets `-34018`. So no entitlement is added. The wire is unchanged: the 65-byte X9.63 point and ECDSA P-256 SHA-256 in DER (`es256`). At creation the plugin keeps `evaluatedPolicyDomainState`. When it differs at `sign`, or the blob does not open, the result is `invalidated`, with no prompt. iOS has `NSFaceIDUsageDescription`. The plugin's privacy manifest declares UserDefaults (`CA92.1`).
- **Android.** Keystore EC P-256 is StrongBox-backed when the device has StrongBox, else a plain Keystore key. The key needs a user check for each use and is invalidated by enrollment. The prompt is `BiometricPrompt` with a `CryptoObject(SHA256withECDSA)`. The public key goes out as the 65-byte point. `allowDeviceCredential` adds the device PIN only from API 30, because below it a `CryptoObject` cannot take `DEVICE_CREDENTIAL`. `MainActivity` is a `FlutterFragmentActivity`. The app's Gradle moved to 9.5.0 and AGP to 9.3.1, which Flutter 3.50 needs to build an APK.
- **Windows.** `KeyCredentialManager` (C++/WinRT coroutines on the platform thread). Hello makes RSA-2048 keys only: `rs256`, PKCS#1 public key, the signature as `RequestSignAsync` returns it. Hello shows its own text and always allows the Hello PIN, so `reason` and `allowDeviceCredential` do nothing there. Results: `UserCanceled`/`UserPrefersPassword` → cancelled, `SecurityDeviceLocked` → lockout, `NotFound` → invalidated.

## 2. Log-in page

### Offer (`UnlockOffer`)
After a successful password login and before Welcome, once per gateway, user and device. Conditions: `/api/info` says devices are on, the device offers a strong biometric, and the person never chose *Don't ask on this computer*.
- Content: the check line `Logged in to <site> as <user> · <role>`, the platform icon tile 84 (ember on `#1E1813`), the title `Unlock with <name> next time?`, one line, and four facts with dots. The facts say where the key lives, that it works with the gateway and its standby, when it ends, and the password interval.
- Buttons: `Use <name>` (primary), `Not now`, `Don't ask on this computer`. The policy line comes from `/api/info`.
- `Use` creates the key, registers it (`POST /api/devices`), then goes to Welcome. An error there goes to Welcome anyway, with a quiet toast `Touch ID could not be turned on: <reason>`.

### Unlock (`Unlock`, `UnlockPrompt`, `UnlockWindows`)
On start, when a device key exists for the last gateway and user, the form becomes:
- `Welcome back` / `Unlock to open the tree of <site>.`;
- the account card: initials 44, user · role, `host + standby` with a status dot from the probe, `<name> · <when>` at the right;
- the round button 104 with the platform icon, `Unlock with <name>`, `Or press Enter`;
- links `Use the password` and `Another account or gateway`;
- the footer `Key in <store> · added <date>`.

The system prompt opens on the button, on Enter, and on its own once when the window gets focus, never in a loop. While the gateway checks, the ring spins and the note reads `Checking the key with <site>…`. Success goes to Welcome (§5 of `login.md`).

### When it does not work
| Case | Comes from | Board | Shows |
|---|---|---|---|
| Cancel, or 3 misses, or OS lockout | `sign` → `cancelled` / `lockout` | `UnlockFallback` | amber notice `<name> did not match 3 times`, password for the user, key kept |
| Fingerprints or faces changed | `sign` → `invalidated` | `UnlockChanged` | amber notice, password, `Turn <name> on again after I log in` (on); Studio deletes the key and the device record (`DELETE /api/devices/<id>` after the login) |
| Removed by an admin / password changed / 30 days / devices off | `/api/device/login` → `device_removed` / `password_changed` / `password_due` / `devices_off` | `UnlockSignedOut` | coral notice with the reason's own words; re-enable offered except for `devices_off` |
| No biometrics here | `isAvailable` → none | `UnlockLinux` | grey notice once, the password form as today |
| Gateway unreachable | probe | `login.md` unreachable state | as today; the key is not tried |

## 3. Inside Studio
- **Idle lock (`UnlockLock`).** Account › Security sets the lock delay: off / 5 / 15 / 30 min, capped by `idle_lock_max_min`. After it, the shell blurs (14 px, saturation 0.6) under a dimmer `rgba(14,17,19,0.72)`. Live value streams pause their drawing, not their subscriptions, and no values are in the semantics tree. A card offers `Unlock with <name>`, `Use the password` and `Log out`. *Review and apply* keeps its changes.
- **Step-up (`UnlockStepUp`).** A request refused with `confirm_required` opens a dialog listing what is being applied, with level badges. `Confirm with <name>` signs the request hash; `Use the password` shows a password field in the dialog. After the confirm, the same request goes again. A step-up is good for 5 minutes, and only one dialog shows at a time.
- **Account › Security (`UnlockApp`).** Opened from the avatar menu. *On this computer*:
  - `Unlock with <name>` switch (off removes the key and the device record);
  - `Lock Studio after` select;
  - `Confirm before config changes`, read-only when the gateway forces it.

  *Your devices on <site>* lists name, method, last used and a tag (`this device`, `password due in n days`, `removed by <admin>`), with `Turn off` (this device), `Remove` or `Forget`. `Sign out everywhere` bumps the user generation, through the existing user op. A line states the gateway's policy.
- **Access › Users.** For an admin, each user row gains a device count; the user drawer lists the devices with Remove.

## 4. Finding a gateway (`Discover*`)
- The gateway field gets a button `Find on this network` (46 high, radar icon). It toggles a panel under the field, which takes the place of the recent chips while it is open.
- **Looking (`DiscoverScan`).** The panel title is `Looking on Wi-Fi "<ssid>" (<subnet>)…`, with the ssid when the OS gives it, else the interface. Rows appear as they answer; the browse lasts 8 s. `Look again` starts it over.
- **Rows (`Discover`).** Each row has a dot, the site in bold, tags, the hosts in mono, a note and the time it was seen:
  - tag `used before` (teal) when the origin is in the recent list;
  - `active + standby` (ember) when two hosts announce one site with `pair`;
  - `downstream of <up>` (grey) for `up`;
  - `new` (amber) for a CA not pinned or trusted by the OS;
  - `plain http` (coral, row disabled) and versions below `min_studio` (disabled, with the reason).

  Picking a row fills the gateway field and the standby, and the status line says `<site> · picked from this network · standby filled in`.
- **Trust (`DiscoverTrust`).** For a row tagged `new`, an amber card replaces the panel: `First time on <site> · check its certificate`, one line on why, the code in a 4 × 2 grid of mono groups, and where to find it on the broker. `It matches · trust <site>` pins that CA for that origin in `storage`; `Cancel` goes back to the list. Until then the form below is dimmed (40 %) and the footer reads `TLS · <site> CA, not trusted yet`.
- **Nothing (`DiscoverNone`).** `No gateway answered on Wi-Fi "<ssid>" in 8 s`, with four reasons:
  - multicast blocked;
  - no local-network permission, with `Open settings` (macOS, iOS);
  - announce off;
  - you can type the address.

  Then **Probe a range**: CIDR and port (default the last port used), `Probe`, and a line on what it does. It finds the same rows through `/api/info`.
- **Mobile.** The empty state has `Scan a code`, which reads the QR on System › Gateway (`wyrm://host:port?fp=…`) and fills the field and the pin at once.

## 5. Calls
| UI | Call |
|---|---|
| What to offer, row details, probe | `GET /api/info` |
| Offer → register | `POST /api/devices {name, platform, public_key}` |
| Unlock, idle unlock | `POST /api/device/challenge` → `POST /api/device/login` |
| Step-up | `POST /api/device/confirm` or `POST /api/confirm` |
| Account › Security | `GET /api/devices`, `DELETE /api/devices/<id>` |
| Access › Users | `GET /api/users/<u>/devices` |
| Find | DNS-SD browse `_wyrm._tcp` (`bonsoir`) |

New state through `frx`: a substate `device` (`available`, `kind`, `name`, `keyId`, `deviceId`, `lockAfter`, `dontAsk`), a substate `discovery` (`scanning`, `found` as a map of site → `FoundGateway` model, `trustPending`), and pinned CAs in the storage package. Actions: `OfferDeviceAction`, `UnlockWithDeviceAction`, `ConfirmStepUpAction`, `LockAction`, `RemoveDeviceAction`, `FindGatewaysAction` (the service `GatewayBrowserService` dispatches found rows), `ProbeRangeAction`, `TrustGatewayAction`.

## 6. Checklist
- [x] `device_key` plugin on macOS, Windows, iOS, Android; `isAvailable` none on Linux (Windows written, not yet compiled).
- [ ] Offer once, `Not now`, `Don't ask on this computer`.
- [ ] Unlock with the prompt; auto-prompt once on focus; Enter.
- [ ] Fallback, changed, signed-out (4 codes), Linux.
- [ ] Idle lock hides values; Review and apply kept.
- [ ] Step-up on `confirm_required`, then the request again.
- [ ] Account › Security and Access › Users devices.
- [x] Find: browse, merge active + standby, tags, disabled rows, Look again.
- [x] Trust with the code; pin per origin; footer states.
- [x] Nothing found: reasons, Open settings, Probe a range; Scan a code on mobile deferred (§7, 12).
- [ ] Permissions in each platform's manifest; `frx doctor`, `dart analyze`; goldens for the 16 frames.

## 7. Decided while building (Find, 2026-11-14, ADR 0029)
The ADR and §4 left these open; the rule below is the one built (`business/lib/wyrm/discovery.dart`, the `discovery` actions).

1. **The row's URL** follows ADR 0050 decision 10: the address when the certificate's `names` list it, else the mDNS host name when listed, else the first DNS name. A name that does not resolve here keeps the address as `connectTo`. Every connection to that origin then connects to the address and checks the certificate against the name. A certificate that names neither gets no URL (`noName`).
2. **The code** is computed by Studio from the `ca` DER it would pin, never taken from `ca_fp`. A row is refused (`codeMismatch`) when `ca_fp` or the TXT `fp` differs from it.
3. **Trusting** (`TrustGatewayAction`) reads `/api/info` twice and stores nothing until both pass:
   - with the accept-any client (no secret is sent): the CA must still be the one whose code was shown, and `ca_fp` must match;
   - with the new pin alone: the gateway's certificate must chain to that CA and name the URL's host.

   A refusal keeps the card with its reason (`changed`, `mismatch`, `chain`, `no_answer`).
4. **A pin** covers the row's origin and its standby's origin (from `pair`) with the same CA; the standby is not contacted then. A pinned origin trusts that CA and no other, not the system's roots. The probe (`login.md` §6), the login and the WebSocket use the same client (`GatewayTrust`), so a pinned gateway answers all three.
5. **Known CA, other site.** A row whose CA is already pinned for another origin is not `new`. Its note reads `signed by the <site> CA (known)`, and picking it pins it after the same two reads, with no code step: the person checked that CA before.
6. **A CA trusted by the system** with a name that resolves needs no pin. One whose name does not resolve asks for the code, so the address is kept with the pin. TLS with no CA to check and a certificate the system does not trust is disabled (`noCa`).
7. **Pins stay with Remember off.** A pin is a trust decision taken after comparing a code. It holds no secret, and dropping it would ask for the code at every start. They are stored with `PinnedCas` (`storage`, key `pinnedCas`).
8. **Disabled rows** say why:
   - plain `http` off loopback (`plainHttp`);
   - no `/api/info`: a 404 or not CBOR (`noInfo`: a wyrmd older than Studio needs). There is no separate wyrmd version floor;
   - `min_studio` above this Studio's version (`studioTooOld`; `studioRelease` follows `app/pubspec.yaml`, and a test checks it);
   - no answer (`noAnswer`).

   Usable rows sort first, then by site.
9. **Merging by site.** The same host again replaces its row and keeps the standby. A second host of a site becomes the standby of the usable one, else of the one whose `/api/info` says `role: active`. *Used before* compares origins with each URL of each recent entry (an entry is a `main, standby` list).
10. **The panel title** names the interface and the /24 around its IPv4 address (`en0 (10.0.7.0/24)`), not the Wi-Fi name. The SSID needs location permission on iOS and Android, and Dart on the desktop does not expose it. The same /24 is the default range.
11. **Probe a range**:
    - IPv4 only. A block may hold at most 1 024 addresses (a /22); its network and broadcast addresses are left out;
    - 16 requests at a time, 1.5 s each. HTTPS comes first, then plain HTTP when the port does not speak TLS;
    - only addresses that answer become rows;
    - the default port is the one in the gateway field, else 8446;
    - the range and the port are checked as they are typed, and the line under them says what is wrong.
12. **Scan a code is deferred.** No QR scanner is added this round: `mobile_scanner` brings ML Kit and a camera permission into every Android and iOS build, and the mobile builds do not ship yet. `parseGatewayCode('wyrm://host:port?fp=…')` exists and is tested. When a scanner lands, a scanned code fills the field, and the code computed from the fetched CA must equal `fp` before the pin is stored (no comparing by eye). Until then the card does not say *On a phone: scan the code*.
13. **Open settings** opens *Privacy & Security › Local Network* on macOS and the app's settings on iOS (`url_launcher`). Other platforms show the reason without the link.
14. **Layout.** While the panel or the card is open, the form is the boards' compact one: user and password side by side, *Remember* hidden, and the form panel 560 wide (content 460). *Find on this network* is also on the plain log-in page, beside the field, so the `Login*` goldens show it.
15. **Browsing** lasts 8 s (`bonsoir`; on Android it takes the multicast lock). *Look again* starts over and drops late answers of the last search, and so does a range probe. Closing the panel stops the browse.
16. **Apple platforms refuse a TLS certificate** valid for more than 825 days that was issued after July 2019, even under a pin. Certificates made by `wyrmd` start in 1975 and pass. A gateway certificate made by hand must keep within 825 days, or Studio on macOS and iOS says `certificate is not trusted`.

