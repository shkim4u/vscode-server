#!/bin/bash
# Simple one-liner deployment script for AWS CloudShell

# Default values
PROJECT_NAME=${PROJECT_NAME:-ax-on-mastery}
INSTANCE_TYPE=${INSTANCE_TYPE:-m5.2xlarge}
VSCODE_SERVER_VERSION=${VSCODE_SERVER_VERSION:-4.109.2}
DEPLOY_PROJECT_RESOURCE=${DEPLOY_PROJECT_RESOURCE:-True}
DEPLOY_INIT_MINIMAL=${DEPLOY_INIT_MINIMAL:-False}

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
      InstanceType="${INSTANCE_TYPE}" \
      VSCodeServerVersion="${VSCODE_SERVER_VERSION}" \
      GitHubAccessToken="${GITHUB_TOKEN}" \
      RemoteSSHPublicKey="${REMOTE_SSH_PUBLIC_KEY}" \
      ProjectName="${PROJECT_NAME}" \
      DeployProjectResource="${DEPLOY_PROJECT_RESOURCE}" \
      DeployInitMinimal="${DEPLOY_INIT_MINIMAL}" \
      AWSAccessKeyId="${AWS_ACCESS_KEY_ID}" \
      AWSSecretAccessKey="${AWS_SECRET_ACCESS_KEY}" \
      AWSBearerTokenBedrock="${AWS_BEARER_TOKEN_BEDROCK}" \
    --capabilities CAPABILITY_IAM \
    --region "${REGION}"
