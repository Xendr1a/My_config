#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib/base-test.sh"

doctor="$ROOT/doctor/doctor"
assert_exec "$doctor" 'doctor 可执行'
require_command python3
python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$doctor" ||
  fail 'doctor python 语法'
pass 'doctor python 语法'

if ! command -v niri >/dev/null 2>&1 || ! niri msg --json outputs >/dev/null 2>&1; then
  skip 'doctor 端到端' '缺少可用的 niri 会话'
  exit 0
fi

tmp=$(mktemp -d -- "${TMPDIR:-/tmp}/doctor-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/niri"
printf '# 环境\n\n## 当前环境\n\n旧内容\n' >"$tmp/README.md"
printf 'README.md\t/tmp/README.md\tuser\ttest\n' >"$tmp/MANIFEST.tsv"

"$doctor" --root "$tmp" --refresh >"$tmp/out" 2>&1 ||
  fail 'doctor --refresh' "$(cat "$tmp/out")"
assert_file "$tmp/doctor/facts.toml" 'facts 由真机生成'
grep -q '^product = ' "$tmp/doctor/facts.toml" || fail 'facts 含机型' "$(cat "$tmp/doctor/facts.toml")"
pass 'facts 含机型'

"$doctor" --root "$tmp" --render >"$tmp/out" 2>&1 ||
  fail 'doctor --render' "$(cat "$tmp/out")"
grep -q 'doctor:begin environment' "$tmp/README.md" || fail 'README 写入事实块'
pass 'README 写入事实块'

# 用当前 facts 造一个与真机一致的 kanshi profile 与 MANIFEST。
python3 - "$tmp" <<'PY'
import pathlib
import sys
import tomllib

root = pathlib.Path(sys.argv[1])
facts = tomllib.loads((root / "doctor/facts.toml").read_text(encoding="utf-8"))
output = facts["outputs"][0]
(root / "kanshi").mkdir()
(root / "kanshi/config").write_text(
    "profile test {\n"
    f'    output {output["name"]} {{\n'
    "        enable\n"
    f'        mode {output["current"]}\n'
    "        position 0,0\n"
    "        scale 1\n"
    "    }\n"
    "}\n",
    encoding="utf-8",
)
(root / "MANIFEST.tsv").write_text("README.md\t/tmp/README.md\tuser\ttest\n", encoding="utf-8")
PY

if ! "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail '一致 fixture 应退出 0' "$(cat "$tmp/out")"
fi
pass '一致 fixture 退出 0'

cp "$tmp/README.md" "$tmp/README.bak"
python3 - "$tmp/README.md" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r"scale ([0-9.]+)", lambda m: "scale " + ("9" if m.group(1) != "9" else "8"), text, count=1)
path.write_text(text, encoding="utf-8")
PY
if "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail 'README 漂移应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'README.*DRIFT' "$tmp/out" || fail 'README 漂移出现在报告里' "$(cat "$tmp/out")"
grep -q 'README.md:[0-9]*' "$tmp/out" || fail 'README 漂移给出行号' "$(cat "$tmp/out")"
pass 'README 漂移被抓到并给行号'
cp "$tmp/README.bak" "$tmp/README.md"

cp "$tmp/doctor/facts.toml" "$tmp/facts.bak"
python3 - "$tmp/doctor/facts.toml" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r'^current = ".*"$', 'current = "640x480@59.940"', text, count=1, flags=re.M)
path.write_text(text, encoding="utf-8")
PY
if "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail '事实与真机漂移应非零退出' "$(cat "$tmp/out")"
fi
grep -q '真机 .*\.current.*DRIFT' "$tmp/out" || fail '事实漂移出现在报告里' "$(cat "$tmp/out")"
pass '事实与真机漂移被抓到'
cp "$tmp/facts.bak" "$tmp/doctor/facts.toml"

cp "$tmp/kanshi/config" "$tmp/kanshi.bak"
python3 - "$tmp/kanshi/config" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(re.sub(r"output \S+", "output NOPE-9", text, count=1), encoding="utf-8")
PY
if "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail 'kanshi 输出漂移应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'kanshi/config:[0-9]*.*DRIFT' "$tmp/out" || fail 'kanshi 漂移给出行号' "$(cat "$tmp/out")"
pass 'kanshi 输出漂移被抓到并给行号'

printf 'profile test {\n    output %s {\n        mode garbage\n    }\n}\n' \
  "$(python3 -c 'import sys,tomllib;print(tomllib.load(open(sys.argv[1],"rb"))["outputs"][0]["name"])' "$tmp/doctor/facts.toml")" \
  >"$tmp/kanshi/config"
if "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail 'kanshi 模式语法漂移应非零退出' "$(cat "$tmp/out")"
fi
grep -q '无法解析' "$tmp/out" || fail 'kanshi 模式语法漂移出现在报告里' "$(cat "$tmp/out")"
pass 'kanshi 模式语法漂移被抓到'
cp "$tmp/kanshi.bak" "$tmp/kanshi/config"

printf 'missing-file\t/tmp/x\tuser\ttest\n' >"$tmp/MANIFEST.tsv"
if "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail 'MANIFEST 缺文件应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'MANIFEST.tsv:1' "$tmp/out" || fail 'MANIFEST 漂移给出行号' "$(cat "$tmp/out")"
pass 'MANIFEST 缺失被抓到并给行号'
