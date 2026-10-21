#!/usr/bin/env python3
"""Generate spec/fixtures/*.cbor.hex and fixtures.json.

Canonical CBOR as cbor2 produces it with canonical=True: integer keys ascending,
text keys ordered by length then bytewise, floats in shortest lossless form.
This matches wyrm-core's encoder; the Rust test asserts byte equality.

Usage:  python spec/fixtures/gen.py           # regenerate
        python spec/fixtures/gen.py --check   # exit 1 if on-disk fixtures differ
"""
import json
import sys
from pathlib import Path

import cbor2

HERE = Path(__file__).resolve().parent
TS = 1760000000123456
PTOK = b"\x01" + b"\x00" * 8  # placeholder: version byte + 8 bytes


def fixtures():
    fx = []

    def add(name, desc, obj, note=None):
        b = cbor2.dumps(obj, canonical=True)
        fx.append({"name": name, "description": desc, "hex": b.hex(), "len": len(b), "json": obj, "note": note})

    # ~val
    add("val_number", "~val: число, good, uhlc ts", {0: 21.4, 1: 0, 2: TS})
    add("val_bool_bad", "~val: bool, bad quality", {0: False, 1: 2, 2: TS})
    add("val_string", "~val: рядок", {0: "on", 1: 0, 2: TS})
    add("val_enum_idx", "~val: enum як індекс", {0: 2, 1: 0, 2: TS})
    add("val_binary", "~val: сирі байти", {0: b"\x01\x02\x03\x04", 1: 0, 2: TS})
    add("val_uncertain", "~val: uncertain/stale після рестарту", {0: 21.4, 1: 1, 2: TS})

    # ~meta
    add("meta_number_full", "~meta повний для листового числового вузла (is=wy:number, type=number)",
        {0: 2, 1: 1, 2: "°C", 4: 0, 5: 0,
         6: {"precision": 1, "min": -40.0, "max": 120.0, "interval_ms": 1000},
         7: {"display": "Supply air temp", "tag": ["hvac", "floor2"]}, 10: 17})
    add("meta_folder_full", "~meta повний для контейнера з дією reset",
        {0: 1, 9: ["supply_temp", "return_temp", "fan"], 10: 5, 14: 3,
         8: {"reset": {"params": {"mode": {1: 4, 3: ["soft", "hard"]}}, "result": 0, "stream": False}}})
    add("meta_action_ui", "~meta з'єднання драйвера: дії з display/group, параметри з display/description/placeholder/editor",
        {0: 1, 10: 4,
         8: {"add_device": {"params": {
                 "name": {1: 2, "required": True, "display": "Name"},
                 "unit": {1: 1, "default": 1, "display": "Slave ID", "description": "1..247"},
                 "host": {1: 2, "placeholder": "10.0.1.199"},
                 "password": {1: 2, "editor": "password"}},
                 "level": 4, "display": "Add Device", "group": "new"},
             "restart": {"params": {}, "level": 4, "display": "Restart"},
             "remove": {"params": {}, "level": 4, "display": "Remove", "group": "edit"}}})
    add("meta_profile_only", "~meta дитини, що повністю відповідає профілю", {0: 2, 10: 3})
    add("meta_view_list", "~meta?view=list: масив дітей скорочено", [
        {0: 2, 1: 1, 11: False, 10: 17, 12: "Supply air temp"},
        {0: 2, 1: 1, 11: False, 10: 9},
        {0: 4, 1: 3, 11: False, 10: 2, 4: 2, 13: True},
    ])
    add("meta_view_keys", "~meta?view=keys: префіксно стиснуті ключі ('/'-суфікс = push, '' = pop)",
        ["ahu1/", "supply_temp", "return_temp", "fan", "", "ahu2/", "supply_temp", ""])
    add("meta_patch", "~meta patch: {rev, patch}", {10: 18, "patch": {4: 2}})
    add("profile_extends", "pub/<profile>/~meta: поля ~meta + текстовий ключ extends",
        {1: 1, 2: "°C", "extends": "wy:number"})

    # attachment
    add("att_reply_ok", "attachment відповіді set/invoke: ok", {0: 0})
    add("att_reply_err", "attachment відповіді: out_of_range з деталлю", {0: 0x29, 7: "value 150 > max 120"})
    add("att_stream_mid", "attachment стрімової відповіді", {9: 7, 10: 3, 11: False})
    add("att_stream_last", "attachment останньої відповіді стріму", {9: 7, 10: 4, 11: True})
    add("att_refreshed", "attachment: кеш недійсний", {0: 2, 3: True})
    add("att_304", "attachment: ~meta не змінився з rev", {0: 0, 8: 17})
    add("att_request_set", "attachment запиту set з ptok (placeholder) і trace",
        {4: PTOK, 12: "user:olena", 13: b"\xde\xad\xbe\xef" * 4})
    add("att_request_flow", "attachment запиту від флоу з maxperm=write", {4: PTOK, 5: 3, 12: "flow:peak-shaving"})
    add("att_zstd", "attachment відповіді list зі стисненням", {0: 0, 14: "zstd"})

    # ptok claims (unsigned body)
    add("ptok_claims_v1", "ptok v1 claims (перед підписом): 0x01 || cbor(claims) || ed25519 sig(64)",
        {"sub": "user:olena", "roles": ["operator"],
         "grants": [{"k": "wy/plant-a/down/**", "p": 2}, {"k": "wy/plant-a/down/bacnet/**", "p": 3},
                    {"k": "wy/plant-a/sys/**", "p": 0}],
         "max": 3, "iat": 1760000000, "exp": 1760000300, "jti": b"\x11" * 16, "site": "plant-a"})
    return fx


def jsonable(o):
    if isinstance(o, bytes):
        return o.hex()
    if isinstance(o, dict):
        return {str(k): jsonable(v) for k, v in o.items()}
    if isinstance(o, list):
        return [jsonable(x) for x in o]
    return o


def render(fx):
    return json.dumps([{**f, "json": jsonable(f["json"])} for f in fx], ensure_ascii=False, indent=1) + "\n"


def main():
    fx = fixtures()
    text = render(fx)
    if "--check" in sys.argv:
        ok = (HERE / "fixtures.json").read_text(encoding="utf-8") == text
        for f in fx:
            ok &= (HERE / f"{f['name']}.cbor.hex").read_text() == f["hex"] + "\n"
        print("fixtures in sync" if ok else "fixtures OUT OF SYNC — run gen.py")
        sys.exit(0 if ok else 1)
    (HERE / "fixtures.json").write_text(text, encoding="utf-8")
    for f in fx:
        (HERE / f"{f['name']}.cbor.hex").write_text(f["hex"] + "\n")
    print(f"{len(fx)} fixtures, {sum(f['len'] for f in fx)} bytes")


if __name__ == "__main__":
    main()
