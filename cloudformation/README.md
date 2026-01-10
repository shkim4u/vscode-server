# VSCode Server CloudFormation 배포 가이드 (Remote SSH 공개키 포함)

## 추가된 RemoteSSHPublicKey 파라미터를 포함한 배포 예시입니다.

1. SSH 키 생성 (Windows)

Windows에서 PowerShell 또는 Git Bash를 사용하여 SSH 키를 생성합니다.

* SSH 키 생성 (ed25519 알고리즘 사용)

ssh-keygen -t ed25519 -C "vscode-remote-ssh" -f ~/.ssh/vscode-remote-ssh

* 또는 RSA 알고리즘 사용

ssh-keygen -t rsa -b 4096 -C "vscode-remote-ssh" -f ~/.ssh/vscode-remote-ssh

2. 공개키를 환경 변수로 설정

* Windows PowerShell

$env:REMOTE_SSH_PUBLIC_KEY = Get-Content ~/.ssh/vscode-remote-ssh.pub -Raw

* Windows Git Bash / Linux / macOS

export REMOTE_SSH_PUBLIC_KEY=$(cat ~/.ssh/vscode-remote-ssh.pub)

3. CloudFormation 배포 명령어 (파라미터 추가)

```bash
export GITHUB_TOKEN=<YOUR_GITHUB_PAT>

export REMOTE_SSH_PUBLIC_KEY=$(cat ~/.ssh/vscode-remote-ssh.pub)

curl -sL https://raw.githubusercontent.com/shkim4u/vscode-server/main/cloudformation/vscode-server-stack.yaml -o /tmp/vscode-server-stack.yaml && \
aws cloudformation deploy \
--stack-name VSCodeServerStack \
--template-file /tmp/vscode-server-stack.yaml \
--parameter-overrides \
InstanceType=m7i.2xlarge \
VSCodeServerVersion=4.107.0 \
GitHubAccessToken=$GITHUB_TOKEN \
RemoteSSHPublicKey="$REMOTE_SSH_PUBLIC_KEY" \
--capabilities CAPABILITY_IAM \
--region ap-northeast-2
```

4. SSH 공개키 없이 배포하는 경우

SSH Remote 기능이 필요 없다면 파라미터를 생략하거나 빈 문자열로 전달할 수 있습니다.

```bash
export GITHUB_TOKEN=<YOUR_GITHUB_PAT>

curl -sL https://raw.githubusercontent.com/shkim4u/vscode-server/main/cloudformation/vscode-server-stack.yaml -o /tmp/vscode-server-stack.yaml && \
aws cloudformation deploy \
--stack-name VSCodeServerStack \
--template-file /tmp/vscode-server-stack.yaml \
--parameter-overrides \
InstanceType=m7i.2xlarge \
VSCodeServerVersion=4.107.0 \
GitHubAccessToken=$GITHUB_TOKEN \
RemoteSSHPublicKey="" \
--capabilities CAPABILITY_IAM \
--region ap-northeast-2
```

5. 배포 후 VSCode Remote SSH 연결

배포가 완료되면 다음과 같이 VSCode Remote SSH로 연결할 수 있습니다.

* EC2 Public IP 확인

```bash
aws cloudformation describe-stacks \
--stack-name VSCodeServerStack \
--query 'Stacks[0].Outputs[?OutputKey==`VSCodeServerPublicIP`].OutputValue' \
--output text \
--region ap-northeast-2
```

* VSCode에서 Remote SSH 연결 설정 (~/.ssh/config)

```
Host vscode-server
HostName <EC2_PUBLIC_IP>
User ubuntu
IdentityFile ~/.ssh/vscode-remote-ssh
```

참고사항:
- SSH 공개키는 반드시 따옴표로 감싸서 전달해야 합니다 (RemoteSSHPublicKey="$REMOTE_SSH_PUBLIC_KEY")
- 생성된 개인키(~/.ssh/vscode-remote-ssh)는 안전하게 보관하고 공유하지 마세요
- 공개키는 ssh-ed25519 AAAA... 또는 ssh-rsa AAAA...로 시작하는 한 줄의 문자열입니다
