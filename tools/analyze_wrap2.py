"""Measure Unity's flow-map wrap width precisely.

Only considers lines that open a flow mapping (`{` before any `}` on the line)
whose continuation lines are indented and end with `}`.  Long single-quoted
scalars are excluded because they contain `}` and `{` unbalanced.
"""

import os
import re
import sys
import collections

ROOT = sys.argv[1] if len(sys.argv) > 1 else r"D:\Project\CATSIM_2\Assets"
EXTS = {".prefab", ".asset", ".unity", ".controller", ".mat", ".anim", ".meta"}


def iter_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            if os.path.splitext(name)[1] in EXTS:
                yield os.path.join(dirpath, name)


def main():
    per_base = collections.defaultdict(collections.Counter)
    examples = collections.defaultdict(list)
    total = 0
    for path in iter_files(ROOT):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                lines = fh.read().split("\n")
        except (OSError, UnicodeDecodeError):
            continue
        for i in range(len(lines) - 1):
            line = lines[i]
            stripped = line.strip()
            if "{" not in line or not stripped.endswith(","):
                continue
            # must be a key: { ...   (flow map opener), and no closing brace on this line
            if line.count("{") - line.count("}") != 1:
                continue
            nxt = lines[i + 1]
            if not nxt.startswith("    ") or not nxt.strip():
                continue
            # continuation must be a plain key: value fragment, not a quoted scalar
            if "'" in line or '"' in line or "'" in nxt or '"' in nxt:
                continue
            if ":" not in nxt:
                continue
            base = len(line) - len(line.lstrip())
            total += 1
            per_base[base][len(line)] += 1
            if len(examples[base]) < 6:
                examples[base].append((os.path.basename(path), i + 1, len(line), line, nxt))
    print(f"wrapped_flow_maps={total}")
    for base in sorted(per_base):
        lens = per_base[base]
        print(f"\nbase indent={base}  n={sum(lens.values())}  min={min(lens)} max={max(lens)}")
        print("   lengths:", " ".join(f"{k}:{lens[k]}" for k in sorted(lens)))
        for name, ln, length, line, nxt in examples[base]:
            print(f"   {name}:{ln} len={length}")
            print(f"     |{line}")
            print(f"     >{nxt}")


if __name__ == "__main__":
    main()
