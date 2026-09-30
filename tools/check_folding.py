"""Verify Unity's multi-line quoted scalar folding by reproducing the value."""

import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else r"D:\Project\CATSIM_2\Assets\Configs\Runtime\DialogueConfig\camera_test.asset"
with open(path, "r", encoding="utf-8") as fh:
    raw = fh.read()

# Rebuild the scalar the way the YAML spec says: a single line break in a quoted
# scalar becomes a space, and each additional break becomes a newline. The
# indentation of a continuation line is discarded.
match = re.search(r"_serializedGraph: '(.*?)'\r?\n", raw, re.S)
if not match:
    print("scalar not found")
    sys.exit(1)
body = match.group(1)
pieces = body.split("\n")
rebuilt = pieces[0]
for piece in pieces[1:]:
    rebuilt += " " + piece.lstrip()
print(f"raw lines={len(pieces)} rebuilt length={len(rebuilt)}")

start = raw.index("_serializedGraph: '") + len("_serializedGraph: '")
end = raw.index("'", start)
original_layout = raw[start:end]
print(f"original layout length={len(original_layout)}")
print(f"rebuilt == layout: {rebuilt == original_layout}")
if rebuilt != original_layout:
    for i in range(min(len(rebuilt), len(original_layout))):
        if rebuilt[i] != original_layout[i]:
            print(f"  first difference at {i}")
            print(f"    layout:  ...{original_layout[max(0, i - 40):i + 40]!r}")
            print(f"    rebuilt: ...{rebuilt[max(0, i - 40):i + 40]!r}")
            break

for probe in ('},"positionDir"', '}, "positionDir"', '"Separator|', '"Separator| '):
    print(f"  contains {probe!r}: {probe in rebuilt}")
