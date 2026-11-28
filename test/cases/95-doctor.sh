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

"$doctor" --root "$tmp" --state-dir "$tmp/state" --refresh >"$tmp/out" 2>&1 ||
  fail 'doctor --refresh' "$(cat "$tmp/out")"
assert_file "$tmp/doctor/facts.toml" 'facts 由真机生成'
grep -q '^hostname = ' "$tmp/doctor/facts.toml" || fail 'facts 含 hostname'
grep -q '^\[brightness\]' "$tmp/doctor/facts.toml" || fail 'facts 含背光'
grep -q '^\[niri\]' "$tmp/doctor/facts.toml" || fail 'facts 含 niri 工作区/场景'
grep -q '^\[fontconfig\]' "$tmp/doctor/facts.toml" || fail 'facts 含 fontconfig'
pass 'facts 覆盖新维度'

"$doctor" --root "$tmp" --state-dir "$tmp/state" --render >"$tmp/out" 2>&1 ||
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

if ! "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
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
if ! "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
  fail 'known 命中应退出 0' "$(cat "$tmp/out")"
fi
grep -q 'known：home/.zshrc.*KNOWN' "$tmp/out" || fail 'known 命中被标记' "$(cat "$tmp/out")"
pass 'known 命中打印但不失败'

# 同一入口的 niri 差异不能靠 known 消掉。
printf 'niri\n' >"$tmp/sync-mode"
if "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
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
if "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
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
if "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
  fail '事实与真机漂移应非零退出' "$(cat "$tmp/out")"
fi
grep -q '真机 HDMI-A-1.*DRIFT' "$tmp/out" || fail '事实漂移出现在报告里' "$(cat "$tmp/out")"
pass '事实与真机漂移被抓到'
"$doctor" --root "$tmp" --state-dir "$tmp/state" --refresh >/dev/null 2>&1 || fail '事实刷新失败'
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
if "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
  fail 'kanshi 不适配应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'kanshi 适配.*DRIFT' "$tmp/out" || fail 'kanshi 无适配 profile 出现在报告里' "$(cat "$tmp/out")"
pass 'kanshi 适配判定不依赖 kanshi 服务'
cp "$tmp/kanshi.bak" "$tmp/kanshi/config"

if ! "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
  fail '恢复后 fixture 应退出 0' "$(cat "$tmp/out")"
fi
pass '恢复后退出 0'

# baseline：接受当前 niri 漂移后应 BASELINED 且退出 0。
printf 'niri\n' >"$tmp/sync-mode"
"$doctor" --root "$tmp" --state-dir "$tmp/state" --accept >"$tmp/out" 2>&1 || fail 'doctor --accept' "$(cat "$tmp/out")"
assert_file "$tmp/doctor/baseline.toml" 'baseline 已写入'
grep -q 'id = "check-sync DIFF niri/config.kdl"' "$tmp/doctor/baseline.toml" ||
  fail 'baseline 记录稳定 id' "$(cat "$tmp/doctor/baseline.toml")"
if ! "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
  fail '命中 baseline 应退出 0' "$(cat "$tmp/out")"
fi
grep -q 'check-sync DIFF niri/config.kdl.*BASELINED' "$tmp/out" ||
  fail 'baseline 命中标记 BASELINED' "$(cat "$tmp/out")"
pass '命中 baseline 且观测值一致退出 0'

# 同一 id 的观测值变化：必须重新报 DRIFT。
printf 'niri2\n' >"$tmp/sync-mode"
if "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
  fail 'baseline 观测值变化应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'check-sync DIFF niri/config.kdl.*DRIFT 值变' "$tmp/out" ||
  fail '观测量变化标记 DRIFT' "$(cat "$tmp/out")"
pass 'baseline 观测值变化重新报警'
"$doctor" --root "$tmp" --state-dir "$tmp/state" --accept >/dev/null 2>&1 || fail '更新 baseline 失败'

# 新增一条 baseline 外的漂移：只报新增项，旧项仍 BASELINED。
printf 'new\n' >"$tmp/sync-mode"
if "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
  fail '新增漂移应非零退出' "$(cat "$tmp/out")"
fi
grep -q 'check-sync DIFF niri/config.kdl.*BASELINED' "$tmp/out" ||
  fail '旧漂移保持 BASELINED' "$(cat "$tmp/out")"
grep -q 'check-sync DIFF tmux/.tmux.conf.local.*DRIFT' "$tmp/out" ||
  fail '新增漂移被指出' "$(cat "$tmp/out")"
pass '新增漂移只报新增项'

# baseline 项已修复：退出码仍 0，并打 INFO 提示收紧。
printf 'clean\n' >"$tmp/sync-mode"
if ! "$doctor" --root "$tmp" --state-dir "$tmp/state" >"$tmp/out" 2>&1; then
  fail 'baseline 项已修复应退出 0' "$(cat "$tmp/out")"
fi
grep -q 'baseline 已修复 check-sync DIFF niri/config.kdl.*INFO' "$tmp/out" ||
  fail '已修复项打 INFO' "$(cat "$tmp/out")"
grep -q '可 --accept 收紧基线' "$tmp/out" || fail '已修复项提示 --accept'
pass 'baseline 已修复项退出 0 并提示收紧'

# --accept 收紧：没有漂移时应清空条目。
"$doctor" --root "$tmp" --state-dir "$tmp/state" --accept >"$tmp/out" 2>&1 || fail '收紧 baseline 失败' "$(cat "$tmp/out")"
if grep -q '^\[\[baseline\]\]' "$tmp/doctor/baseline.toml"; then
  fail '收紧后 baseline 应为空' "$(cat "$tmp/doctor/baseline.toml")"
fi
pass '--accept 可收紧基线'

# ---------- 每日巡检状态 / 晨报 ----------

printf 'clean\n' >"$tmp/sync-mode"

"$doctor" --root "$tmp" --state-dir "$tmp/state-summary" --summary >"$tmp/sum" 2>&1 ||
  fail 'doctor --summary' "$(cat "$tmp/sum")"
[[ $(wc -l <"$tmp/sum") -eq 1 ]] || fail '--summary 无漂移恰好一行' "$(cat "$tmp/sum")"
grep -Eq '^配置漂移: 漂移 0 · baseline 0 · known 0 · 昨日新增 0 · 最近变更 无$' "$tmp/sum" ||
  fail '--summary 字段顺序固定且零变化为无' "$(cat "$tmp/sum")"
assert_file "$tmp/state-summary/last.json" '零漂移也写 last.json'
pass '--summary 单行、字段顺序固定、零变化为无'

"$doctor" --root "$tmp" --state-dir "$tmp/state-json" >"$tmp/out" 2>&1 ||
  fail '默认检查（取 items 基准）' "$(cat "$tmp/out")"
items_actual=$(sed -n 's/^# 检查 \([0-9]\+\) 项.*/\1/p' "$tmp/out")
[[ -n "$items_actual" ]] || fail '默认输出含检查总数' "$(cat "$tmp/out")"
"$doctor" --root "$tmp" --state-dir "$tmp/state-json" --json >"$tmp/json" 2>&1 ||
  fail 'doctor --json' "$(cat "$tmp/json")"
python3 -m json.tool "$tmp/json" >/dev/null || fail '--json 不是合法 JSON' "$(cat "$tmp/json")"
python3 - "$tmp/json" "$items_actual" <<'PY' || fail '--json schema / items 不符'
import json, sys
obj = json.load(open(sys.argv[1], encoding="utf-8"))
actual = int(sys.argv[2])
want = ["ts", "schema", "checks", "items", "drift", "baselined", "known", "skipped", "exit",
        "added", "fixed", "duration_ms"]
