#!/bin/bash
# Simple one-liner deployment script for AWS CloudShell

# Default values
PROJECT_NAME=${PROJECT_NAME:-ax-on-mastery}

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-ap-northeast-2}
S3_BUCKET_NAME="vscode-server-template-${ACCOUNT_ID}-${REGION}"

# Create bucket if it doesn't exist
aws s3 ls "s3://${S3_BUCKET_NAME}" 2>/dev/null || \
  (echo "Creating S3 bucket..." && \
   if [ "${REGION}" = "us-east-1" ]; then \
     aws s3api create-bucket --bucket "${S3_BUCKET_NAME}" --region "${REGION}"; \
   else \
     aws s3api create-bucket --bucket "${S3_BUCKET_NAME}" --region "${REGION}" --create-bucket-configuration LocationConstraint="${REGION}"; \
   fi)

# Download and deploy
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
      ProjectName="${PROJECT_NAME}" \
      DeployProjectResource="True" \
      DeployInitMinimal="True" \
      AWSAccessKeyId="${AWS_ACCESS_KEY_ID}" \
      AWSSecretAccessKey="${AWS_SECRET_ACCESS_KEY}" \
      AWSBearerTokenBedrock="${AWS_BEARER_TOKEN_BEDROCK}" \
    --capabilities CAPABILITY_IAM \
    --region "${REGION}"
