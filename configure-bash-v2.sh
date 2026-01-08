#!/bin/bash

# configure-bash.sh

# bashrc에 추가할 내용을 생성
BASHRC_CONTENT='
# AWS CLI 자동완성 설정
complete -C '\''/usr/local/bin/aws_completer'\'' aws
export AWS_REGION=ap-northeast-2
export AWS_DEFAULT_REGION=ap-northeast-2
export AWS_BEDROCK_REGION=us-west-2

# Git 브랜치와 상태를 표시하는 함수
parse_git_branch_and_status() {
    local branch=$(git branch 2> /dev/null | sed -e '\''/^[^*]/d'\'' -e '\''s/* \(.*\)/\1/'\'')
    if [ ! -z "$branch" ]; then
        local status=""
        # 변경된 파일 수 계산
        local modified=$(git status --porcelain 2> /dev/null | grep '\''^.M'\'' | wc -l)
        local added=$(git status --porcelain 2> /dev/null | grep '\''^A'\'' | wc -l)
        local deleted=$(git status --porcelain 2> /dev/null | grep '\''^.D'\'' | wc -l)
        local untracked=$(git status --porcelain 2> /dev/null | grep '\''^??'\'' | wc -l)

        # 상태가 있는 경우에만 표시
        [ $modified -gt 0 ] && status="${status}~${modified}"
        [ $added -gt 0 ] && status="${status}+${added}"
        [ $deleted -gt 0 ] && status="${status}-${deleted}"
        [ $untracked -gt 0 ] && status="${status}?${untracked}"

        # 상태가 없으면 깨끗한 상태
        [ -z "$status" ] && status="✓"

        echo "($branch $status)"
    fi
}

# pyenv 설정
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"

# pyenv 초기화
eval "$(pyenv init - bash)"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# 프롬프트 설정
export PS1='\''\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[33m\]$(parse_git_branch_and_status)\[\033[00m\]\$ '\''

# OpenAI API 키 설정 안내 메시지
if [ -z "$OPENAI_API_KEY" ]; then
    echo "OpenAI 모델을 활용하기 위하여 다음과 같이 환경 변수를 설정하세요."
    echo "export OPENAI_API_KEY=sk-proj-XXXXXXXX"
fi

alias vi=vim
# unalias python pip

export N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true

#alias code='\''code-server'\''
'

# bashrc 파일 백업
if [ -f ~/.bashrc ]; then
    cp ~/.bashrc ~/.bashrc.backup.$(date +%Y%m%d_%H%M%S)
    echo "Created backup of existing .bashrc file"
fi

# 새로운 내용을 bashrc에 추가
echo "$BASHRC_CONTENT" >> ~/.bashrc

# bashrc 새로고침
source ~/.bashrc

echo "Bash configuration has been updated successfully!"