raise SystemExit(0 if list(obj) == want and obj["schema"] == 1
                 and obj["items"] == actual and obj["checks"] == actual
                 and obj["drift"] == 0 and obj["exit"] == 0
                 and obj["added"] == [] and obj["fixed"] == []
                 and isinstance(obj["ts"], str) and isinstance(obj["duration_ms"], int) else 1)
PY
pass '--json schema 稳定且 items 等于实际检查行数'

rm -rf "$tmp/state-log"
"$doctor" --root "$tmp" --state-dir "$tmp/state-log" --json >/dev/null 2>&1 || fail '巡检第一次运行'
inode1=$(stat -c %i "$tmp/state-log/last.json")
"$doctor" --root "$tmp" --state-dir "$tmp/state-log" --json >/dev/null 2>&1 || fail '巡检第二次运行'
inode2=$(stat -c %i "$tmp/state-log/last.json")
[[ "$inode1" != "$inode2" ]] || fail 'last.json 应被原子覆盖'
[[ $(wc -l <"$tmp/state-log/doctor.log") -eq 2 ]] || fail 'doctor.log 应有两行' "$(cat "$tmp/state-log/doctor.log")"
python3 - "$tmp/state-log" <<'PY' || fail 'last.json 应为最后一行日志'
import json, sys, pathlib
state = pathlib.Path(sys.argv[1])
lines = state.joinpath("doctor.log").read_text(encoding="utf-8").splitlines()
last = json.loads(state.joinpath("last.json").read_text(encoding="utf-8"))
raise SystemExit(0 if json.loads(lines[-1]) == last and len(lines) == 2 else 1)
PY
pass '连续运行追加日志并覆盖 last.json'

"$doctor" --root "$tmp" --state-dir "$tmp/state-since" --since 24h >"$tmp/since" 2>&1
grep -qx '无变化' "$tmp/since" || fail '--since 无变化' "$(cat "$tmp/since")"
# 先跑一次零漂移，确立「上次巡检」；再造一条漂移看摘要只列这一条。
"$doctor" --root "$tmp" --state-dir "$tmp/state-since" --summary >/dev/null 2>&1 ||
  fail '--summary 基线巡检'
printf 'niri\n' >"$tmp/sync-mode"
if "$doctor" --root "$tmp" --state-dir "$tmp/state-since" --summary >"$tmp/sum" 2>&1; then
  fail '有漂移时 --summary 应退出 1'
fi
[[ $(wc -l <"$tmp/sum") -eq 2 ]] || fail '--summary 有新增时两行' "$(cat "$tmp/sum")"
grep -qx '配置漂移: 漂移 1 · baseline 0 · known 0 · 昨日新增 1 · 最近变更 + check-sync DIFF niri/config.kdl' "$tmp/sum" ||
  fail '--summary 只列自上次以来的漂移条目' "$(cat "$tmp/sum")"
grep -qx '  + check-sync DIFF niri/config.kdl（新增）' "$tmp/sum" ||
  fail '--summary 展开新增明细' "$(cat "$tmp/sum")"
"$doctor" --root "$tmp" --state-dir "$tmp/state-since" --since 24h >"$tmp/since" 2>&1
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} \+ check-sync DIFF niri/config\.kdl ' "$tmp/since" ||
  fail '--since 列出窗口内新增' "$(cat "$tmp/since")"
"$doctor" --root "$tmp" --state-dir "$tmp/state-since" --since today >"$tmp/since" 2>&1
grep -q 'check-sync DIFF niri/config.kdl' "$tmp/since" || fail '--since today 可解析' "$(cat "$tmp/since")"
if "$doctor" --root "$tmp" --state-dir "$tmp/state-since" --json >/dev/null 2>&1; then
  fail '有漂移时 --json 应退出 1'
fi
# 漂移持续存在、没有新变化时，最近变更回到「无」。
if "$doctor" --root "$tmp" --state-dir "$tmp/state-since" --summary >"$tmp/sum" 2>&1; then
  fail '稳定漂移仍应退出 1'
