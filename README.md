# My_config

这台机器上 Arch + niri + Noctalia 的配置留档。机型、主机名与显示布局写在下面的[当前环境](#当前环境)，由 `./doctor/doctor --render` 从真机事实生成。

仓库来自 [Mel-SRK/My_config](https://github.com/Mel-SRK/My_config)，保留其目录结构、`install.sh` / `MANIFEST.tsv` 校验体系；本机的输出布局、终端与 shell 启动方式按实际硬件改过。

## 预览

![预览图片.jpg](./预览图片.jpg)

仓库布局：

| 路径 | 内容 |
|---|---|
| 顶层目录（`niri/`、`alacritty/`、`noctalia/`…） | 镜像 `~/.config/` 下的同名子目录 |
| `home/` | 家目录点文件（`.zshrc`、`.gitconfig`、`.gdbinit`…） |
| `system-files/` | `/etc` 与 `/usr/local` 下手工改过的文件 |
| `archive/` | 已退役方案，只作历史留档，不要部署 |
| `tools/check-sync.sh` | 比对仓库与实机，只读 |
| `doctor/` | 事实基线 `facts.toml`、已接受漂移 `baseline.toml` 与自检脚本 |
| `packages/` | 重装时要装的包清单（official / foreign） |
| `migrations/` | 一次性状态修复脚本 |
| `test/` | 本地测试集 |
| `MANIFEST.tsv` | 仓库路径 ↔ 安装路径映射，安装与校验脚本都读它 |

## 当前环境

- 合成器 **niri 26.04**（滚动式列布局）；桌面 Shell **Noctalia v5**（`extra/noctalia`，二进制 `noctalia`）
- 登录器 **greetd + noctalia-greeter**（`/etc/greetd/config.toml`），`sddm` 已 disabled
<!-- doctor:begin environment -->
- 机型 **COLORFUL G16 24**，主机名 `Xen`
- 显示：`eDP-1` **2560x1600@240** scale 1.5（BOE，位置 x=5440 y=-700）；`HDMI-A-1` **1920x1080@240** scale 1（PNP(SAC)，位置 x=3520 y=360）
- 背光：内置屏 `/sys/class/backlight/nvidia_0`；外接屏 `HDMI-A-1` 走 `ddcutil` VCP `0x10`
- 场景：`~/.local/bin/scene`，`Mod+Shift+W` write / `Mod+Shift+D` present / `Mod+Shift+T` ctf；命名工作区 `写作`、`打题` 固定 `HDMI-A-1`
- 终端 **alacritty**（真机已装：`alacritty`、`foot`）
<!-- doctor:end environment -->

- 显示布局与热插拔由 Noctalia 的 `niri-displays` 面板维护，写在 `niri/outputs.kdl`（不用 kanshi）
- shell zsh + oh-my-zsh（`/usr/share/oh-my-zsh`）+ powerlevel10k
- 输入法 fcitx5，当前默认 `pinyin`，保留 `qingjian`；X11/Java 应用走 xwayland-satellite
- 终端启动即进 tmux：`alacritty` 的 `[terminal.shell]` 直接 `tmux new-session -A -s Xendr1a`，`.zshrc` 里不再 attach
- 代理统一 `127.0.0.1:7897`（Clash Verge）；防火墙 firewalld（`nftables.service` 未启用）

## 环境自检（doctor）

`doctor/facts.toml` 是唯一事实基线：由真机采集，可编辑、可 diff。doctor 不重复实现仓库 ↔ 实机同步，只补 `tools/check-sync.sh` 没覆盖的维度：

- 配置同步：直接调用 `tools/check-sync.sh`，按它的 `same` / `drift` / `DIFF` / `MISSING` 行出表；`facts.toml` 的 `[[known]]` 命中的差异只打印（`KNOWN`），不计失败。
- 已接受的既有漂移记在 `doctor/baseline.toml`：每项是稳定 id + 观测值 sha256。它不是忽略列表——观测值一变就重新报 `DRIFT`；不在 baseline 的新漂移也报 `DRIFT`。修好后的条目只在 `--accept` 时收紧，doctor 不会自动删。
- 本机事实：hostname、显示器连接器 / 当前模式 / 缩放（当前 off 的输出改为校验基线模式仍在可用列表）、背光设备、外接屏 `ddcutil` VCP `0x10`。
- niri 命名工作区与 `~/.local/bin/scene` 三个键位、kanshi profile 对当前输出的适配（kanshi 没启用也照常判定）。
- fontconfig 实际中文解析结果、fcitx5 profile 默认输入法（当前激活输入法随焦点变化，只提示不判定）。
- README 的 `doctor:begin/end environment` 段由同一份 facts 渲染。
- 真机探测失败（命令不可用、超时、空输出）一律记 `SKIP` 并进 `skipped`，不参与退出码；只有拿到真实值且与 facts 不符才算 `DRIFT`。避免 service/缓存冷启动时把探测空值误报成新增漂移。

夜间光 / 色温没有查询接口，doctor 不采集。`niri/outputs.kdl` 是 Noctalia 面板维护的单向文件（实机为准），doctor 只沿用 check-sync 的 `state` 语义记录差异，不做仓库↔实机双向判定。

```shell
./doctor/doctor                     # 检查
./doctor/doctor --accept            # 把当前所有 DRIFT 写进 doctor/baseline.toml
./doctor/doctor --refresh           # 从 DMI、niri、backlight、ddcutil、fc-match、fcitx5、已装终端重采事实
./doctor/doctor --render            # 按事实重写 README 环境段
./doctor/doctor --refresh --render  # 硬件或布局变了以后一次改完
./doctor/doctor --summary           # 单行晨报；有新增时附最多 5 条明细
./doctor/doctor --json              # 同一次检查的稳定 JSON
./doctor/doctor --since 24h         # 从 doctor.log 汇总窗口内的新增 / 修复
```

`--accept` 只在人工确认“这些漂移现在可以接受”时用：它按当前 `DRIFT` 重写整个 baseline（按 id 排序，保留已有 `reason`）。之后命中且观测值一致的项显示 `BASELINED`；新增漂移、baseline 观测值变化都返回非零。baseline 里有、当前已不漂移的项显示 `INFO 已修复，可 --accept 收紧基线`，但不会自动删除。

doctor 只读 niri、kanshi、alacritty、noctalia 的配置，不会为了变绿去改它们；kanshi、check-sync 报出的真实差异交回各自维护者。

### 每日巡检与晨报

每次完整检查（默认、`--summary`、`--json`）都只读仓库，同时把状态写到
`~/.local/state/doctor/`：`last.json` 是最近一次结果（tmp + rename 原子覆盖），
`doctor.log` 是追加的 JSONL（同一 schema）。`--accept` / `--refresh` / `--render`
沿用原来的写模式，不写这两个状态文件。

- `--summary`：汇总行固定为
  `配置漂移: 漂移 N · baseline N · known N · 昨日新增 N · 最近变更 <无|漂移条目>`；
  有新增时从第二行起列 `+ <id>（<值变|新增>）`，最多 5 条，多则 `+ 还有 N 条`。
  「昨日新增」是 `doctor.log` 近 24h 的去重新增 id 数；「最近变更」对比 `doctor.log`
  上一次巡检，只列自上次以来新增（`+`）或修复（`-`）的漂移条目，零变化为 `无`。
- `--json`：单个对象，字段顺序固定为
  `ts, schema, checks, items, drift, baselined, known, skipped, exit, added[{id,detail,kind}], fixed[{id}], duration_ms`。
  `schema` 目前为 `1`；`items` 与 `checks` 都是检查总数（61 是其中一项分母），
  因为 fcitx5 激活输入法行始终输出，同一台机器的 `items` 不随焦点变化。
- `--since`：接受 `24h`（也支持 `30m` / `2d` 这类写法）、`yesterday`、`today`、
  `YYYY-MM-DD`、`YYYY-MM-DDTHH:MM`；窗口内无变化打印 `无变化`，否则每行
  `<时间> <+/-> <id> <detail>`（同一 id 的同向事件只留最后一次）。

systemd user timer（手动安装，doctor 和 `install.sh` 都不会偷偷改 systemd）：

```shell
install -Dm644 systemd/user/doctor-daily.service ~/.config/systemd/user/doctor-daily.service
install -Dm644 systemd/user/doctor-daily.timer ~/.config/systemd/user/doctor-daily.timer
systemctl --user daemon-reload && systemctl --user enable --now doctor-daily.timer
```

`doctor-daily.timer` 用 `OnCalendar=*-*-* 07:00:00` + `Persistent=true`（关机错过则开机补跑）；
service 固定 `WorkingDirectory=/home/xendr1a/system/My_config-x`、`Environment=LANG=C.UTF-8`，
`ExecStart` 用绝对路径 `/home/xendr1a/system/My_config-x/doctor/doctor --summary`；仓库换位置时
这三处一起改。输出进 journal，`doctor.log` 由 doctor 自己写，单元不重复重定向。

## 键位速查

niri（`Super` 即 Mod）：

| 键 | 作用 |
|---|---|
| `Mod+T` | 终端 |
| `Mod+D` / `Mod+B` | Noctalia 启动器 / 剪贴板面板 |
| `Super+Alt+L` | 锁屏；`Mod+O` overview |
| `Mod+H/J/K/L` | 焦点：左/下/上/右（加 `Ctrl` 变成移动） |
| `Mod+,` / `Mod+.` | 把右侧窗口并入当前列 / 把列底部窗口弹出为新列 |
| `Mod+[` / `Mod+]` | 上面两个动作的"智能版"：唯一窗口时并入相邻列，列里多窗口时把它拆出去 |
| `Mod+R` / `Mod+Shift+R` | 切换列宽 / 窗高预设；`Mod+F` maximize 列 |
| `Mod+V` 浮动、`Mod+W` 列内 tab 切换、`Mod+Q` 关窗 | |
| `Mod+Shift+E` / `Ctrl+Alt+Delete` | 退出 niri 会话；配置修改由 niri 自动重载 |
| `Mod+Shift+S` | 区域截图 → satty 标注，Enter 复制并存盘到 `~/Pictures/Screenshots` |
| `Mod+Shift+O` | 区域截图 → tesseract OCR（中英）→ 剪贴板 |
| `Mod+A` / `Mod+S` / `Mod+Shift+A` | Manggo 选词翻译 / 截图翻译 / 输入翻译（装法见「Manggo」一节） |
| `Mod+Shift+M` | `solo-display`：只留焦点显示器 / 再按恢复全部 |
| `Print` / `Ctrl+Print` / `Alt+Print` | niri 内置：选区 / 整屏 / 窗口，直接进剪贴板 |

媒体键 `Ctrl+Alt+Left/Right` 或 `XF86AudioPrev/Next`，亮度走 `noctalia msg brightness-up/down`（不再用 brightnessctl）。

截图分两套：`Print` 系走 niri 内置，快，适合立刻要图；`Mod+Shift+S` 和 `Mod+Shift+O` 的选区也走 niri 截图 UI（选区期间冻结画面，grim + slurp 是实时画面，不冻结），选完再由 satty 标注或 tesseract 识别。`Mod+Shift+S` 存盘到 `~/Pictures/Screenshots`，只保留最近 200 张（`SCREENSHOT_KEEP` 可改，0 = 不清理），niri 自带 `Print` 存的图也计入。脚本在 `local/bin/screenshot-annotate`、`local/bin/ocr-region`。

Manggo 的安装、快捷键、自启和截图故障处理见 [Manggo 使用说明](docs/manggo.md)。快捷键由 niri 注册，截图使用 wlr Portal，屏幕共享保留 GNOME 后端。

tmux：前缀 `Ctrl+x`（连按两次透传字面 `Ctrl+x`；另有兼容前缀 `Ctrl+b`）。新建窗口 `Ctrl+x` `c`，横向分割 `-`，纵向 `|`。默认开鼠标，选中即复制到系统剪贴板。

nvim：

`<leader>` 是空格。以下快捷键在普通模式使用：编辑后先按 `Esc`，再依次按空格和后续键（默认两键间隔不超过一秒，无需按住空格）。

| 类别 | 键 |
|---|---|
| 基础 | `t` 开关目录树，`<leader>e` 打开或聚焦目录树，`1`-`9` 切 buffer，`gt`/`gT` 下一个/上一个，`w`/`q` 保存/退出，`<C-_>` 注释，`<Esc>` 清搜索高亮 |
| 窗口 | `<C-h/j/k/l>` 移到左/下/上/右窗口；`<leader>ww` 循环切换，`<leader>ws`/`<leader>wv` 横分/竖分，`<leader>wc` 关闭，`<leader>wo` 只留当前窗口，`<leader>w=` 等宽等高 |
| 模糊搜索 | `<leader>ff` 文件名，`<leader>fs` 全局搜内容，`<leader>fb` buffer，`<leader>fh` 最近文件，`<leader>fg` git 改动 |
| LSP | `gd` 定义，`gr` 引用，`K` 悬停，`<leader>rn` 重命名，`<leader>ca` code action，`<leader>af` 格式化，`[g`/`]g` 诊断 |
| Git | `gn`/`gp` 上下 hunk，`<leader>gb` blame，`<leader>gp` 预览，`<leader>gr` 重置 |

Orca 内的 `Ctrl+W` 会关闭应用标签页，窗口操作使用上面的 `<leader>w…`；例如 `Esc` → 空格 → `e` 可从文件回目录树，树已关闭时也会打开。

补全 nvim-cmp + pyright；保存时 conform.nvim 调 black + isort；诊断只显示 ERROR。Markdown / rst / diff 不做全局行尾空白清理，保留有语义的空格。

## 装机

```shell
# 1. 装包：packages/official.txt 与 packages/foreign.txt 是本机实际包清单，重新装机时按它补
./tool/mycfg-pkgs install      # 打印缺哪些、怎么装（不执行）
# 关键几项（其余见清单）：
sudo pacman -S niri noctalia noctalia-greeter-git greetd xwayland-satellite alacritty tmux neovim \
               zsh fcitx5 fcitx5-chinese-addons fcitx5-qt fcitx5-gtk fcitx5-qingjian-git \
               kanshi swaybg firejail pwndbg qt6ct jq satty fzf wl-clipboard \
               tesseract tesseract-data-chi_sim tesseract-data-eng \
               xdg-desktop-portal-gnome xdg-desktop-portal-gtk xdg-desktop-portal-wlr
# 非官方仓库：oh-my-zsh-git（提供 /usr/share/oh-my-zsh）、yay、niri-display-settings-git、manggo（翻译，可选）
# powerlevel10k 走 zsh-theme-powerlevel10k-git；zsh-autosuggestions / zsh-syntax-highlighting 也在 official 清单
# p10k instant prompt 需要 ~/.p10k.zsh（MANIFEST 里 home 之外的 p10k/.p10k.zsh）

# 2. 取仓库并安装（本机就是这套配置的源）
git clone https://github.com/Xendr1a/My_config && cd My_config
./install.sh            # 只打印计划
./install.sh --apply    # 真正写入（root 条目仍只打印 sudo 命令）

# 3. 收尾
./tool/mycfg-post           # 从 MANIFEST 打印后续步骤
./tool/mycfg-post --apply   # 执行 chmod 与 tmux 链接；systemctl 命令仍需自己跑
```

`install.sh` 不会碰 `archive/`。装完想确认有没有漏同步：

```shell
./tools/check-sync.sh          # 全量
./tools/check-sync.sh niri     # 只看匹配项
```

安装默认保留 MANIFEST 中标记为 `state` 的已有文件（Noctalia settings、fcitx5 profile），缺失时才初始化。只有明确恢复留档状态时才用 `./install.sh --apply --restore-state`；该选项会覆盖现有状态。

`environment.d/` 里的变量要重新登录才对 niri 启动的应用生效。

greetd 的两个文件（`/etc/greetd/config.toml`、`/etc/pam.d/greetd`）装完都不需要重启 greetd：前者在 greetd 下次启动时读，后者每次认证都重读一遍。**不要在图形会话里跑 `systemctl restart greetd`** —— greeter 会去抢 `vt = 1`，把当前 niri 会话挤成 inactive：桌面消失、进程还在，再登录会被 `niri-session` 的 `A niri session is already running.` 挡在门外。真要立刻生效，等登出到登录界面之后再重启。万一已经踩了：`loginctl list-sessions` 找到自己那个 seat0 会话，切到另一块 VT 跑 `loginctl activate <会话号>`；同一块 VT 被 greeter 占着就先 `sudo systemctl stop greetd`。

## 迁移

`tool/mycfg-migrate list` 列出待办（无待办时退出码为 3），`tool/mycfg-migrate run` 只打印计划，
确认后用 `tool/mycfg-migrate run --apply` 严格按顺序执行。安装不会自动执行迁移。
成功的迁移在 `${XDG_STATE_HOME:-$HOME/.local/state}/my_config/migrations` 下记录 marker；
可用 `MYCONFIG_STATE_DIR` 覆盖整个目录。失败不记 marker，并停止后续迁移。
配置退役后需要清理旧路径、或有一次性状态修复时写一条迁移，遵守 [迁移约定](migrations/README.md)。

## 测试

运行 `./test/run` 执行 `test/cases/` 下的本地用例；`./test/run --host` 额外检查实机漂移。
可以用 `./test/run --filter manifest` 筛选文件名。失败时看输出中的日志路径，
每个用例的完整 stdout/stderr 都保留在打印的日志目录中。
`./test/run --filter doctor` 只跑环境自检用例（需要可用的 niri 会话）。

## 软件包

`packages/official.txt` 是官方仓库的显式安装，`packages/foreign.txt` 是 AUR 或手工编译的，
只记包名不记版本。三档用法：

```bash
./tool/mycfg-pkgs check            # 缺哪些、哪些装了但没记录
./tool/mycfg-pkgs write --apply    # 按当前机器重写清单（默认只预览 diff）
./tool/mycfg-pkgs install          # 打印补齐命令，不执行
```

换机器或重装后先运行 `tool/mycfg-pkgs install` 并手动执行它打印的装包命令，再运行 `./install.sh`。`install.sh` 结尾会自动提示缺包数量。

## 外接显示器（Noctalia niri-displays 面板）

本机不用 kanshi：输出布局由 Noctalia 的 `niri-displays` 插件（`niri-display-settings-git`）管理，右上角显示器图标就是面板。

- `niri/config.kdl` 里没有 `output` 块，只有 `include "outputs.kdl"`；面板每次改动都会重写 `~/.config/niri/outputs.kdl`（已收进 MANIFEST，标记 `state`）
- 关闭（off）状态不写进 `outputs.kdl`，避免拔掉外接屏后一个可用输出都没有
- `~/.config/niri/displays-policy.json` 是面板策略：`{"focus_external":true,"internal_off_with_external":true}` = 接外接屏时关内屏、焦点落在外接屏
- 想要"只留当前屏 / 全部打开"又不进面板：`Mod+Shift+M` 跑 `local/bin/solo-display`（toggle，可带 `solo` / `all` 参数，依赖 `niri msg -j` + `jq`）

手动改 `outputs.kdl` 也能生效，但下次在面板里动一下就会被覆盖。

## Noctalia v5

- 启动：niri `spawn-at-startup "noctalia"`；IPC 一律 `noctalia msg ...`（旧的 `qs -c noctalia-shell ipc call ...` 已失效）
- `~/.config/noctalia/config.toml`：声明式配置——backdrop、启动器/剪贴板面板里把 Tab 映射到 Up/Down
- `~/.local/state/noctalia/settings.toml`：运行时状态，**优先级高于 config.toml**。GUI 里改任何设置（换壁纸、调动画、开关组件）都会整份重写它，所以它一直在漂。改完设置同步进仓库：

  ```shell
  cp ~/.local/state/noctalia/settings.toml noctalia/settings.toml
  ```

- overview 背景要 `backdrop.enabled=true`（config 和 state 两处都要）+ niri 里 `match namespace="^noctalia-backdrop"`
- 声明式的值"不生效"时，先 grep state 那份

## 输入法

fcitx5。`fcitx5/profile` 的留档默认输入法是 `pinyin`，该文件按运行状态管理，普通安装保留实机已有选择；不再收录 `conf/cached_layouts` 缓存。切换键 `Ctrl+Shift`，另绑 `Alt+Shift`。
云拼音已开启，配置为 `fcitx5/conf/pinyin.conf` 中的 `CloudPinyinEnabled=True`；拼音、繁简转换和标点配置按实机留档。
环境变量在 `/etc/environment`：`QT_IM_MODULE` / `SDL_IM_MODULE` / `GLFW_IM_MODULE` / `XMODIFIERS`；`GTK_IM_MODULE` 是注释掉的——GTK 应用走原生 text-input，不需要它。

## GTK / Electron 暗色

`gtk-3.0/settings.ini` 与 `gtk-4.0/settings.ini` 用 `Adwaita` + `prefer-dark`，`environment.d/gtk-dark.conf` 再给 `GTK_THEME=Adwaita:dark`。

不要写成 `Adwaita-dark`：Electron 会把它当亮色主题，Obsidian / Sidra 就会变白（本机也没装 `gnome-themes-extra`，这个名字没有对应主题目录）。gsettings 里是 `gtk-theme='Adwaita'`、`color-scheme='prefer-dark'`。

## system-files（/etc 与 /usr/local）

只收手工改过、重装系统不会自动生成的东西：

- `/etc/greetd/config.toml` — greeter 命令与会话用户（`vt=1`、`noctalia-greeter-session`）
- `/etc/environment` — 输入法环境变量
- `/etc/pacman.conf` — multilib、blackarch（清华镜像 + `Required DatabaseOptional TrustedOnly`）、archlinuxcn、arch4edu（后两者继承全局签名策略）
- `/etc/pam.d/greetd` — 末尾追加的 `pam_gnupg` 段（登录时把密码预置给 session 阶段，供 gpg-agent 自动解锁）
- `/etc/systemd/system/clash-verge-service.service`、`/etc/systemd/system/kvm-nat-bypass-routes.service` + `/usr/local/sbin/kvm-nat-bypass-routes.sh`（后者用 `ip rule` 8800/8900 让 `192.168.122.0/24` 的 VM 流量绕开 mihomo TUN）
- `/etc/udev/rules.d/50-nuphy.rules`、`50-vgn-mouse.rules`、`90-micmute-led.rules`

**故意没收**：`/etc/fstab`、`/etc/kernel/cmdline`、`/etc/mkinitcpio.d/linux.preset`、`/etc/mkinitcpio.conf`、`/etc/locale.conf`、`/etc/vconsole.conf` —— 装系统时生成，而且夹带 UUID / PARTUUID 这类本机指纹，备份它们对恢复没有价值（换盘就变），需要时重装时重写即可。`/etc/nftables.conf` 也没收：本机 `nftables.service` 是 disabled + inactive，实际生效的是 firewalld。

## 麦克风静音 LED

ThinkPad Fn+麦克风键默认的 `audio-micmute` trigger 状态不同步，这里用脚本盯 PipeWire 事件手动控 LED：`micmute-led/micmute-led-sync.sh`（装到 `~/.local/bin/`）+ user 服务 + udev 规则。

前提：用户在 `input` 组。踩过的两个坑：

- udev 的 `GROUP=` / `MODE=` 只对 `/dev/` 节点生效，`/sys` 下的 sysfs 属性（LED 的 brightness）必须用 `RUN+=/usr/bin/chmod` + `RUN+=/usr/bin/chgrp`
- systemd 的 `StartLimitIntervalSec` 必须写在 `[Unit]` 段，写在 `[Service]` 会被忽略

## Java / X11 应用

`environment.d/java-awt.conf` 给 `_JAVA_AWT_WM_NONREPARENTING=1`（niri 这种非重父化合成器下防 Swing 窗口空白），`environment.d/xwayland-satellite.conf` 给 `DISPLAY=:0`，让 HMCL 这类还依赖 X11 的程序找到 xwayland-satellite。

## CTF 样本沙箱（ctfdbg / ctfrun）

跑来路不明的二进制（题目附件、别人的 exp、AWD 里对手放的样本）等于把家目录、密钥、网络身份一起交出去。这两个是 firejail 包装器，默认只让样本看到它所在的当前目录。

```shell
cd ~/samples/bin/<题目>       # 必须先在样本目录里，别在 ~ 下跑
ctfdbg demo                   # 沙箱里用 pwndbg 调试（裸文件名自动补 ./）
ctfdbg demo -ex 'b *main'     # 后面的参数原样传给 gdb
ctfrun ./chall                # 直接跑样本
ctfrun python3 exp.py         # 跑 exp
ctfrun bash                   # 进沙箱内部看：mount / capsh --print / ls -a ~
ctfrun -n ./chall             # 放开网络（用你的 IP 出去）
```

同一用户在同一实际目录（按 `pwd -P` 解析软链接）、同一联网模式下，`ctfrun` 和 `ctfdbg` 会自动复用同一个具名沙箱；不同目录或不同联网模式使用独立沙箱。跨终端附加时，直接使用 exp 打印的沙箱内 PID：

```shell
# 终端 1：进入题目目录，启动 exp，保持目标进程存活（可在 process() 后 pause()）
ctfrun python3 ./exp_32_m.py

# 终端 2：进入同一题目目录，PID 以 exp 实际输出为准
ctfdbg -q -p 9
```

需要联网时两个命令都加 `-n`；默认断网命令不会加入联网沙箱。最后一个进程退出后沙箱结束，下次自动新建。升级前已运行的旧沙箱需要退出后重开。共享沙箱解决 PID 可见性，附加仍需满足系统 ptrace 权限。

| 参数 | 作用 | 代价 / 注意 |
|---|---|---|
| `--whitelist=$(pwd)` | 家目录换成空 tmpfs，只挂当前目录 | 看不到 `~/.ssh`、`~/.hermes`、`~/Documents` |
| `--net=none`（默认） | 只留 loopback，需要联网时加 `-n` | 断网 |
| `--private-tmp` / `--private-dev` | 私有 `/tmp`、精简 `/dev` | 样本写的临时文件退出即消失 |
| `--nodbus` | 不给 session dbus | 剪贴板 / 通知 / secret service 都用不了 |
| `--nosound` `--no3d` | 无音频 / 3D 设备 | — |
| `--caps.drop=all` / `--nonewprivs` / `--seccomp` | 丢能力、禁提权、拦危险 syscall | 极少数样本会被拦，属正常 |
| `--rlimit-nproc=2000` | 进程数上限 | 防 fork 炸弹拖死机器 |
| `--allow-debuggers` | 放行 ptrace | 必须开，否则 gdb 用不了 |

zsh 补全在 `local/completions/_ctfrun`（两个脚本共用，靠 `#compdef ctfrun ctfdbg`）。按脚本自己的解析顺序给候选：命令之前只补 `-n/--net/--no-net/-h/--help`，第一个词补当前目录里可执行的文件 + PATH 里的外部命令（`ctfrun python3 exp.py`），再往后原样透传只补文件名——`ctfrun ./chall -n` 里那个 `-n` 是给样本的，所以不会当自己的选项补出来。

系统目录（`/usr` `/lib` `/etc`）仍可见但只读——动态链接的程序必须读到 libc / ld.so 才能跑，把它们也藏起来程序根本起不来。

安全性边界：和 docker 同一批内核机制（namespace + seccomp + caps），**挡不住内核 0day**；当前目录可写，别把唯一原件放进去跑；联网档下样本以你的网络身份对外发流量。

## Hermes gateway

`systemd/user/hermes-gateway.service` 与 `.d/` 的四个 drop-in 均由 MANIFEST 管理：launch.conf 使用 `/usr/bin/hermes` wrapper，proxy.conf 配置 7897 代理，computer-use-wayland.conf 启用 Wayland，override.conf 保留 `OOMPolicy=continue`。

## Steam（niri / Xwayland）

Steam 在这台机器上有两个独立毛病，都有现成脚本：

1. **启动死锁**：launcher 先建 `~/.steam/steam.pipe`、再 re-exec 自己，新实例只要能打开 pipe 就判定"已有实例"，把命令行转发给已经卡死的进程然后退出。表现是点图标没反应。
   `local/bin/steam-fix`：清掉卡死的 launcher/UI → 删 `steam.pid`/`steam.pipe`/ValveIPC 共享内存 → `mkfifo steam.pipe && chmod 000`（launcher 打不开就不会误判）→ `LIBGL_ALWAYS_SOFTWARE=1` 启动 `steamrt64/steam -cef-disable-gpu`。

2. **`gldriverquery` 挂死烧 CPU**：Xwayland 下 GLX 建上下文失败
   ```
   X Error of failed request: BadValue   (GLX, X_GLXCreateContext)
   ```
   报完不退出，每个实例各占 100% CPU（实测三个实例把 load 顶到 4.3）。`LIBGL_ALWAYS_SOFTWARE=1` 绕不过去，因为卡的就是 GLX 那一步；把二进制换成立即退出的 stub 也不行——Steam 启动时会从自己的 depot 把 `ubuntu12_32/64/gldriverquery` 还原回去。
   最终做法是看门狗：`local/bin/steam-gldriverquery-guard`（活过 10 秒的实例直接 kill，每 10 秒扫一次）+ `systemd/user/steam-gldriverquery-guard.service`（随 `graphical-session.target` 启动，`Restart=always`）。

```shell
./install.sh --apply                      # 装脚本与单元
systemctl --user enable --now steam-gldriverquery-guard.service
systemctl --user status steam-gldriverquery-guard.service
~/.local/bin/steam-gldriverquery-guard status   # 当前有没有卡住的实例
```

Steam 自己更新后 `gldriverquery` 会被替换，但看门狗只按进程名匹配，不受影响。游戏（Proton/DXVK 走 Vulkan）不受这个 helper 影响。

## Manggo（翻译 / 截图 OCR）

AUR `manggo`（proprietary，1.2.2-2）。本机**不走 pacman 安装**：按 AUR 的 PKGBUILD 打包后把内容解到 `~/opt/manggo`，入口是包装器 `~/.local/bin/Manggo`。

不直接 `yay -S manggo` 的原因：`package()` 里的 `patchelf --set-rpath` 在 fakeroot 下会失败——

```
bwrap: Creating new namespace failed: Operation not permitted
```

`fakeroot -- patchelf --print-rpath <file>` 可稳定复现，`env -i patchelf` 就正常，是 fakeroot 的 `LD_PRELOAD` 和 patchelf 打架。跳过那一步是安全的：现有 `DT_RUNPATH` 已经是 `$ORIGIN:$ORIGIN/..:<上游 CI 泄漏路径>`，`$ORIGIN` 在前，补丁只是删掉尾部那条无意义路径。

重现步骤：

```shell
git clone https://aur.archlinux.org/manggo.git /tmp/mgb && cd /tmp/mgb
# 注释掉 package() 里的 patchelf 两行
makepkg -f --noconfirm                      # 产出 manggo-1.2.2-2-x86_64.pkg.tar.zst
bsdtar -xf manggo-*.pkg.tar.zst -C ~/opt/manggo
```

`~/.local/bin/Manggo` 只是透传包装器（`exec ~/opt/manggo/usr/lib/manggo/bin/Manggo "$@"`）。三个键位用 `spawn-sh "exec ~/.local/bin/Manggo --action …"`，因为 niri 的 `spawn` 不走 shell、PATH 里没有 `~/.local/bin`。`Manggo --list-actions` 可核对动作名。

登录自启**没开**：第一次按键会自动拉起。想开机常驻就把 `autostart/Manggo.desktop` 复制到 `~/.config/autostart/`（其中 Exec 已指向包装器）。

Manggo 自己的设置（翻译服务、OCR 服务、语言偏好）在它 GUI 里改，配置落在 `~/.config/Manggo/`，不纳入仓库。

## 与上游的差异（本机未落地项）

仓库继承自 Mel-SRK/My_config，以下上游条目在本机不存在对应硬件或另有替代，故意没有部署：

| 上游条目 | 本机情况 |
|---|---|
| `micmute-led/`（脚本 + user 服务 + udev 规则） | 本机 `/sys/class/leds/` 没有麦克风静音 LED 节点，ThinkPad 专有 |
| `system-files/etc/udev/hwdb.d/61-battery-local.hwdb` | `BAT0` 没有 `charge_control_start_threshold`，不支持充电阈值 |
| `kanshi/config` + `systemd/user/kanshi.service` | 外接屏由 Noctalia `niri-displays` 面板管理（见上一节），kanshi 已装但不用 |
| `systemd/user/hermes-gateway*` | 本机 Hermes 由 CLI/会话直接跑，没有常驻 gateway 单元 |
| `system-files/etc/systemd/journald.conf.d/10-size.conf` | 未落地；需要时 `sudo install -Dm644` 后 `sudo systemctl restart systemd-journald` |
| `autostart/Manggo.desktop` | 自启没启用（首次按键会拉起 Manggo），Exec 已指向 `~/.local/bin/Manggo` |

截图 / OCR 链路的依赖已装齐（`satty` 0.22、`fzf`、`tesseract-data-chi_sim`、`xdg-desktop-portal-wlr`），
`test/cases/80-capture.sh` 会现场验证：satty 的四个标志都在 `--help` 里、造图跑一遍 `chi_sim+eng` 能认出关键字。

- `Mod+Shift+O` 的默认语言是 `chi_sim+eng`，只有 `eng` 时中文识别为空——`tesseract-data-chi_sim` 是硬依赖
- `niri-portals.conf` 把 Screenshot 路由到 wlr 后端，改完要 `systemctl --user restart xdg-desktop-portal.service`
- `wl-clipboard`：本机不是 pacman 包，是解包到 `~/opt/wl-clipboard` 并软链到 `~/.local/bin`
- Manggo 已装成 `~/opt/manggo` + `~/.local/bin/Manggo` 包装器（见上一节），三个翻译键位已启用
- nvim 插件锁版本留的是本机已装的旧版（上游把 `lazy-lock.json` 整体往前推了一版），要跟上用 `:Lazy update`
