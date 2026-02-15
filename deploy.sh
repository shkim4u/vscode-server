#!/bin/bash

# VSCode Server Stack Deployment Script
# This script deploys the VSCode Server CloudFormation stack with S3 bucket support

set -e

# Default values
PROJECT_NAME="ax-on-mastery"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --project-name NAME    Project name (default: ax-on-mastery)"
      echo "  --help, -h             Show this help message"
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
echo "Project Name: ${PROJECT_NAME}"
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

# Download template
curl -sL https://raw.githubusercontent.com/shkim4u/vscode-server/main/cloudformation/vscode-server-stack.yaml \
    -o /tmp/vscode-server-stack.yaml

echo "Template downloaded successfully"
echo "Template size: $(stat -f%z /tmp/vscode-server-stack.yaml 2>/dev/null || stat -c%s /tmp/vscode-server-stack.yaml) bytes"

echo "=========================================="
echo "Deploying CloudFormation stack..."
echo "=========================================="

# Deploy stack
aws cloudformation deploy \
    --stack-name VSCodeServerStack \
    --template-file /tmp/vscode-server-stack.yaml \
    --s3-bucket "${S3_BUCKET_NAME}" \
    --s3-prefix cloudformation-templates \
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

echo "=========================================="
echo "Deployment completed successfully!"
echo "=========================================="

# Get stack outputs
echo "Stack Outputs:"
aws cloudformation describe-stacks \
    --stack-name VSCodeServerStack \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table