fi
grep -q '最近变更 无$' "$tmp/sum" || fail '稳定漂移不再重复列为最近变更' "$(cat "$tmp/sum")"
# 修复 baseline 条目要出现在最近变更里（- id）。
printf 'niri\n' >"$tmp/sync-mode"
"$doctor" --root "$tmp" --state-dir "$tmp/state-since" --accept >/dev/null 2>&1 || fail '造 baseline 条目'
printf 'clean\n' >"$tmp/sync-mode"
"$doctor" --root "$tmp" --state-dir "$tmp/state-since" --summary >"$tmp/sum" 2>&1 ||
  fail '已修复 baseline 时 --summary 退出 0'
grep -q '最近变更 - check-sync DIFF niri/config.kdl$' "$tmp/sum" ||
  fail '--summary 列出已修复条目' "$(cat "$tmp/sum")"
"$doctor" --root "$tmp" --state-dir "$tmp/state-since" --accept >/dev/null 2>&1 || fail '收紧 baseline'
pass '--since 窗口筛选与晨报最近变更语义'

facts_mtime=$(stat -c %y "$ROOT/doctor/facts.toml")
baseline_mtime=$(stat -c %y "$ROOT/doctor/baseline.toml")
git_before=$(git -C "$ROOT" status --porcelain)
"$doctor" --state-dir "$tmp/state-ro" >"$tmp/out" 2>&1 || true
[[ "$(stat -c %y "$ROOT/doctor/facts.toml")" == "$facts_mtime" ]] || fail '默认运行改动了 facts.toml'
[[ "$(stat -c %y "$ROOT/doctor/baseline.toml")" == "$baseline_mtime" ]] || fail '默认运行改动了 baseline.toml'
[[ "$(git -C "$ROOT" status --porcelain)" == "$git_before" ]] || fail '默认运行弄脏了 git status'
[[ $(wc -l <"$tmp/state-ro/doctor.log") -eq 1 ]] || fail '默认运行应写一条状态日志'
pass '默认运行只读仓库，状态只落用户目录'

# 探测空值 ≠ 漂移：假 fc-match 不输出任何 family。
mkdir -p "$tmp/fakebin-empty" "$tmp/fakebin-drift"
cat >"$tmp/fakebin-empty/fc-match" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$tmp/fakebin-drift/fc-match" <<'SH'
#!/usr/bin/env bash
printf 'Totally Different Font'
SH
chmod +x "$tmp/fakebin-empty/fc-match" "$tmp/fakebin-drift/fc-match"

rm -rf "$tmp/state-fc-empty"
if ! PATH="$tmp/fakebin-empty:$PATH" "$doctor" --root "$tmp" --state-dir "$tmp/state-fc-empty" >"$tmp/out" 2>&1; then
  fail 'fc-match 空输出应退出 0' "$(cat "$tmp/out")"
fi
grep -q '真机 fontconfig.monospace_cjk.*SKIP' "$tmp/out" || fail '空 fc-match 记 SKIP' "$(cat "$tmp/out")"
grep -q '真机 fontconfig.sans_serif_cjk.*SKIP' "$tmp/out" || fail '空 fc-match（sans）记 SKIP' "$(cat "$tmp/out")"
PATH="$tmp/fakebin-empty:$PATH" "$doctor" --root "$tmp" --state-dir "$tmp/state-fc-empty" --json >"$tmp/json" 2>&1 ||
  fail 'fc-match 空输出时 --json 应退出 0'
python3 - "$tmp/json" <<'PY' || fail '空探测应进 skipped 且 drift 0'
import json, sys
obj = json.load(open(sys.argv[1], encoding="utf-8"))
raise SystemExit(0 if obj["drift"] == 0 and obj["exit"] == 0 and obj["skipped"] >= 2 else 1)
PY
pass '探测空值记 SKIP，不参与退出码'

