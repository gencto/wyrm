#!/usr/bin/env python3
"""The client side of the QEMU smoke test of a board image (smoke.sh, ADR 0051 §3).

It speaks to the gateway as a person's first client does: `GET /api/info` over TLS
without trust, the `setup_proof` checked against the setup code and the CA the gateway
presents, then that CA pinned and every later request sent over a verified connection
(the CA and one of the certificate's names). Bodies are canonical CBOR.

Standard library only; run it as `python3 -I smoke_client.py`.

  entry <index.json> <board> <field>   a field of the board's index entry (`a.b`: field b
                                       of field a); fails when it is not there
  wait <port> <seconds>                until a TLS handshake succeeds; prints the seconds
  closed <port>                        exit 0 when no TLS handshake succeeds (three tries)
  setup <port> <state dir>             the first admin: env SMOKE_CODE, SMOKE_USER,
                                       SMOKE_PASSWORD; the CA and its name go to <state dir>
  login <port> <state dir>             a login over the pinned CA, after a restart

The code and the password come from the environment, never from argv.
"""

import base64
import hashlib
import hmac
import http.client
import json
import os
import socket
import ssl
import struct
import sys
import time

HOST = "127.0.0.1"
# wyrm_core::setup
LABEL = b"wyrm-setup-v1\n"
PROOF_LABEL = b"wyrm-setup-proof-v1\n"


