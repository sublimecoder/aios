"""Deep-merge a JSON fragment into a JSON file, fragment winning on its own keys.

Usage: json-merge.py <target> <fragment> <apply 0|1> [backup]
Prints INVALID, or the comma-joined top-level keys that would change (empty =
nothing to do). Writes only when apply=1. Objects merge recursively, anything
else (arrays included) is replaced, and no key is ever deleted -- so keys the
fragment does not own pass through, which is what lets two installers share
one settings file.
"""
import json, os, shutil, sys, time

target, frag, apply = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
backup = len(sys.argv) > 4 and sys.argv[4] == "backup"


def merge(a, b):
    out = dict(a)
    for k, v in b.items():
        out[k] = merge(a[k], v) if isinstance(a.get(k), dict) and isinstance(v, dict) else v
    return out


try:
    cur = json.load(open(target, encoding="utf-8")) if os.path.exists(target) else {}
    add = json.load(open(frag, encoding="utf-8"))
except (ValueError, OSError):
    print("INVALID")
    sys.exit(0)

if not isinstance(cur, dict) or not isinstance(add, dict):
    # A JSON array or null parses fine but is not a settings object -- merging
    # into/from one would silently discard it (dict(a) on a list raises, and
    # treating it as {} would clobber whatever the array actually held).
    print("INVALID")
    sys.exit(0)

new = merge(cur, add)
changed = [k for k in add if cur.get(k) != new.get(k)]
if changed and apply:
    if backup and os.path.exists(target):
        shutil.copy2(target, target + ".aios-bak-" + time.strftime("%Y%m%dT%H%M%S"))
    os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
    tmp = target + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(new, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if os.path.exists(target):
        shutil.copymode(target, tmp)
    os.replace(tmp, target)
print(", ".join(changed))
