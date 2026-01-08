#!/bin/bash

###
## CloudFormation Stack Output 값을 조회하는 스크립트
## 사용법: ./get-stack-output.sh <stack-name> <output-key>
## 예제: ./get-stack-output.sh my-vscode-stack VSCodeServerPasswordSSM
###

# 파라미터 검증
if [ $# -ne 2 ]; then
  echo "Error: Invalid number of arguments"
  echo "Usage: $0 <stack-name> <output-key>"
  echo ""
  echo "Examples:"
  echo "  # Direct execution:"
  echo "  $0 VSCodeServerStack VSCodeServerCloudFrontDomainName"
  echo "  $0 VSCodeServerStack VSCodeServerPasswordSSM"
  echo ""
  echo "  # Remote execution with curl:"
  echo "  curl -fsSL https://raw.githubusercontent.com/shkim4u/ax-on-mastery/main/cloudformation/get-stack-output.sh | bash -s VSCodeServerStack VSCodeServerPasswordSSM"
  exit 1
fi

STACK_NAME=$1
OUTPUT_KEY=$2

# AWS CLI 설치 여부 확인
if ! command -v aws &> /dev/null; then
  echo "Error: AWS CLI is not installed"
  exit 1
fi

# Stack 존재 여부 확인
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
  echo "Error: Stack '$STACK_NAME' does not exist or you don't have permission to access it"
  exit 1
fi

# Output 값 조회
OUTPUT_VALUE=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='$OUTPUT_KEY'].OutputValue" \
  --output text)

# Output 값이 없는 경우
if [ -z "$OUTPUT_VALUE" ]; then
  echo "Error: Output key '$OUTPUT_KEY' not found in stack '$STACK_NAME'"
  echo ""
  echo "Available output keys:"
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[*].OutputKey" \
    --output text
  exit 1
fi

# VSCodeServerPasswordSSM인 경우 Parameter Store에서 실제 비밀번호 조회
if [ "$OUTPUT_KEY" = "VSCodeServerPasswordSSM" ]; then
  echo "Retrieving password from Parameter Store: $OUTPUT_VALUE"
  PASSWORD=$(aws ssm get-parameter \
    --name "$OUTPUT_VALUE" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$PASSWORD" ]; then
    echo ""
    echo "🚨 (주의) 아래 실습 환경 접속을 위한 액세스 코드는 유출되지 않도록 각별히 유의해 주시기 바랍니다!"
    echo "VSCode Server Access Code: $PASSWORD"
  else
    echo "Error: Failed to retrieve password from Parameter Store"
    echo "Parameter name: $OUTPUT_VALUE"
    exit 1
  fi
else
  # 일반 Output 값 출력
  echo "$OUTPUT_VALUE"
fi
