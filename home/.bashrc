#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# 环境与 ~/.profile / ~/.zshenv 保持一致：交互 bash 也要有 JAVA_HOME
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
export JAVA_HOME="$HOME/opt/jdk/jdk-17.0.21+9"
