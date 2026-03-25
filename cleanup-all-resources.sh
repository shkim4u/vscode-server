#!/bin/bash

# Comprehensive Cleanup Script for AX on Mastery
# This script deletes CloudFormation stacks and AgentCore Runtimes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_STACKS="AxOnMasteryStack,VSCodeServerStack"
DEFAULT_STACK_REGION="ap-northeast-2"
DEFAULT_AGENTCORE_REGION="us-west-2"
DEFAULT_NO_WAIT_STACK_DELETION=true

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --stacks STACKS              Comma-separated list of CloudFormation stacks to delete"
    echo "                               (default: $DEFAULT_STACKS)"
    echo "  --stack-region REGION        AWS region for CloudFormation stacks"
    echo "                               (default: $DEFAULT_STACK_REGION)"
    echo "  --agentcore-region REGION    AWS region for AgentCore Runtimes"
    echo "                               (default: $DEFAULT_AGENTCORE_REGION)"
    echo "  --no-wait-stack-deletion     Do not wait for stack deletion to complete"
    echo "                               (default: true)"
    echo "  -y, --yes                    Skip confirmation prompts (for automation)"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                       # Interactive mode with defaults"
    echo "  $0 --yes                                 # Non-interactive mode with defaults"
    echo "  $0 --stacks MyStack --stack-region us-west-2"
    echo "  $0 --yes --stacks Stack1,Stack2 --agentcore-region us-east-1"
    echo "  $0 --yes --no-wait-stack-deletion        # Fast mode: don't wait for stack deletion"
    exit 0
}

# Parse command line arguments
SKIP_PROMPT=false
STACKS=""
STACK_REGION=""
AGENTCORE_REGION=""
NO_WAIT_STACK_DELETION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -y|--yes)
            SKIP_PROMPT=true
            shift
            ;;
        --stacks)
            STACKS="$2"
            shift 2
            ;;
        --stack-region)
            STACK_REGION="$2"
            shift 2
            ;;
        --agentcore-region)
            AGENTCORE_REGION="$2"
            shift 2
            ;;
        --no-wait-stack-deletion)
            NO_WAIT_STACK_DELETION=true
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            echo ""
            usage
            ;;
    esac
done

