#!/usr/bin/env bash
# Scheduler load on a running demo site (ADR 0022 "Benchmarks"; docs/scheduler.md):
#
#   1. idle:     N schedules with one daily event each, every window at least 10 min
#                away; `wyr sub wy/<site>/downstream/scheduler/**` for IDLE_S seconds
#                counts the samples (expected 0), then the schedules go;
#   2. latency:  one schedule of MOMENTS moment events one second apart (values 1, 2, …)
#                with an `ack` target on a mock point; the arrival of each value at
#                `<s>/current` and at the point minus its scheduled time → p50/p99;
#   3. feedback: a target on plc1/line1/ahu1/fan with `confirm: feedback` on
#                plc1/line1/ahu1/fan_status → `confirmed`; a write of `false` by hand →
#                `override`; the next transition writes `true` again → `confirmed`.
#
#   examples/demo/run.sh                     # in another terminal
#   examples/demo/scheduler-load.sh          # edge: all three
#   N=3 MOMENTS=5 IDLE_S=5 examples/demo/scheduler-load.sh     # a short smoke run
#   PHASES=latency SITE=central GATEWAY=http://127.0.0.1:8445 ROUTER=tcp/127.0.0.1:7447 \
#     examples/demo/scheduler-load.sh
#
# The demo has no admin_keys, so `wyr invoke`/`wyr set` on the router are refused.
# Actions and the write by hand go through the site's gateway as the user `admin`
# (`wyr probe --file`, generated scenarios; WYR_GATEWAY_PASSWORD); values are read with
# `wyr sub` on the router (loopback reads need no token). The scheduler's responder allows
# one caller 50 requests per second (burst 100): the scenarios pause 1 s after every 40
# actions. Everything the script creates is removed at the end, also after a failure,
# Ctrl+C or SIGTERM: a schedule that a list still shows is removed again (three tries),
# and the mock point is reset. The exit code is 1 when a schedule is still there.
#
# Needs: target/release/wyr (cargo build --release -p wyr), python3, the demo running.
# Phase 3 needs the point fan_status of edge.json5 (restart the demo after pulling it).
set -euo pipefail
cd "$(dirname "$0")"
export WYR=${WYR:-../../target/release/wyr}
export SITE=${SITE:-edge}
export GATEWAY=${GATEWAY:-http://127.0.0.1:8444}
export ROUTER=${ROUTER:-tcp/127.0.0.1:7457}
export N=${N:-1000}
export MOMENTS=${MOMENTS:-100}
export IDLE_S=${IDLE_S:-60}
export PHASES=${PHASES:-idle,latency,feedback}
export MOCK_POINT=${MOCK_POINT:-downstream/mock/g0/g0/p0}
export WYR_GATEWAY_PASSWORD=${WYR_GATEWAY_PASSWORD:-wyrm-demo-1}
[[ -x $WYR ]] || { echo "no $WYR: cargo build --release -p wyr" >&2; exit 1; }

exec python3 -I -u - <<'PY'
import datetime as dt
import json
import math
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time

WYR, SITE, GATEWAY, ROUTER = (os.environ[k] for k in ("WYR", "SITE", "GATEWAY", "ROUTER"))
N, MOMENTS, IDLE_S = (int(os.environ[k]) for k in ("N", "MOMENTS", "IDLE_S"))
PHASES = set(os.environ["PHASES"].split(","))
ROOT = f"wy/{SITE}/downstream/scheduler"
POINT = f"wy/{SITE}/{os.environ['MOCK_POINT']}"
FAN = f"wy/{SITE}/downstream/plc1/line1/ahu1/fan"
FAN_STATUS = f"{FAN}_status"
# at most 100 events per schedule; the node budget holds 1 000 schedules of one event
assert 1 <= MOMENTS <= 100, "MOMENTS: 1 to 100"
assert 1 <= N <= 1000, "N: 1 to 1000"
WORK = tempfile.mkdtemp(prefix="scheduler-load-")
LOG = os.path.join(WORK, "probe.log")
PACE = 40  # actions before each 1 s pause (the responder allows 50/s, burst 100)
CHUNK = 450  # steps per scenario file (a scenario holds at most 500)


def utc_now():
    return dt.datetime.now(dt.timezone.utc)


def local(t):
    """A UTC instant as the schedule's local text (tz UTC), seconds only when not zero."""
    return t.strftime("%Y-%m-%dT%H:%M:%S" if t.second else "%Y-%m-%dT%H:%M")


def paced(steps):
    """A 1 s pause after every PACE actions."""
    out, n = [], 0
    for s in steps:
        out.append(s)
        if "invoke" in s or "set" in s:
            n += 1
            if n % PACE == 0:
                out.append({"sleep_ms": 1000})
    return out


def probe(name, steps, quiet=True):
    """Runs `steps` through the gateway in scenario files of at most CHUNK steps: whether
    every step passed, and the reports (also in LOG, and on stdout unless quiet)."""
    ok, text = True, ""
    for i in range(0, len(steps), CHUNK):
        path = os.path.join(WORK, f"{name}-{i // CHUNK}.json")
        with open(path, "w") as f:
            json.dump({"name": name, "description": "scheduler-load.sh", "steps": steps[i:i + CHUNK]}, f)
        r = subprocess.run(
            [WYR, "probe", "--file", path, "--gateway", GATEWAY, "--site", SITE],
            capture_output=True, text=True)
        text += r.stdout
        with open(LOG, "a") as log:
            log.write(r.stdout + r.stderr)
        if not quiet:
            print(r.stdout, end="")
        if r.returncode != 0:
            ok = False
            if quiet:
                bad = [l for l in r.stdout.splitlines() if " fail " in l or "error" in l.lower()]
                print("\n".join(bad[:10]) or r.stderr.strip(), file=sys.stderr)
    return ok, text


subs = []  # the `wyr sub` processes running


class Sub:
    """`wyr sub <pattern>` on the router; every line with its arrival time (time.time())."""

    def __init__(self, pattern):
        self.lines = []
        self.p = subprocess.Popen([WYR, "--connect", ROUTER, "sub", pattern],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        subs.append(self)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in iter(self.p.stdout.readline, ""):
            self.lines.append((time.time(), line.rstrip("\n")))

    def stop(self):
        if self in subs:
            subs.remove(self)
            self.p.terminate()
            self.p.wait()

    def samples(self, since=0.0):
        """(arrival, key, value text) of the lines after `since`."""
        out = []
        for t, line in list(self.lines):
            if t >= since and " = " in line:
                key, rest = line.split(" = ", 1)
                out.append((t, key, rest.split(" ")[0]))
        return out


def pct(xs, p):
    xs = sorted(xs)
    return xs[max(0, math.ceil(p / 100 * len(xs)) - 1)]


# schedules this script gives a target `t1`: a schedule with targets is not removed, so the
# target goes first (it needs config, as its import or add_target did)
TARGETED = {"load_lat", "load_fan"}


def remove(ids):
    steps = []
    for i in ids:
        if i in TARGETED:
            steps.append({"invoke": f"{ROOT}/{i}/targets/t1", "action": "remove",
                          "cleanup": True})
        steps.append({"invoke": f"{ROOT}/{i}", "action": "remove", "cleanup": True})
    return paced(steps)


def present(ids):
    """The ids of `ids` that are still schedules of the site (a list on the router); all of
    them when the list fails."""
    r = subprocess.run([WYR, "--connect", ROUTER, "--timeout", "10", "list", ROOT],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return list(ids)
    names = {line.split()[0] for line in r.stdout.splitlines() if line.strip()}
    return [i for i in ids if i in names]


def forget_removed(ids):
    """Takes the ids of `ids` that are gone out of `created`; True when none is left."""
    left = set(present(ids))
    created[:] = [c for c in created if c not in ids or c in left]
    return not left


created = []  # schedules this run made and has not seen removed
mock_written = False  # the mock point holds a written value until `reset`
report = []


def schedule_json(sid, default, events, targets=()):
    return json.dumps({
        "format": "wyrm-schedule/1", "id": sid, "display": sid, "tz": "UTC",
        "default": default, "enabled": True, "next_event": len(events) + 1,
        "events": [dict(e, id=f"e{k + 1}") for k, e in enumerate(events)],
        "targets": list(targets), "next_target": len(targets) + 1,
    })


def idle():
    base = utc_now().replace(second=0, microsecond=0) + dt.timedelta(minutes=10)
    ids = [f"load_{i}" for i in range(N)]
    steps = []
    for i, sid in enumerate(ids):
        start = base + dt.timedelta(minutes=i)
        ev = {"value": 1, "start": local(start), "end": local(start + dt.timedelta(minutes=1)),
              "recurrence": "FREQ=DAILY"}
        steps.append({"invoke": ROOT, "action": "import",
                      "args": {"json": schedule_json(sid, 0, [ev]), "overwrite": True}})
    created.extend(ids)
    t = time.time()
    if not probe("load-idle", paced(steps))[0]:
        raise SystemExit("idle: creating the schedules failed (see the log)")
    print(f"idle: {N} schedules made in {time.time() - t:.1f} s")
    sub = Sub(f"{ROOT}/**")
    time.sleep(10)  # the stored values of every node come first
    mark = time.time()
    replayed = len(sub.samples())
    time.sleep(IDLE_S)
    live = sub.samples(mark)
    sub.stop()
    keys = sorted({k for _, k, _ in live})
    report.append(f"idle: {N} schedules, {replayed} stored values at subscribe, "
                  f"{len(live)} samples in {IDLE_S} s (expected 0)"
                  + (f"; keys: {', '.join(keys[:5])}" if keys else ""))
    t = time.time()
    probe("load-idle-remove", remove(ids))
    if forget_removed(set(ids)):
        print(f"idle: removed in {time.time() - t:.1f} s")
    else:
        print("idle: some schedules are still there; the cleanup tries again", file=sys.stderr)


def latency():
    sid = "load_lat"
    t0 = utc_now().replace(microsecond=0) + dt.timedelta(seconds=40)
    events = [{"value": k, "start": local(t0 + dt.timedelta(seconds=k - 1)),
               "end": local(t0 + dt.timedelta(seconds=k - 1))} for k in range(1, MOMENTS + 1)]
    global mock_written
    target = {"id": "t1", "point": POINT, "confirm": "ack", "enabled": True}
    created.append(sid)
    mock_written = True
    if not probe("load-lat", [{"invoke": ROOT, "action": "import",
                               "args": {"json": schedule_json(sid, 0, events, [target]),
                                        "overwrite": True}}])[0]:
        raise SystemExit("latency: import failed (see the log)")
    cur, pt = Sub(f"{ROOT}/{sid}/current"), Sub(POINT)
    wait = (t0 - utc_now()).total_seconds() + MOMENTS + 3
    print(f"latency: {MOMENTS} moments from {t0.isoformat()}, waiting {wait:.0f} s")
    time.sleep(max(0, wait))
    cur.stop()
    pt.stop()
    for name, sub in (("current", cur), ("point", pt)):
        first = {}
        for t, _, v in sub.samples():
            try:
                x = float(v)
            except ValueError:
                continue
            k = round(x)
            if abs(x - k) < 1e-9 and 1 <= k <= MOMENTS and k not in first:
                first[k] = t
        lat = [(first[k] - (t0.timestamp() + k - 1)) * 1000 for k in sorted(first)]
        if lat:
            report.append(f"latency ({name}, {POINT if name == 'point' else sid + '/current'}): "
                          f"{len(lat)}/{MOMENTS} arrived, p50 {pct(lat, 50):.1f} ms, "
                          f"p99 {pct(lat, 99):.1f} ms, max {max(lat):.1f} ms")
        else:
            report.append(f"latency ({name}): no value arrived")
    ok, _ = probe("load-lat-remove", remove([sid]) + [
        {"invoke": f"wy/{SITE}/downstream/mock", "action": "reset", "cleanup": True}])
    forget_removed({sid})
    mock_written = not ok


def feedback():
    sid = "load_fan"
    now = utc_now().replace(microsecond=0)
    t1 = now + dt.timedelta(seconds=45)
    t = f"{ROOT}/{sid}/targets/t1"
    steps = [
        {"require": FAN_STATUS},
        {"set": FAN, "value": False},
        {"invoke": ROOT, "action": "add_schedule", "args": {"id": sid, "tz": "UTC", "default": False}},
        {"sub": f"{ROOT}/{sid}/**"},
        {"sub": FAN},
        # true until t1, then true again from another event: a transition at t1
        {"invoke": f"{ROOT}/{sid}", "action": "add_event",
         "args": {"value": True, "start": local(now - dt.timedelta(minutes=1)), "end": local(t1)}},
        {"invoke": f"{ROOT}/{sid}", "action": "add_event",
         "args": {"value": True, "start": local(t1), "end": local(t1 + dt.timedelta(minutes=10))}},
        # confirm is the index of the enum: 0 read_back, 1 feedback, 2 ack
        {"invoke": f"{ROOT}/{sid}", "action": "add_target",
         "args": {"point": FAN, "confirm": 1, "feedback": FAN_STATUS}},
        {"value": t, "equals": "confirmed", "within_ms": 15000},
        {"value": FAN, "equals": True},
        # a person switches the fan off: the person wins until the next transition
        {"set": FAN, "value": False},
        {"value": t, "equals": "override", "within_ms": 10000},
        {"value": t, "equals": "confirmed", "within_ms": 60000},
        {"value": FAN, "equals": True},
        {"invoke": t, "action": "remove", "cleanup": True},
        {"invoke": f"{ROOT}/{sid}", "action": "remove", "cleanup": True},
        {"set": FAN, "value": False, "cleanup": True},
    ]
    created.append(sid)
    print(f"feedback: the next transition at {t1.isoformat()}")
    ok, text = probe("load-fan", steps, quiet=False)
    forget_removed({sid})
    if "not on this site" in text:
        report.append(f"feedback: skipped, no {FAN_STATUS} (restart the demo with edge.json5)")
    else:
        report.append("feedback: " + ("confirmed, override, written again: ok" if ok else
                                      "FAILED (see above)"))


def terminated(signum, frame):
    raise KeyboardInterrupt  # SIGTERM cleans up as Ctrl+C does


signal.signal(signal.SIGTERM, terminated)
interrupted = False
try:
    for phase, run in (("idle", idle), ("latency", latency), ("feedback", feedback)):
        if phase in PHASES:
            run()
except KeyboardInterrupt:
    interrupted = True
    print("interrupted: cleaning up", file=sys.stderr)
finally:
    for sub in list(subs):
        sub.stop()
    # a failed remove (rate limit, a gateway drop) is tried again after a pause
    for attempt in range(3):
        left = present(created)
        created[:] = left
        if not left:
            break
        if attempt:
            time.sleep(5)
        print(f"cleanup: removing {len(left)} schedules", file=sys.stderr)
        probe("load-cleanup", remove(left))
    else:
        created[:] = present(created)
    if mock_written:
        probe("load-cleanup-mock", [
            {"invoke": f"wy/{SITE}/downstream/mock", "action": "reset", "cleanup": True}])
    if created:
        print(f"cleanup: still there, remove by hand: {', '.join(created[:10])}"
              + (" …" if len(created) > 10 else ""), file=sys.stderr)
    print("\n".join([f"\nscheduler load on {SITE} (probe reports in {LOG}):"] + report))
if interrupted or created:
    sys.exit(130 if interrupted else 1)
PY