rm -rf "$tmp/state-fc-drift"
if PATH="$tmp/fakebin-drift:$PATH" "$doctor" --root "$tmp" --state-dir "$tmp/state-fc-drift" >"$tmp/out" 2>&1; then
  fail 'fc-match 不一致值应退出 1' "$(cat "$tmp/out")"
fi
grep -q '真机 fontconfig.monospace_cjk.*DRIFT' "$tmp/out" || fail '真实不一致值记 DRIFT' "$(cat "$tmp/out")"
PATH="$tmp/fakebin-drift:$PATH" "$doctor" --root "$tmp" --state-dir "$tmp/state-fc-drift" --json >"$tmp/json" 2>&1 || true
python3 - "$tmp/json" <<'PY' || fail '真实不一致值应进 added'
import json, sys
obj = json.load(open(sys.argv[1], encoding="utf-8"))
ids = {item["id"] for item in obj["added"]}
raise SystemExit(0 if obj["exit"] == 1 and "真机 fontconfig.monospace_cjk" in ids else 1)
PY
pass '探测到真实不一致值仍是 DRIFT'

# ---------- --state-dir 隔离：探针不污染生产状态 ----------
# 生产路径用临时 HOME 模拟，真实 ~/.local/state/doctor/ 全程不参与。
probe_home="$tmp/home-probe"
probe_prod="$probe_home/.local/state/doctor"
mkdir -p -- "$probe_prod"
snapshot_state() {
  (cd -- "$1" && stat -c '%n %s %y %i' -- . * && sha256sum -- *)
}

# 不传 --state-dir 时落到 $HOME 下的生产路径（此处即临时 HOME，不是真机）。
HOME="$probe_home" "$doctor" --root "$tmp" >"$tmp/out" 2>&1 || true
[[ -f "$probe_prod/last.json" && -f "$probe_prod/doctor.log" ]] ||
  fail '默认状态目录应位于 $HOME/.local/state/doctor' "$(cat "$tmp/out")"
prod_before=$(snapshot_state "$probe_prod")

# 临时 HOME 没有真机的 niri / scene 配置，退出码可能非零；这里只看状态落盘位置。
probe_state="$tmp/state-probe"
rm -rf -- "$probe_state"
HOME="$probe_home" "$doctor" --root "$tmp" --state-dir "$probe_state" --summary >"$tmp/sum" 2>&1 || true
assert_file "$probe_state/last.json" '--state-dir 写 last.json'
assert_file "$probe_state/doctor.log" '--state-dir 写 doctor.log'
[[ $(wc -l <"$probe_state/doctor.log") -eq 1 ]] ||
  fail '--state-dir 首跑写一行日志' "$(cat "$probe_state/doctor.log")"
inode1=$(stat -c %i "$probe_state/last.json")
HOME="$probe_home" "$doctor" --root "$tmp" --state-dir "$probe_state" --summary >"$tmp/sum" 2>&1 || true
inode2=$(stat -c %i "$probe_state/last.json")
[[ "$inode1" != "$inode2" ]] || fail '--state-dir 下 last.json 应被原子覆盖'
[[ $(wc -l <"$probe_state/doctor.log") -eq 2 ]] ||
  fail '--state-dir 下 doctor.log 应追加' "$(cat "$probe_state/doctor.log")"
python3 - "$probe_state" <<'PY' || fail 'last.json 应为最后一行日志'
import json, pathlib, sys
state = pathlib.Path(sys.argv[1])
lines = state.joinpath("doctor.log").read_text(encoding="utf-8").splitlines()
last = json.loads(state.joinpath("last.json").read_text(encoding="utf-8"))
raise SystemExit(0 if len(lines) == 2 and json.loads(lines[-1]) == last else 1)
PY
[[ "$(snapshot_state "$probe_prod")" == "$prod_before" ]] ||
  fail '--state-dir 运行改动了生产状态目录' "$(snapshot_state "$probe_prod")"
pass '--state-dir 状态只落指定目录，生产目录内容与 mtime 不变'