STACKS="${STACKS:-$DEFAULT_STACKS}"
STACK_REGION="${STACK_REGION:-$DEFAULT_STACK_REGION}"
AGENTCORE_REGION="${AGENTCORE_REGION:-$DEFAULT_AGENTCORE_REGION}"
NO_WAIT_STACK_DELETION="${NO_WAIT_STACK_DELETION:-$DEFAULT_NO_WAIT_STACK_DELETION}"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Resource Cleanup Script${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "CloudFormation Stacks:     $STACKS"
echo "Stack Region:              $STACK_REGION"
echo "AgentCore Region:          $AGENTCORE_REGION"
echo "No Wait Stack Deletion:    $NO_WAIT_STACK_DELETION"
echo ""

# Check AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Check AWS credentials for stack region
echo "Checking AWS credentials for stack region..."
if ! aws sts get-caller-identity --region "$STACK_REGION" &> /dev/null; then
    echo -e "${RED}Error: AWS credentials are not configured or invalid for region $STACK_REGION${NC}"
    echo "Please configure AWS credentials using 'aws configure' or set environment variables."
    exit 1
fi
echo -e "${GREEN}AWS credentials OK for $STACK_REGION${NC}"
echo ""

# Check AWS credentials for AgentCore region
echo "Checking AWS credentials for AgentCore region..."
if ! aws sts get-caller-identity --region "$AGENTCORE_REGION" &> /dev/null; then
    echo -e "${RED}Error: AWS credentials are not configured or invalid for region $AGENTCORE_REGION${NC}"
    exit 1
fi
echo -e "${GREEN}AWS credentials OK for $AGENTCORE_REGION${NC}"
echo ""

# Display current AWS identity
CALLER_IDENTITY=$(aws sts get-caller-identity --region "$STACK_REGION" --output json)
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
USER_ARN=$(echo "$CALLER_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)

echo -e "${YELLOW}Current AWS Identity:${NC}"
echo "  Account: $ACCOUNT_ID"
echo "  ARN:     $USER_ARN"
echo ""

# Confirmation prompt
if [ "$SKIP_PROMPT" = false ]; then
    echo -e "${RED}WARNING: This script will:${NC}"
    echo -e "${RED}  1. Delete CloudFormation stacks: $STACKS${NC}"
    echo -e "${RED}  2. Delete all AgentCore Runtimes in $AGENTCORE_REGION${NC}"
    echo -e "${RED}  3. Delete IAM User 'APIuser' (if exists)${NC}"
    echo -e "${RED}  4. Delete S3 Bucket 'vscode-server-template-*' (if exists)${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    read -p "$(echo -e ${RED}Are you sure you want to proceed? [y/N]: ${NC})" -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Aborted by user.${NC}"
        exit 0
    fi
    echo ""
fi

#############################################
# Part 1: CloudFormation Stack Deletion
#############################################

echo -e "${YELLOW}=== Part 1: CloudFormation Stack Deletion ===${NC}"
echo ""

# Convert comma-separated stacks to array
IFS=',' read -ra STACK_ARRAY <<< "$STACKS"

STACK_SUCCESS_COUNT=0
STACK_FAILED_COUNT=0
FAILED_STACKS=()

for STACK_NAME in "${STACK_ARRAY[@]}"; do
    # Trim whitespace
    STACK_NAME=$(echo "$STACK_NAME" | xargs)

    if [ -z "$STACK_NAME" ]; then
        continue
    fi

    echo -e "${YELLOW}Checking if stack exists: $STACK_NAME${NC}"

    # Check if stack exists
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$STACK_REGION" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")

    if [ "$STACK_STATUS" = "NOT_FOUND" ]; then
        echo -e "${YELLOW}Stack $STACK_NAME does not exist. Skipping.${NC}"
        echo ""
        continue
    fi

    echo -e "${YELLOW}Stack Status: $STACK_STATUS${NC}"
    echo -e "${YELLOW}Deleting CloudFormation stack: $STACK_NAME${NC}"

    # Delete stack
    DELETE_RESULT=$(aws cloudformation delete-stack \
        --stack-name "$STACK_NAME" \
        --region "$STACK_REGION" \
        2>&1)

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Stack deletion initiated: $STACK_NAME${NC}"

        if [ "$NO_WAIT_STACK_DELETION" = true ]; then
            echo -e "${YELLOW}Skipping wait for stack deletion (--no-wait-stack-deletion enabled)${NC}"
            STACK_SUCCESS_COUNT=$((STACK_SUCCESS_COUNT + 1))
        else
            echo -e "${YELLOW}Waiting for stack deletion to complete...${NC}"

            # Wait for stack deletion
            if aws cloudformation wait stack-delete-complete \
                --stack-name "$STACK_NAME" \
                --region "$STACK_REGION" 2>&1; then
                echo -e "${GREEN}✓ Successfully deleted stack: $STACK_NAME${NC}"
                STACK_SUCCESS_COUNT=$((STACK_SUCCESS_COUNT + 1))
            else
                echo -e "${RED}✗ Failed to delete stack: $STACK_NAME (wait timed out or failed)${NC}"
                STACK_FAILED_COUNT=$((STACK_FAILED_COUNT + 1))
                FAILED_STACKS+=("$STACK_NAME")
            fi
        fi
    else
        echo -e "${RED}✗ Failed to initiate stack deletion: $STACK_NAME${NC}"
        echo "  Error: $DELETE_RESULT"
        STACK_FAILED_COUNT=$((STACK_FAILED_COUNT + 1))
        FAILED_STACKS+=("$STACK_NAME")
    fi

    echo ""
done

# Stack deletion summary
echo -e "${YELLOW}=== CloudFormation Stack Deletion Summary ===${NC}"
echo -e "${GREEN}Successfully deleted: $STACK_SUCCESS_COUNT stack(s)${NC}"

if [ $STACK_FAILED_COUNT -gt 0 ]; then
    echo -e "${RED}Failed to delete: $STACK_FAILED_COUNT stack(s)${NC}"
    echo ""
    echo -e "${RED}Failed stacks:${NC}"
    for failed_stack in "${FAILED_STACKS[@]}"; do
        echo -e "  ${RED}- $failed_stack${NC}"
    done
fi
echo ""

#############################################
# Part 2: AgentCore Runtime Cleanup
#############################################

echo -e "${YELLOW}=== Part 2: AgentCore Runtime Cleanup ===${NC}"
echo ""

# List all AgentCore Runtimes
echo "Querying AgentCore Runtime API in $AGENTCORE_REGION..."
AGENTS_JSON=$(aws bedrock-agentcore-control list-agent-runtimes \
    --region "$AGENTCORE_REGION" \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to list AgentCore Runtimes${NC}"
    echo "Error details: $AGENTS_JSON"
    echo ""
    echo "Possible causes:"
    echo "  1. Insufficient permissions to list agent runtimes"
    echo "  2. AgentCore service not available in region"

    # Continue to final summary even if AgentCore query fails
    AGENT_SUCCESS_COUNT=0
    AGENT_FAILED_COUNT=0
else
    # Parse agent count
    AGENT_COUNT=$(echo "$AGENTS_JSON" | jq -r '.agentRuntimes | length')

    if [ "$AGENT_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No AgentCore Runtimes found. Nothing to delete.${NC}"
        AGENT_SUCCESS_COUNT=0
        AGENT_FAILED_COUNT=0
    else
        echo -e "${YELLOW}Found $AGENT_COUNT AgentCore Runtime(s) to delete:${NC}"
        echo ""

        # Display agents
        echo "$AGENTS_JSON" | jq -r '.agentRuntimes[] | "  - Runtime ID: \(.agentRuntimeId), Name: \(.agentRuntimeName // "N/A"), Status: \(.status)"'
        echo ""

        # Additional confirmation for AgentCore (if not skipped globally)
        if [ "$SKIP_PROMPT" = false ]; then
            read -p "$(echo -e ${RED}Proceed with deleting ALL AgentCore Runtimes? [y/N]: ${NC})" -n 1 -r
            echo ""

            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}AgentCore cleanup skipped by user.${NC}"
                AGENT_SUCCESS_COUNT=0
                AGENT_FAILED_COUNT=0
            else
                echo ""
                echo -e "${YELLOW}Starting AgentCore cleanup process...${NC}"
                echo ""

                # Track results
                AGENT_SUCCESS_COUNT=0
                AGENT_FAILED_COUNT=0
                FAILED_AGENTS=()

                # Process each agent
                while read -r agent; do
                    RUNTIME_ID=$(echo "$agent" | jq -r '.agentRuntimeId')
                    RUNTIME_NAME=$(echo "$agent" | jq -r '.agentRuntimeName // "N/A"')

                    echo -e "${YELLOW}Deleting AgentCore Runtime: $RUNTIME_NAME (ID: $RUNTIME_ID)${NC}"

                    # Delete AgentCore Runtime
                    DELETE_RESULT=$(aws bedrock-agentcore-control delete-agent-runtime \
                        --agent-runtime-id "$RUNTIME_ID" \
                        --region "$AGENTCORE_REGION" \
                        2>&1)

                    # Check if deletion was successful
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ Successfully deleted AgentCore Runtime: $RUNTIME_NAME${NC}"
                        AGENT_SUCCESS_COUNT=$((AGENT_SUCCESS_COUNT + 1))
                    else
                        echo -e "${RED}✗ Failed to delete AgentCore Runtime: $RUNTIME_NAME${NC}"
                        echo "  Error: $DELETE_RESULT"
                        AGENT_FAILED_COUNT=$((AGENT_FAILED_COUNT + 1))
                        FAILED_AGENTS+=("$RUNTIME_NAME ($RUNTIME_ID)")
                    fi

                    echo ""
                done < <(echo "$AGENTS_JSON" | jq -c '.agentRuntimes[]')
            fi
        else
            echo -e "${YELLOW}Starting AgentCore cleanup process...${NC}"
            echo ""

            # Track results
            AGENT_SUCCESS_COUNT=0
            AGENT_FAILED_COUNT=0
            FAILED_AGENTS=()

            # Process each agent
            while read -r agent; do
                RUNTIME_ID=$(echo "$agent" | jq -r '.agentRuntimeId')
                RUNTIME_NAME=$(echo "$agent" | jq -r '.agentRuntimeName // "N/A"')

                echo -e "${YELLOW}Deleting AgentCore Runtime: $RUNTIME_NAME (ID: $RUNTIME_ID)${NC}"

                # Delete AgentCore Runtime
                DELETE_RESULT=$(aws bedrock-agentcore-control delete-agent-runtime \
                    --agent-runtime-id "$RUNTIME_ID" \
                    --region "$AGENTCORE_REGION" \
                    2>&1)

                # Check if deletion was successful
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Successfully deleted AgentCore Runtime: $RUNTIME_NAME${NC}"
                    AGENT_SUCCESS_COUNT=$((AGENT_SUCCESS_COUNT + 1))
                else
                    echo -e "${RED}✗ Failed to delete AgentCore Runtime: $RUNTIME_NAME${NC}"
                    echo "  Error: $DELETE_RESULT"
                    AGENT_FAILED_COUNT=$((AGENT_FAILED_COUNT + 1))
                    FAILED_AGENTS+=("$RUNTIME_NAME ($RUNTIME_ID)")
                fi

                echo ""
            done < <(echo "$AGENTS_JSON" | jq -c '.agentRuntimes[]')
        fi

        # AgentCore cleanup summary
        echo -e "${YELLOW}=== AgentCore Runtime Cleanup Summary ===${NC}"
        echo -e "${GREEN}Successfully deleted: $AGENT_SUCCESS_COUNT AgentCore Runtime(s)${NC}"

        if [ $AGENT_FAILED_COUNT -gt 0 ]; then
            echo -e "${RED}Failed to delete: $AGENT_FAILED_COUNT AgentCore Runtime(s)${NC}"
            echo ""
            echo -e "${RED}Failed runtimes:${NC}"
            for failed_agent in "${FAILED_AGENTS[@]}"; do
                echo -e "  ${RED}- $failed_agent${NC}"
            done
        fi
    fi
fi

echo ""

#############################################
# Part 3: IAM User (APIuser) Cleanup
#############################################

echo -e "${YELLOW}=== Part 3: IAM User (APIuser) Cleanup ===${NC}"
echo ""

IAM_USER_DELETED=false

if aws iam get-user --user-name APIuser &>/dev/null; then
    echo -e "${YELLOW}Found IAM User 'APIuser'${NC}"

    PROCEED_IAM=true
    if [ "$SKIP_PROMPT" = false ]; then
        read -p "$(echo -e ${RED}Do you want to delete the IAM User 'APIuser'? [y/N]: ${NC})" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}IAM User cleanup skipped by user.${NC}"
            PROCEED_IAM=false
        fi
    fi

    if [ "$PROCEED_IAM" = true ]; then
        echo -e "${YELLOW}Deleting IAM User 'APIuser'...${NC}"

        # Delete access keys
        echo "  Deleting access keys..."
        ACCESS_KEYS=$(aws iam list-access-keys --user-name APIuser --query 'AccessKeyMetadata[].AccessKeyId' --output text)
        if [ -n "$ACCESS_KEYS" ]; then
            for key in $ACCESS_KEYS; do
                aws iam delete-access-key --user-name APIuser --access-key-id "$key"
                echo -e "${GREEN}  ✓ Access key deleted: $key${NC}"
            done
        else
            echo "  No access keys to delete"
        fi

        # Delete service-specific credentials
        echo "  Deleting service-specific credentials..."
        SERVICE_CREDS=$(aws iam list-service-specific-credentials --user-name APIuser --query 'ServiceSpecificCredentials[].ServiceSpecificCredentialId' --output text 2>/dev/null || echo "")
        if [ -n "$SERVICE_CREDS" ]; then
            for cred in $SERVICE_CREDS; do
                aws iam delete-service-specific-credential --user-name APIuser --service-specific-credential-id "$cred"
                echo -e "${GREEN}  ✓ Service-specific credential deleted: $cred${NC}"
            done
        else
            echo "  No service-specific credentials to delete"
        fi

        # Detach policies
        echo "  Detaching policies..."
        POLICIES=$(aws iam list-attached-user-policies --user-name APIuser --query 'AttachedPolicies[].PolicyArn' --output text)
        if [ -n "$POLICIES" ]; then
            for policy in $POLICIES; do
                aws iam detach-user-policy --user-name APIuser --policy-arn "$policy"
                echo -e "${GREEN}  ✓ Policy detached: $policy${NC}"
            done
        else
            echo "  No policies to detach"
        fi

        # Delete user
        echo "  Deleting user..."
        if aws iam delete-user --user-name APIuser; then
            echo -e "${GREEN}✓ IAM User 'APIuser' deleted successfully${NC}"
            IAM_USER_DELETED=true
        else
            echo -e "${RED}✗ Failed to delete IAM User 'APIuser'${NC}"
        fi
    fi
else
    echo -e "${YELLOW}IAM User 'APIuser' does not exist. Skipping.${NC}"
fi

echo ""

#############################################
# Part 4: S3 Bucket Cleanup
#############################################

echo -e "${YELLOW}=== Part 4: S3 Bucket Cleanup ===${NC}"
echo ""

S3_BUCKET_DELETED=false
S3_BUCKET_NAME="vscode-server-template-${ACCOUNT_ID}-${STACK_REGION}"

if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
    echo -e "${YELLOW}Found S3 Bucket: $S3_BUCKET_NAME${NC}"

    PROCEED_S3=true
    if [ "$SKIP_PROMPT" = false ]; then
        read -p "$(echo -e ${RED}Do you want to delete the S3 Bucket \'$S3_BUCKET_NAME\'? [y/N]: ${NC})" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}S3 Bucket cleanup skipped by user.${NC}"
            PROCEED_S3=false
        fi
    fi

    if [ "$PROCEED_S3" = true ]; then
        echo -e "${YELLOW}Emptying S3 Bucket: $S3_BUCKET_NAME...${NC}"

        # Delete all objects (including versioned objects)
        if aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>&1; then
            echo -e "${GREEN}  ✓ All objects deleted${NC}"
        else
            echo -e "${RED}  ✗ Failed to delete objects${NC}"
        fi

        # Delete all object versions and delete markers (for versioned buckets)
        VERSIONS=$(aws s3api list-object-versions --bucket "$S3_BUCKET_NAME" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)
        if [ -n "$VERSIONS" ] && [ "$VERSIONS" != '{"Objects": null}' ] && [ "$VERSIONS" != "null" ]; then
            aws s3api delete-objects --bucket "$S3_BUCKET_NAME" --delete "$VERSIONS" > /dev/null 2>&1
            echo -e "${GREEN}  ✓ Object versions deleted${NC}"
        fi

        DELETE_MARKERS=$(aws s3api list-object-versions --bucket "$S3_BUCKET_NAME" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)
        if [ -n "$DELETE_MARKERS" ] && [ "$DELETE_MARKERS" != '{"Objects": null}' ] && [ "$DELETE_MARKERS" != "null" ]; then
            aws s3api delete-objects --bucket "$S3_BUCKET_NAME" --delete "$DELETE_MARKERS" > /dev/null 2>&1
            echo -e "${GREEN}  ✓ Delete markers removed${NC}"
        fi

        # Delete the bucket
        echo "  Deleting bucket..."
        if aws s3api delete-bucket --bucket "$S3_BUCKET_NAME" --region "$STACK_REGION" 2>&1; then
            echo -e "${GREEN}✓ S3 Bucket '$S3_BUCKET_NAME' deleted successfully${NC}"
            S3_BUCKET_DELETED=true
        else
            echo -e "${RED}✗ Failed to delete S3 Bucket '$S3_BUCKET_NAME'${NC}"
        fi
    fi
