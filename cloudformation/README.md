# VSCode Server CloudFormation 배포 가이드

## 주요 기능
- Remote SSH 공개키 지원
- 자동 시작/중지 스케줄링 (KST 기준 08:00 시작 / 20:00 중지)
- 작업 중 자동 중지 방지 기능 (AutoStop 태그)
- S3 버킷을 통한 대용량 템플릿 배포 지원

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

3. CloudFormation 배포

**참고**: 템플릿 크기가 51,200 바이트를 초과하므로 S3 버킷이 필요합니다.

### 방법 1: 배포 스크립트 사용 (권장)

배포 스크립트는 S3 버킷을 자동으로 생성하고 관리합니다.

#### 배포 파라미터

| 파라미터 | 환경변수 | 커맨드라인 옵션 | 기본값 | 설명 |
|---------|---------|----------------|--------|------|
| 프로젝트 이름 | PROJECT_NAME | --project-name | ax-on-mastery | 배포할 프로젝트 이름 |
| 인스턴스 타입 | INSTANCE_TYPE | --instance-type | m5.2xlarge | EC2 인스턴스 타입 |
| VSCode 버전 | VSCODE_SERVER_VERSION | --vscode-server-version | 4.109.2 | VSCode Server 버전 |
| 프로젝트 배포 | DEPLOY_PROJECT_RESOURCE | --deploy-project-resource | True | 프로젝트 리소스 배포 여부 |
| 최소 초기화 | DEPLOY_INIT_MINIMAL | --deploy-init-minimal | False | 최소 초기화 배포 여부 |

**간단한 버전 (환경변수 사용)**:
```bash
# 환경 변수 설정
export GITHUB_TOKEN=<YOUR_GITHUB_PAT>
export REMOTE_SSH_PUBLIC_KEY=$(cat ~/.ssh/vscode-remote-ssh.pub)

# 선택사항: 기본값을 변경하려면 아래 환경변수 설정
export PROJECT_NAME=my-project              # 기본값: ax-on-mastery
export INSTANCE_TYPE=m5.2xlarge             # 기본값: m5.2xlarge
export VSCODE_SERVER_VERSION=4.109.2        # 기본값: 4.109.2
export DEPLOY_PROJECT_RESOURCE=True         # 기본값: True
export DEPLOY_INIT_MINIMAL=False            # 기본값: False

# 스크립트 다운로드 및 실행
curl -sL https://raw.githubusercontent.com/shkim4u/vscode-server/main/deploy-simple.sh | bash
```

**상세한 버전 (커맨드라인 파라미터 사용)**:
```bash
# 환경 변수 설정
export GITHUB_TOKEN=<YOUR_GITHUB_PAT>
export REMOTE_SSH_PUBLIC_KEY=$(cat ~/.ssh/vscode-remote-ssh.pub)

# 스크립트 다운로드 및 실행
curl -sL https://raw.githubusercontent.com/shkim4u/vscode-server/main/deploy.sh -o deploy.sh
chmod +x deploy.sh

# 기본값으로 배포
./deploy.sh

# 커스텀 설정으로 배포
./deploy.sh \
  --project-name my-project \
  --instance-type m5.2xlarge \
  --vscode-server-version 4.109.2 \
  --deploy-project-resource True \
  --deploy-init-minimal False

# 도움말 보기
./deploy.sh --help
```

#### 사용 예시

**예시 1: GPU 인스턴스로 배포**
```bash
export GITHUB_TOKEN=<YOUR_GITHUB_PAT>
export REMOTE_SSH_PUBLIC_KEY=$(cat ~/.ssh/vscode-remote-ssh.pub)

./deploy.sh \
  --instance-type g5.12xlarge \
  --project-name my-ml-project
```

**예시 2: 최소 초기화로 빠른 배포**
```bash
export GITHUB_TOKEN=<YOUR_GITHUB_PAT>
export REMOTE_SSH_PUBLIC_KEY=$(cat ~/.ssh/vscode-remote-ssh.pub)

./deploy.sh \
  --deploy-init-minimal True \
  --deploy-project-resource False
```

**예시 3: 환경변수로 간단하게**
```bash
export GITHUB_TOKEN=<YOUR_GITHUB_PAT>
export REMOTE_SSH_PUBLIC_KEY=$(cat ~/.ssh/vscode-remote-ssh.pub)
export INSTANCE_TYPE=t3.xlarge
export PROJECT_NAME=test-project

curl -sL https://raw.githubusercontent.com/shkim4u/vscode-server/main/deploy-simple.sh | bash
```

### 방법 2: 수동 배포 (S3 버킷 지정)