def fail(msg):
    print(f"smoke_client: FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def say(msg):
    print(f"smoke_client: {msg}", flush=True)


# ---- canonical CBOR, the subset the gateway uses -------------------------------------


def _head(major, n):
    if n < 24:
        return bytes([major << 5 | n])
    if n < 0x100:
        return bytes([major << 5 | 24, n])
    if n < 0x10000:
        return bytes([major << 5 | 25]) + struct.pack(">H", n)
    if n < 0x100000000:
        return bytes([major << 5 | 26]) + struct.pack(">I", n)
    return bytes([major << 5 | 27]) + struct.pack(">Q", n)


def cbor_encode(v):
    if isinstance(v, bool):
        return b"\xf5" if v else b"\xf4"
    if isinstance(v, int) and v >= 0:
        return _head(0, v)
    if isinstance(v, int):
        return _head(1, -1 - v)
    if isinstance(v, bytes):
        return _head(2, len(v)) + v
    if isinstance(v, str):
        b = v.encode()
        return _head(3, len(b)) + b
    if isinstance(v, list):
        return _head(4, len(v)) + b"".join(cbor_encode(x) for x in v)
    if isinstance(v, dict):
        # canonical: keys ordered by their encoded bytes
        items = sorted((cbor_encode(k), cbor_encode(x)) for k, x in v.items())
        return _head(5, len(items)) + b"".join(k + x for k, x in items)
    raise TypeError(type(v))


def cbor_decode(data):
    value, end = _item(data, 0)
    if end != len(data):
        fail(f"CBOR: {len(data) - end} bytes after the item")
    return value


def _item(d, i):
    ib = d[i]
    major, info = ib >> 5, ib & 31
    i += 1
    if info < 24:
        n = info
    elif info in (24, 25, 26, 27):
        size = 1 << (info - 24)
        raw = d[i : i + size]
        i += size
        if major == 7:
            if info == 25:
                return struct.unpack(">e", raw)[0], i
            if info == 26:
                return struct.unpack(">f", raw)[0], i
            if info == 27:
                return struct.unpack(">d", raw)[0], i
        n = int.from_bytes(raw, "big")
    else:
        fail("CBOR: indefinite lengths are not canonical")
    if major == 0:
        return n, i
    if major == 1:
        return -1 - n, i
    if major == 2:
        return bytes(d[i : i + n]), i + n
    if major == 3:
        return d[i : i + n].decode(), i + n
    if major == 4:
        out = []
        for _ in range(n):
            x, i = _item(d, i)
            out.append(x)
        return out, i
    if major == 5:
        out = {}
        for _ in range(n):
            k, i = _item(d, i)
            x, i = _item(d, i)
            out[k] = x
        return out, i
    if major == 6:
        return _item(d, i)
    return {20: False, 21: True, 22: None}.get(n), i


# ---- the setup code (wyrm_core::setup) ------------------------------------------------


def code_hash(code):
    plain = code.replace("-", "").replace(" ", "").upper()
    if len(plain) != 26:
        return None
    try:
        raw = base64.b32decode(plain + "======")
    except ValueError:
        return None
    if len(raw) != 16:
        return None
    return hashlib.sha256(LABEL + raw).digest()


def proof_ok(code, ca_der, proof):
    h = code_hash(code)
    if h is None:
        return False
    want = hmac.new(h, PROOF_LABEL + ca_der, hashlib.sha256).digest()
    return hmac.compare_digest(want, proof)


# ---- HTTPS ----------------------------------------------------------------------------


def unverified():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    # the gateway speaks TLS 1.2 and 1.3 (rustls) and nothing older
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def pinned(ca_der):
    """Trusts the one CA and nothing else (no system roots)."""
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_verify_locations(cadata=ca_der)
    return ctx


class Conn(http.client.HTTPConnection):
    """Connects to HOST:port, verifies the certificate against `name` (SNI too)."""

    def __init__(self, port, ctx, name, timeout=90):
        super().__init__(HOST, port, timeout=timeout)
        self.ctx = ctx
        self.name = name

    def connect(self):
        sock = socket.create_connection((HOST, self.port), self.timeout)
        self.sock = self.ctx.wrap_socket(sock, server_hostname=self.name)


def request(port, ctx, name, method, path, body=None, session=None):
    c = Conn(port, ctx, name)
    headers = {"Connection": "close"}
    data = None
    if body is not None:
        data = cbor_encode(body)
        headers["Content-Type"] = "application/cbor"
    if session is not None:
        headers["Authorization"] = f"Bearer {session}"
    c.request(method, path, body=data, headers=headers)
    r = c.getresponse()
    raw = r.read()
    c.close()
    value = cbor_decode(raw) if raw and r.getheader("content-type", "").startswith("application/cbor") else raw
    return r.status, value


def handshake(port, ctx=None, name=None, timeout=5):
    sock = socket.create_connection((HOST, port), timeout)
    try:
        tls = (ctx or unverified()).wrap_socket(sock, server_hostname=name)
        tls.close()
    finally:
        sock.close()


# ---- the steps ------------------------------------------------------------------------


def info(port, ctx, name):
    status, v = request(port, ctx, name, "GET", "/api/info")
    if status != 200 or not isinstance(v, dict):
        fail(f"GET /api/info: HTTP {status} {v!r}")
    return v


def shown(v):
    """The fields of `info` worth a log line; bytes as their length."""
    out = {}
    for k, x in sorted(v.items()):
        out[k] = f"<{len(x)} bytes>" if isinstance(x, bytes) else x
    return json.dumps(out, sort_keys=True)


def env(name):
    value = os.environ.get(name)
    if not value:
        fail(f"{name} is not set")
    return value


def site_name(names):
    """The name of the certificate a client that found the device by mDNS checks."""
    for n in names:
        if n.startswith("wyrm-") and n.endswith(".local"):
            return n
    for n in names:
        if not n.replace(".", "").replace(":", "").isdigit():
            return n
    fail(f"no DNS name among the certificate's names {names}")


def login(port, ctx, name, user, password):
    status, v = request(port, ctx, name, "POST", "/api/login", {"user": user, "password": password})
    if status != 200 or not isinstance(v, dict) or "session" not in v:
        fail(f"POST /api/login: HTTP {status} {v!r}")
    say(f"POST /api/login: HTTP {status}, a session until {v.get('exp')}")
    status, me = request(port, ctx, name, "GET", "/api/me", session=v["session"])
    if status != 200 or not isinstance(me, dict) or me.get("sub") != user:
        fail(f"GET /api/me: HTTP {status} {me!r}")
    say(f"GET /api/me: HTTP {status}, sub {me['sub']}, roles {me.get('roles')}")
    status, _ = request(port, ctx, name, "POST", "/api/login", {"user": user, "password": password + "x"})
    if status == 200:
        fail("a wrong password logs in")
    say(f"POST /api/login with a wrong password: HTTP {status}")


def cmd_setup(port, state):
    code, user, password = env("SMOKE_CODE"), env("SMOKE_USER"), env("SMOKE_PASSWORD")
    first = info(port, unverified(), None)
    say(f"GET /api/info (not yet trusted): {shown(first)}")
    if first.get("setup") is not True:
        fail("info has no `setup: true`")
    ca, proof = first.get("ca"), first.get("setup_proof")
    if not isinstance(ca, bytes) or not isinstance(proof, bytes):
        fail("info has no `ca` or no `setup_proof`")
    if not proof_ok(code, ca, proof):
        fail("setup_proof does not verify with the setup code and the presented CA")
    other = "AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AA"
    if proof_ok(other, ca, proof) or proof_ok(code, ca + b"\0", proof):
        fail("setup_proof verifies with another code or another CA: the check proves nothing")
    say("setup_proof verifies with the code and the presented CA (and not with another code or CA)")
    name = site_name(first.get("names") or [])
    ctx = pinned(ca)
    # from here on only the pinned CA and the certificate's name are trusted
    handshake(port, ctx, name)
    say(f"the CA is pinned: TLS verifies for {name} ({first.get('ca_fp')})")

    status, v = request(port, ctx, name, "POST", "/api/setup", {"code": code, "user": user, "password": password})
    if status != 204:
        fail(f"POST /api/setup: HTTP {status} {v!r}")
    say(f"POST /api/setup: HTTP {status}")
    after = info(port, ctx, name)
    if "setup" in after or "setup_proof" in after:
        fail(f"info still offers a setup: {shown(after)}")
    say("GET /api/info: no setup offered any more")
    status, v = request(port, ctx, name, "POST", "/api/setup", {"code": code, "user": user + "2", "password": password})
    if status == 204 or not isinstance(v, dict) or v.get("code") != "no_setup":
        fail(f"a second POST /api/setup: HTTP {status} {v!r}")
    say(f"a second POST /api/setup: HTTP {status} {v.get('code')}")
    login(port, ctx, name, user, password)

    with open(os.path.join(state, "ca.der"), "wb") as f:
        f.write(ca)
    with open(os.path.join(state, "gateway.json"), "w") as f:
        json.dump({"name": name, "ca_fp": first.get("ca_fp")}, f)


def cmd_login(port, state):
    user, password = env("SMOKE_USER"), env("SMOKE_PASSWORD")
    with open(os.path.join(state, "ca.der"), "rb") as f:
        ca = f.read()
    with open(os.path.join(state, "gateway.json")) as f:
        saved = json.load(f)
    ctx, name = pinned(ca), saved["name"]
    v = info(port, ctx, name)
    say(f"GET /api/info over the pinned CA: {shown(v)}")
    if v.get("ca_fp") != saved["ca_fp"] or v.get("ca") != ca:
        fail(f"the CA changed: {v.get('ca_fp')} after {saved['ca_fp']}")
    if "setup" in v:
        fail("info offers a setup again")
    say("the same CA and no setup: the site's data was kept")
    login(port, ctx, name, user, password)


def cmd_wait(port, seconds):
    start = time.monotonic()
    last = None
    while time.monotonic() - start < seconds:
        try:
            handshake(port)
            print(int(time.monotonic() - start))
            return
        except (OSError, ssl.SSLError) as e:
            last = e
            time.sleep(3)
    fail(f"no TLS on port {port} within {seconds} s ({last})")


def cmd_closed(port):
    for n in range(3):
        try:
            handshake(port)
        except (OSError, ssl.SSLError) as e:
            say(f"port {port}, try {n + 1}: no TLS ({type(e).__name__}: {e})")
            time.sleep(2)
            continue
        fail(f"port {port} answers TLS")


def main(argv):
    if len(argv) == 4 and argv[0] == "entry":
        with open(argv[1]) as f:
            index = json.load(f)
        for e in index["images"]:
            if e["board"] == argv[2]:
                for key in argv[3].split("."):
                    if not isinstance(e, dict) or key not in e:
                        fail(f"board {argv[2]} of {argv[1]} has no field {argv[3]}")
                    e = e[key]
                print(e)
                return
        fail(f"no board {argv[2]} in {argv[1]}")
    elif len(argv) == 3 and argv[0] == "wait":
        cmd_wait(int(argv[1]), int(argv[2]))
    elif len(argv) == 2 and argv[0] == "closed":
        cmd_closed(int(argv[1]))
    elif len(argv) == 3 and argv[0] == "setup":
        cmd_setup(int(argv[1]), argv[2])
    elif len(argv) == 3 and argv[0] == "login":
        cmd_login(int(argv[1]), argv[2])
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