else
    echo -e "${YELLOW}S3 Bucket '$S3_BUCKET_NAME' does not exist. Skipping.${NC}"
fi

echo ""

#############################################
# Final Summary
#############################################

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Final Cleanup Summary${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${GREEN}CloudFormation Stacks Deleted: $STACK_SUCCESS_COUNT${NC}"
echo -e "${GREEN}AgentCore Runtimes Deleted:    $AGENT_SUCCESS_COUNT${NC}"
echo -e "${GREEN}IAM User 'APIuser' Deleted:    $IAM_USER_DELETED${NC}"
echo -e "${GREEN}S3 Bucket Deleted:             $S3_BUCKET_DELETED${NC}"
echo ""

set -euo pipefail

delete_log_groups_by_prefix() {
    local region="$1"
    local prefix="$2"

    echo "  Deleting log groups matching: ${prefix}* (region: ${region})"
    local log_groups
    log_groups=$(aws logs describe-log-groups \
        --region "$region" \
        --log-group-name-prefix "$prefix" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null) || true

    if [ -z "$log_groups" ]; then
        echo "    No log groups found."
        return
    fi

    for lg in $log_groups; do
        echo "    Deleting: $lg"
        aws logs delete-log-group \
            --region "$region" \
            --log-group-name "$lg" 2>/dev/null || echo "    WARN: Failed to delete $lg"
    done
}

delete_log_group_exact() {
    local region="$1"
    local name="$2"

    echo "  Deleting log group: ${name} (region: ${region})"
    aws logs delete-log-group \
        --region "$region" \
        --log-group-name "$name" 2>/dev/null || echo "    Not found or failed: $name"
}

echo "========================================"
echo "CloudWatch Log Group Cleanup"
echo "Profile: default"
echo "========================================"

# --- ap-northeast-2 ---
echo ""
echo "[ap-northeast-2]"
delete_log_groups_by_prefix "ap-northeast-2" "/aws/appsync/apis/"
delete_log_group_exact      "ap-northeast-2" "/aws/batch/job"
delete_log_groups_by_prefix "ap-northeast-2" "/aws/codebuild/RagEnginesSageMakerModel"
delete_log_groups_by_prefix "ap-northeast-2" "/aws/lambda/AxOnMasteryStack"
delete_log_groups_by_prefix "ap-northeast-2" "/aws/lambda/VSCodeServerStack"
delete_log_groups_by_prefix "ap-northeast-2" "/aws/sagemaker/Endpoints/RagEnginesSageMakerModel"
delete_log_groups_by_prefix "ap-northeast-2" "AxOnMasteryStack-"

# --- us-west-2 ---
echo ""
echo "[us-west-2]"
delete_log_groups_by_prefix "us-west-2" "/aws/bedrock-agentcore/runtimes/"
delete_log_group_exact      "us-west-2" "/aws/sagemaker/Endpoints/stable-diffusion-fine-tuning"
delete_log_group_exact      "us-west-2" "/aws/sagemaker/NotebookInstances"
delete_log_group_exact      "us-west-2" "/aws/sagemaker/TrainingJobs"

echo ""
echo "========================================"
echo "CloudWatch Log Group Cleanup completed."
echo "========================================"

# Determine exit code
TOTAL_FAILED=$((STACK_FAILED_COUNT + AGENT_FAILED_COUNT))
if [ $TOTAL_FAILED -gt 0 ]; then
    echo -e "${RED}Total Failed Operations: $TOTAL_FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All cleanup operations completed successfully!${NC}"
    exit 0
fi
