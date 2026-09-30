"""Empirically characterise Unity's flow-collection line wrapping.

Reads a real Unity project tree and reports, for every wrapped flow collection:
  * the indent of its first line
  * the length of the first line
  * the indent and length of every continuation line
so the wrapping width can be inferred instead of guessed.
"""

import os
import re
import sys
import collections

ROOT = sys.argv[1] if len(sys.argv) > 1 else r"D:\Project\CATSIM_2\Assets"
EXTS = {".prefab", ".asset", ".unity", ".controller", ".mat", ".anim", ".meta", ".playable", ".overrideController"}

FLOW_OPEN = re.compile(r"[,{]\s*$")


def iter_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".git",)]
        for name in filenames:
            if os.path.splitext(name)[1] in EXTS:
                yield os.path.join(dirpath, name)


def main():
    first_len = collections.Counter()
    cont_len = collections.Counter()
    cont_indent = collections.Counter()
    first_base = collections.Counter()
    per_base = collections.defaultdict(collections.Counter)
    cont_per_base = collections.defaultdict(collections.Counter)
    examples = collections.defaultdict(list)
    files = 0
    wrapped = 0
    maxline = 0
    long_examples = []

    for path in iter_files(ROOT):
        files += 1
        try:
            with open(path, "r", encoding="utf-8") as fh:
                lines = fh.read().split("\n")
        except (OSError, UnicodeDecodeError):
            continue
        for i in range(len(lines) - 1):
            line = lines[i]
            if len(line) > 200:
                if len(long_examples) < 5:
                    long_examples.append((path, i + 1, len(line), line[:100]))
                continue
            if not FLOW_OPEN.search(line):
                continue
            nxt = lines[i + 1]
            if not nxt.strip() or nxt.lstrip() == nxt:
                continue
            wrapped += 1
            base = len(line) - len(line.lstrip())
            first_len[len(line)] += 1
            first_base[base] += 1
            per_base[base][len(line)] += 1
            if len(examples[base]) < 3:
                examples[base].append((path, i + 1, len(line), line.strip()[:90], nxt.strip()[:70]))
            # continuation lines: those starting with 4 spaces directly after
            j = i + 1
            while j < len(lines):
                cl = lines[j]
                if not cl.startswith("    ") or not cl.strip():
                    break
                ci = len(cl) - len(cl.lstrip())
                cont_len[len(cl)] += 1
                cont_indent[ci] += 1
                cont_per_base[base][len(cl)] += 1
                maxline = max(maxline, len(cl))
                if cl.rstrip().endswith(("}", "]")) or cl.rstrip().endswith(","):
                    j += 1
                    if cl.rstrip().endswith(("}", "]")):
                        break
                else:
                    break
            else:
                pass

    print(f"files={files} wrapped_collections={wrapped}")
    print("\n-- first-line length histogram --")
    for k in sorted(first_len):
        print(f"  len={k:4d} n={first_len[k]}")
    print("\n-- first-line base indent histogram --")
    for k in sorted(first_base):
        print(f"  indent={k:3d} n={first_base[k]}")
    print("\n-- continuation-line indent histogram --")
    for k in sorted(cont_indent):
        print(f"  indent={k:3d} n={cont_indent[k]}")
    print("\n-- continuation-line length histogram (top 20) --")
    for k, v in cont_len.most_common(20):
        print(f"  len={k:4d} n={v}")
    print("\n-- per base indent: max first-line length --")
    for base in sorted(per_base):
        mx = max(per_base[base])
        cmx = max(cont_per_base[base]) if cont_per_base[base] else 0
        print(f"  base={base:3d} max_first={mx:4d} max_cont={cmx:4d} first_lens={sorted(per_base[base])[:8]}")
    print("\n-- examples --")
    for base in sorted(examples):
        print(f"  base indent={base}")
        for path, ln, length, text, nxt in examples[base]:
            print(f"    {os.path.basename(path)}:{ln} len={length}")
            print(f"      |{text}")
            print(f"      >{nxt}")
    print("\n-- long (>200 char) line examples --")
    for path, ln, length, text in long_examples:
        print(f"  {os.path.basename(path)}:{ln} len={length} |{text}")


if __name__ == "__main__":
    main()
