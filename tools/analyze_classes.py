"""Inventory Unity class ids and document-header shapes across a real project."""

import os
import re
import sys
import collections

ROOT = sys.argv[1] if len(sys.argv) > 1 else r"D:\Project\CATSIM_2\Assets"
EXTS = {".prefab", ".asset", ".unity", ".controller", ".mat", ".anim", ".meta"}
HEADER = re.compile(r"^--- !u!(-?\d+)(?: &(-?\d+))?(.*)$")


def iter_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            if os.path.splitext(name)[1] in EXTS:
                yield os.path.join(dirpath, name)


def main():
    ids = collections.Counter()
    classes = collections.Counter()
    trailers = collections.Counter()
    directives = collections.Counter()
    indegree = collections.Counter()
    files = 0
    bad = []
    for path in iter_files(ROOT):
        files += 1
        try:
            with open(path, "r", encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            continue
        for line in text.split("\n"):
            if line.startswith("%"):
                directives[line.strip()] += 1
                continue
            m = HEADER.match(line)
            if m:
                cid = int(m.group(1))
                ids[cid] += 1
                trail = m.group(3).strip()
                if trail:
                    trailers[trail] += 1
                continue
        # class name key on the line after each header
        lines = text.split("\n")
        for i, line in enumerate(lines):
            m = HEADER.match(line)
            if m and i + 1 < len(lines):
                nxt = lines[i + 1]
                if nxt.endswith(":") and not nxt.startswith(" "):
                    classes[(int(m.group(1)), nxt[:-1])] += 1
                else:
                    bad.append((path, i + 1, nxt[:60]))
    print(f"files={files}")
    print("\n-- class ids (count desc) --")
    for cid, n in ids.most_common():
        key = collections.Counter()
        for (c, name), cn in classes.items():
            if c == cid:
                key[name] = cn
        print(f"  {cid:6d} n={n:7d} names={dict(key)}")
    print("\n-- header trailers --")
    for t, n in trailers.most_common():
        print(f"  {t!r} n={n}")
    print("\n-- directives --")
    for d, n in directives.most_common(10):
        print(f"  {d!r} n={n}")
    print(f"\n-- non-name lines after header: {len(bad)} --")
    for path, ln, txt in bad[:15]:
        print(f"  {os.path.basename(path)}:{ln} {txt!r}")


if __name__ == "__main__":
    main()
