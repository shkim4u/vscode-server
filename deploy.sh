#!/bin/bash

# VSCode Server Stack Deployment Script
# This script deploys the VSCode Server CloudFormation stack with S3 bucket support

set -e

# Default values
PROJECT_NAME="ax-on-mastery"
INSTANCE_TYPE="m5.2xlarge"
VSCODE_SERVER_VERSION="4.109.2"
DEPLOY_PROJECT_RESOURCE="True"
DEPLOY_INIT_MINIMAL="False"
STACK_NAME="VSCodeServerStack"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --instance-type)
      INSTANCE_TYPE="$2"
      shift 2
      ;;
    --vscode-server-version)
      VSCODE_SERVER_VERSION="$2"
      shift 2
      ;;
    --deploy-project-resource)
      DEPLOY_PROJECT_RESOURCE="$2"
      shift 2
      ;;
    --deploy-init-minimal)
      DEPLOY_INIT_MINIMAL="$2"
      shift 2
      ;;
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --project-name NAME              Project name (default: ax-on-mastery)"
      echo "  --instance-type TYPE             EC2 instance type (default: m5.2xlarge)"
      echo "  --vscode-server-version VERSION  VSCode Server version (default: 4.109.2)"
      echo "  --deploy-project-resource BOOL   Deploy project resources (default: True)"
      echo "  --deploy-init-minimal BOOL       Deploy minimal initialization (default: False)"
      echo "  --stack-name NAME                CloudFormation stack name (default: VSCodeServerStack)"
      echo "  --help, -h                       Show this help message"
      echo ""
      echo "Environment variables required:"
      echo "  GITHUB_TOKEN           GitHub Personal Access Token"
      echo "  REMOTE_SSH_PUBLIC_KEY  SSH public key for Remote SSH"
      echo "  AWS_ACCESS_KEY_ID      (optional) AWS Access Key ID"
      echo "  AWS_SECRET_ACCESS_KEY  (optional) AWS Secret Access Key"
      echo "  AWS_BEARER_TOKEN_BEDROCK  (optional) AWS Bearer Token for Bedrock"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Get AWS Account ID and Region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-ap-northeast-2}

# S3 Bucket name for CloudFormation templates
S3_BUCKET_NAME="vscode-server-template-${ACCOUNT_ID}-${REGION}"

echo "=========================================="
echo "VSCode Server Stack Deployment"
echo "=========================================="
echo "Account ID: ${ACCOUNT_ID}"
echo "Region: ${REGION}"
echo "Stack Name: ${STACK_NAME}"
echo "Project Name: ${PROJECT_NAME}"
echo "Instance Type: ${INSTANCE_TYPE}"
echo "VSCode Server Version: ${VSCODE_SERVER_VERSION}"
echo "Deploy Project Resource: ${DEPLOY_PROJECT_RESOURCE}"
echo "Deploy Init Minimal: ${DEPLOY_INIT_MINIMAL}"
echo "S3 Bucket: ${S3_BUCKET_NAME}"
echo "=========================================="

# Check if S3 bucket exists, create if not
if aws s3 ls "s3://${S3_BUCKET_NAME}" 2>/dev/null; then
    echo "S3 bucket ${S3_BUCKET_NAME} already exists"
else
    echo "Creating S3 bucket ${S3_BUCKET_NAME}..."
    if [ "${REGION}" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "${S3_BUCKET_NAME}" --region "${REGION}"
    else
        aws s3api create-bucket \
            --bucket "${S3_BUCKET_NAME}" \
            --region "${REGION}" \
            --create-bucket-configuration LocationConstraint="${REGION}"
    fi

    # Enable versioning for better template management
    echo "Enabling versioning on S3 bucket..."
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled

    # Enable encryption
    echo "Enabling encryption on S3 bucket..."
    aws s3api put-bucket-encryption \
        --bucket "${S3_BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'

    echo "S3 bucket ${S3_BUCKET_NAME} created successfully"
fi

echo "=========================================="
echo "Downloading CloudFormation template..."
echo "=========================================="

# Download template (force overwrite with -o flag)
curl -fsSL https://raw.githubusercontent.com/shkim4u/vscode-server/main/cloudformation/vscode-server-stack.yaml \
    -o /tmp/vscode-server-stack.yaml

echo "Template downloaded successfully"
echo "Template size: $(stat -f%z /tmp/vscode-server-stack.yaml 2>/dev/null || stat -c%s /tmp/vscode-server-stack.yaml) bytes"

echo "=========================================="
echo "Deploying CloudFormation stack..."
echo "=========================================="

# Deploy stack
aws cloudformation deploy \
    --stack-name "${STACK_NAME}" \
    --template-file /tmp/vscode-server-stack.yaml \
    --s3-bucket "${S3_BUCKET_NAME}" \
    --s3-prefix cloudformation-templates \
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
      OpenAIAPIKey="${OPENAI_API_KEY}" \
    --capabilities CAPABILITY_IAM \
    --region "${REGION}"

# Check deployment result
DEPLOY_EXIT_CODE=$?
if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
    echo "=========================================="
    echo "✗ Deployment failed!"
    echo "=========================================="
    echo "CloudFormation deployment returned error code: $DEPLOY_EXIT_CODE"
    echo "Please check the CloudFormation console for detailed error information."
    exit 1
fi

echo "=========================================="
echo "✓ Deployment completed successfully!"
echo "=========================================="

# Get stack outputs
echo "Stack Outputs:"
aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

echo ""
echo "🔎 Retrieving VSCode Server Instance ID..."
# VSCode Server Instance ID 조회
VSCODE_SERVER_INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='VSCodeServerInstanceId'].OutputValue" \
  --region "${REGION}" \
  --output text)
echo "🏷️ VSCode Server Instance ID: "
echo "$VSCODE_SERVER_INSTANCE_ID"

echo ""
echo "🔎 Retrieving VSCode Server CloudFront Domain Name..."
# VSCodeServerCloudFrontDomainName 값 조회
VSCODE_SERVER_CLOUDFRONT_DOMAIN_NAME=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='VSCodeServerCloudFrontDomainName'].OutputValue" \
  --region "${REGION}" \
  --output text)

echo "🏡 VSCode Server CloudFront Domain Name: "
echo "$VSCODE_SERVER_CLOUDFRONT_DOMAIN_NAME"

# PASSWORD_SSM 값 조회
PASSWORD_SSM=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='VSCodeServerPasswordSSM'].OutputValue" \
  --region "${REGION}" \
  --output text)

echo ""
echo "🔎 Retrieving password from Parameter Store: $PASSWORD_SSM"
PASSWORD=$(aws ssm get-parameter \
  --name "$PASSWORD_SSM" \
  --with-decryption \
  --query "Parameter.Value" \
  --region "${REGION}" \
  --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$PASSWORD" ]; then
  echo "🚨 (주의) 아래 실습 환경 접속을 위한 액세스 코드는 유출되지 않도록 각별히 유의해 주시기 바랍니다!"
  echo "🔑 VSCode Server Access Code: $PASSWORD"
else
  echo "Error: Failed to retrieve password from Parameter Store"
  echo "Parameter name: $PASSWORD_SSM"
fi
