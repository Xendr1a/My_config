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
mkdir -p "$tmp/tools" "$tmp/niri"
printf '# 环境\n\n## 当前环境\n\n旧内容\n' >"$tmp/README.md"
printf 'niri/config.kdl\t/tmp/niri.kdl\tuser\ttest\n' >"$tmp/MANIFEST.tsv"
printf 'clean\n' >"$tmp/sync-mode"
cat >"$tmp/tools/check-sync.sh" <<'SH'
#!/usr/bin/env bash
case "$(cat "$(dirname "$0")/../sync-mode")" in
  known) printf 'DIFF      home/.zshrc                                   -> /home/x/.zshrc (33 行差异)\n'; exit 1 ;;
  niri)  printf 'DIFF      niri/config.kdl                              -> /home/x/.config/niri/config.kdl (71 行差异)\n'; exit 1 ;;
  niri2) printf 'DIFF      niri/config.kdl                              -> /home/x/.config/niri/config.kdl (99 行差异)\n'; exit 1 ;;
  new)   printf 'DIFF      niri/config.kdl                              -> /home/x/.config/niri/config.kdl (99 行差异)\n'
         printf 'DIFF      tmux/.tmux.conf.local                        -> /home/x/.config/tmux/.tmux.conf.local (492 行差异)\n'; exit 1 ;;
  *)     printf 'same      niri/config.kdl\n'; exit 0 ;;
esac
SH
chmod +x "$tmp/tools/check-sync.sh"

"$doctor" --root "$tmp" --refresh >"$tmp/out" 2>&1 ||
  fail 'doctor --refresh' "$(cat "$tmp/out")"
assert_file "$tmp/doctor/facts.toml" 'facts 由真机生成'
grep -q '^hostname = ' "$tmp/doctor/facts.toml" || fail 'facts 含 hostname'
grep -q '^\[brightness\]' "$tmp/doctor/facts.toml" || fail 'facts 含背光'
grep -q '^\[niri\]' "$tmp/doctor/facts.toml" || fail 'facts 含 niri 工作区/场景'
grep -q '^\[fontconfig\]' "$tmp/doctor/facts.toml" || fail 'facts 含 fontconfig'
pass 'facts 覆盖新维度'

"$doctor" --root "$tmp" --render >"$tmp/out" 2>&1 ||
  fail 'doctor --render' "$(cat "$tmp/out")"
grep -q 'doctor:begin environment' "$tmp/README.md" || fail 'README 写入事实块'
grep -q '背光' "$tmp/README.md" || fail 'README 含背光行'
grep -q '命名工作区' "$tmp/README.md" || fail 'README 含场景行'
pass 'README 渲染背光与场景'

# 用当前 facts 造一个与真机一致的 kanshi profile。
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
PY

if ! "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail '一致 fixture 应退出 0' "$(cat "$tmp/out")"
fi
grep -q 'check-sync 汇总' "$tmp/out" || fail 'check-sync 被调用' "$(cat "$tmp/out")"
pass '复用 check-sync 且一致 fixture 退出 0'

# known 命中：check-sync 只报 zshrc，known 只打印不算失败。
printf 'known\n' >"$tmp/sync-mode"
cat >>"$tmp/doctor/facts.toml" <<'TOML'

[[known]]
path = "home/.zshrc"
reason = "Dragon Mist 分叉待决"
TOML
if ! "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail 'known 命中应退出 0' "$(cat "$tmp/out")"
fi
grep -q 'known：home/.zshrc.*KNOWN' "$tmp/out" || fail 'known 命中被标记' "$(cat "$tmp/out")"
pass 'known 命中打印但不失败'

# 同一入口的 niri 差异不能靠 known 消掉。
printf 'niri\n' >"$tmp/sync-mode"
if "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail 'niri 差异应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'DIFF niri/config.kdl.*DRIFT' "$tmp/out" || fail 'niri 差异按 DRIFT 处理' "$(cat "$tmp/out")"
pass 'niri 差异真检查，不标 known'

printf 'clean\n' >"$tmp/sync-mode"
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
parts = text.split("\n[[outputs]]\n")
for index, part in enumerate(parts[1:], 1):
    if 'name = "HDMI-A-1"' in part:
        parts[index] = re.sub(r'^current = ".*"$', 'current = "1024x600@60.000"', part, count=1, flags=re.M)
        break