```bash
# 환경 변수 설정
export GITHUB_TOKEN=<YOUR_GITHUB_PAT>
export REMOTE_SSH_PUBLIC_KEY=$(cat ~/.ssh/vscode-remote-ssh.pub)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

# S3 버킷 생성 (한 번만 필요)
S3_BUCKET_NAME="vscode-server-template-${ACCOUNT_ID}-${REGION}"
aws s3api create-bucket \
    --bucket "${S3_BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"

# 배포
curl -sL https://raw.githubusercontent.com/shkim4u/vscode-server/main/cloudformation/vscode-server-stack.yaml -o /tmp/vscode-server-stack.yaml && \
aws cloudformation deploy \
    --stack-name VSCodeServerStack \
    --template-file /tmp/vscode-server-stack.yaml \
    --s3-bucket "${S3_BUCKET_NAME}" \
    --parameter-overrides \
      InstanceType=m5.2xlarge \
      VSCodeServerVersion=4.108.1 \
      GitHubAccessToken="${GITHUB_TOKEN}" \
      RemoteSSHPublicKey="${REMOTE_SSH_PUBLIC_KEY}" \
      ProjectName="ax-on-mastery" \
      DeployProjectResource="True" \
      DeployInitMinimal="True" \
      AWSAccessKeyId="${AWS_ACCESS_KEY_ID}" \
      AWSSecretAccessKey="${AWS_SECRET_ACCESS_KEY}" \
      AWSBearerTokenBedrock="${AWS_BEARER_TOKEN_BEDROCK}" \
    --capabilities CAPABILITY_IAM \
    --region "${REGION}"
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

## 자동 시작/중지 및 Override 기능

VSCode Server는 비용 절감을 위해 자동으로 시작 및 중지됩니다:
- **시작 시간**: 매일 08:00 KST (전날 23:00 UTC)
- **중지 시간**: 매일 20:00 KST (11:00 UTC)

### 작업 중 자동 중지 방지하기

작업이 늦게까지 진행되어 20:00 KST 자동 중지를 건너뛰려면 `AutoStop` 태그를 `disabled`로 설정하세요.

```bash
# 인스턴스 ID 확인
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name VSCodeServerStack \
    --query 'Stacks[0].Outputs[?OutputKey==`VSCodeServerInstanceId`].OutputValue' \
    --output text \
    --region ap-northeast-2)

# 자동 중지 비활성화
aws ec2 create-tags \
    --resources "${INSTANCE_ID}" \
    --tags Key=AutoStop,Value=disabled \
    --region ap-northeast-2
```

**중요**: `AutoStop=disabled` 상태는 다음날 아침 08:00 KST에 자동으로 `enabled`로 복원됩니다. 따라서:
1. 늦게까지 작업할 때만 `disabled`로 설정
2. 다음날 아침에 자동으로 초기화됨
3. 수동으로 다시 `enabled`로 변경할 필요 없음

### 수동으로 AutoStop 재활성화

필요시 수동으로 다시 활성화할 수 있습니다:

```bash
aws ec2 create-tags \
    --resources "${INSTANCE_ID}" \
    --tags Key=AutoStop,Value=enabled \
    --region ap-northeast-2
```

## 스택 출력 정보 확인

배포 후 다음 명령으로 중요한 정보를 확인할 수 있습니다:

```bash
aws cloudformation describe-stacks \
    --stack-name VSCodeServerStack \
    --region ap-northeast-2 \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table
```

출력 항목:
- `VSCodeServerCloudFrontDomainName`: CloudFront URL (브라우저 접속용)
- `VSCodeServerPublicIP`: EC2 Public IP (SSH 접속용)
- `VSCodeServerInstanceId`: EC2 인스턴스 ID
- `VSCodeServerPasswordSSM`: code-server 비밀번호 SSM 파라미터 경로
- `AutoStopOverrideInstructions`: 자동 중지 Override 방법

## 참고사항

- SSH 공개키는 반드시 따옴표로 감싸서 전달해야 합니다 (RemoteSSHPublicKey="$REMOTE_SSH_PUBLIC_KEY")
- 생성된 개인키(~/.ssh/vscode-remote-ssh)는 안전하게 보관하고 공유하지 마세요
- 공개키는 ssh-ed25519 AAAA... 또는 ssh-rsa AAAA...로 시작하는 한 줄의 문자열입니다
- S3 버킷은 계정당 한 번만 생성하면 계속 재사용할 수 있습니다
- 템플릿이 51,200 바이트를 초과하므로 반드시 `--s3-bucket` 파라미터가 필요합니다
