# 提示符、补全、插件只在真的有终端时加载。工具用管道跑 `zsh -i -c` 时没有控制终端，
# job control 开不起来：powerlevel10k 的 gitstatus 在 `setopt monitor` 处失败，
# 先打印 can't change option: monitor，再打印 gitstatus failed to initialize，
# 这些噪声会盖在命令自己的输出前面，看起来像命令出错。
typeset -gi __have_tty=0
[[ -o interactive && -t 0 && -t 1 ]] && __have_tty=1

# 环境变量对所有 shell 生效，包括没有终端的工具调用
# PATH 幂等：交互式 shell 里再起 zsh 时不要重复叠加同一目录
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
export EDITOR="nvim"
export VISUAL="nvim"

# 与 environment.d/qt-theme.conf 一致；覆盖旧会话继承的 qt5ct。
export QT_QPA_PLATFORMTHEME=qt6ct

# Clash Verge 代理
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
export all_proxy=socks5://127.0.0.1:7897
# 本地开发服务直连；保留已有例外。
typeset -aU __proxy_bypass
__proxy_bypass=(localhost 127.0.0.1 ::1 "${(@s:,:)no_proxy}" "${(@s:,:)NO_PROXY}")
export no_proxy="${(j:,:)__proxy_bypass:#}"
export NO_PROXY="$no_proxy"
unset __proxy_bypass

# 登录进 tmux 由 alacritty 的 [terminal.shell] 负责（见 ~/.config/alacritty/alacritty.toml），
# 这里不再 attach：p10k instant prompt 会接管 stdin，放在 zshrc 里必报
# "open terminal failed: not a terminal"。

if (( __have_tty )); then
    # Enable Powerlevel10k instant prompt
    if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
      source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
    fi

    # Oh My Zsh
    export ZSH="/usr/share/oh-my-zsh"
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

    # Theme
    ZSH_THEME="powerlevel10k/powerlevel10k"

    # Plugins
    plugins=(
        git
        z
        zsh-autosuggestions
        zsh-syntax-highlighting
    )

    source $ZSH/oh-my-zsh.sh

    # User aliases
    alias vim="nvim"
    alias vi="nvim"
    alias ls="ls --color=auto"
    alias ll="ls -la"
    alias la="ls -A"

    # fzf：Ctrl+R 历史、Ctrl+T 文件、Alt+C 跳目录、**<Tab> 补全
    if command -v fzf >/dev/null 2>&1; then
        source <(fzf --zsh)
    fi

    # pkgfile：command-not-found 时提示「命令属于哪个包」
    # 数据库由系统级 pkgfile-update.timer 维护（sudo systemctl enable --now pkgfile-update.timer）
    [[ -r /usr/share/doc/pkgfile/command-not-found.zsh ]] &&
        source /usr/share/doc/pkgfile/command-not-found.zsh

    # p10k 配置
    [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

    # 可选工具：未安装时不影响 shell 启动。
    if command -v thefuck >/dev/null 2>&1; then
        eval "$(thefuck --alias)"
    fi

    # Oh-my-pi（本机未装则跳过）
    if command -v omp >/dev/null 2>&1; then
        eval "$(omp completions zsh)"
    fi
fi