path.write_text("\n[[outputs]]\n".join(parts), encoding="utf-8")
PY
if "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail '事实与真机漂移应非零退出' "$(cat "$tmp/out")"
fi
grep -q '真机 HDMI-A-1.*DRIFT' "$tmp/out" || fail '事实漂移出现在报告里' "$(cat "$tmp/out")"
pass '事实与真机漂移被抓到'
"$doctor" --root "$tmp" --refresh >/dev/null 2>&1 || fail '事实刷新失败'
grep -q '^\[\[known\]\]' "$tmp/doctor/facts.toml" || fail '--refresh 保留 known'
pass '--refresh 保留 known'

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
  fail 'kanshi 不适配应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'kanshi 适配.*DRIFT' "$tmp/out" || fail 'kanshi 无适配 profile 出现在报告里' "$(cat "$tmp/out")"
pass 'kanshi 适配判定不依赖 kanshi 服务'
cp "$tmp/kanshi.bak" "$tmp/kanshi/config"

if ! "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail '恢复后 fixture 应退出 0' "$(cat "$tmp/out")"
fi
pass '恢复后退出 0'

# baseline：接受当前 niri 漂移后应 BASELINED 且退出 0。
printf 'niri\n' >"$tmp/sync-mode"
"$doctor" --root "$tmp" --accept >"$tmp/out" 2>&1 || fail 'doctor --accept' "$(cat "$tmp/out")"
assert_file "$tmp/doctor/baseline.toml" 'baseline 已写入'
grep -q 'id = "check-sync DIFF niri/config.kdl"' "$tmp/doctor/baseline.toml" ||
  fail 'baseline 记录稳定 id' "$(cat "$tmp/doctor/baseline.toml")"
if ! "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail '命中 baseline 应退出 0' "$(cat "$tmp/out")"
fi
grep -q 'check-sync DIFF niri/config.kdl.*BASELINED' "$tmp/out" ||
  fail 'baseline 命中标记 BASELINED' "$(cat "$tmp/out")"
pass '命中 baseline 且观测值一致退出 0'

# 同一 id 的观测值变化：必须重新报 DRIFT。
printf 'niri2\n' >"$tmp/sync-mode"
if "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail 'baseline 观测值变化应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'check-sync DIFF niri/config.kdl.*DRIFT 值变' "$tmp/out" ||
  fail '观测量变化标记 DRIFT' "$(cat "$tmp/out")"
pass 'baseline 观测值变化重新报警'
"$doctor" --root "$tmp" --accept >/dev/null 2>&1 || fail '更新 baseline 失败'

# 新增一条 baseline 外的漂移：只报新增项，旧项仍 BASELINED。
printf 'new\n' >"$tmp/sync-mode"
if "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail '新增漂移应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'check-sync DIFF niri/config.kdl.*BASELINED' "$tmp/out" ||
  fail '旧漂移保持 BASELINED' "$(cat "$tmp/out")"
grep -q 'check-sync DIFF tmux/.tmux.conf.local.*DRIFT' "$tmp/out" ||
  fail '新增漂移被指出' "$(cat "$tmp/out")"
pass '新增漂移只报新增项'

# baseline 项已修复：退出码仍 0，并打 INFO 提示收紧。
printf 'clean\n' >"$tmp/sync-mode"
if ! "$doctor" --root "$tmp" >"$tmp/out" 2>&1; then
  fail 'baseline 项已修复应退出 0' "$(cat "$tmp/out")"
fi
grep -q 'baseline 已修复 check-sync DIFF niri/config.kdl.*INFO' "$tmp/out" ||
  fail '已修复项打 INFO' "$(cat "$tmp/out")"
grep -q '可 --accept 收紧基线' "$tmp/out" || fail '已修复项提示 --accept'
pass 'baseline 已修复项退出 0 并提示收紧'

# --accept 收紧：没有漂移时应清空条目。
"$doctor" --root "$tmp" --accept >"$tmp/out" 2>&1 || fail '收紧 baseline 失败' "$(cat "$tmp/out")"
if grep -q '^\[\[baseline\]\]' "$tmp/doctor/baseline.toml"; then
  fail '收紧后 baseline 应为空' "$(cat "$tmp/doctor/baseline.toml")"
fi
pass '--accept 可收紧基线'
