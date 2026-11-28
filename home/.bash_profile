# 让 login bash 也拿到 ~/.profile 里的环境（PATH/JAVA_HOME/输入法）
[[ -f ~/.profile ]] && . ~/.profile
#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc
