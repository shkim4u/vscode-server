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
DEFAULT_STACKS="AxOnMasteryStack,VSCodeServerStack,FineTuningEC2ResourcesStack"
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
    echo -e "${RED}  2. Delete all AgentCore Runtimes and Memories in $AGENTCORE_REGION${NC}"
    echo -e "${RED}  3. Delete IAM User 'APIuser' (if exists)${NC}"
    echo -e "${RED}  4. Delete S3 Bucket 'vscode-server-template-*' (if exists)${NC}"
    echo -e "${RED}  5. Delete CloudWatch Log Groups${NC}"
    echo -e "${RED}  6. Delete images from CDK ECR repositories (repositories will be kept)${NC}"
    echo -e "${RED}  7. Delete SageMaker resources (Endpoints, Models, Notebooks, etc.) in us-west-2${NC}"
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
# Part 2a: AgentCore Runtime and Memory Cleanup
#############################################

echo -e "${YELLOW}=== Part 2: AgentCore Runtime and Memory Cleanup ===${NC}"
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
# Part 2b: AgentCore Memory Cleanup
#############################################

echo -e "${YELLOW}=== AgentCore Memory Cleanup ===${NC}"
echo ""

MEMORY_SUCCESS_COUNT=0
MEMORY_FAILED_COUNT=0
FAILED_MEMORIES=()

# List all AgentCore Memories
echo "Querying AgentCore Memory API in $AGENTCORE_REGION..."
MEMORIES_JSON=$(aws bedrock-agentcore-control list-memories \
    --region "$AGENTCORE_REGION" \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to list AgentCore Memories${NC}"
    echo "Error details: $MEMORIES_JSON"
    echo ""
    echo "Possible causes:"
    echo "  1. Insufficient permissions to list memories"
    echo "  2. AgentCore service not available in region"
else
    # Parse memory count
    MEMORY_COUNT=$(echo "$MEMORIES_JSON" | jq -r '.memories | length')

    if [ "$MEMORY_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No AgentCore Memories found. Nothing to delete.${NC}"
    else
        echo -e "${YELLOW}Found $MEMORY_COUNT AgentCore Memory(ies) to delete:${NC}"
        echo ""

        # Display memories
        echo "$MEMORIES_JSON" | jq -r '.memories[] | "  - Memory ID: \(.id), ARN: \(.arn)"'
        echo ""

        # Additional confirmation for AgentCore Memory (if not skipped globally)
        PROCEED_MEMORY=true
        if [ "$SKIP_PROMPT" = false ]; then
            read -p "$(echo -e ${RED}Proceed with deleting ALL AgentCore Memories? [y/N]: ${NC})" -n 1 -r
            echo ""

            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}AgentCore Memory cleanup skipped by user.${NC}"
                PROCEED_MEMORY=false
            fi
        fi

        if [ "$PROCEED_MEMORY" = true ]; then
            echo -e "${YELLOW}Starting AgentCore Memory cleanup process...${NC}"
            echo ""

            # Process each memory
            while read -r memory; do
                MEMORY_ID=$(echo "$memory" | jq -r '.id')
                MEMORY_ARN=$(echo "$memory" | jq -r '.arn')

                echo -e "${YELLOW}Deleting AgentCore Memory: $MEMORY_ID${NC}"

                # Delete AgentCore Memory
                DELETE_RESULT=$(aws bedrock-agentcore-control delete-memory \
                    --memory-id "$MEMORY_ID" \
                    --region "$AGENTCORE_REGION" \
                    2>&1)

                # Check if deletion was successful
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✓ Successfully deleted AgentCore Memory: $MEMORY_ID${NC}"
                    MEMORY_SUCCESS_COUNT=$((MEMORY_SUCCESS_COUNT + 1))
                else
                    echo -e "${RED}✗ Failed to delete AgentCore Memory: $MEMORY_ID${NC}"
                    echo "  Error: $DELETE_RESULT"
                    MEMORY_FAILED_COUNT=$((MEMORY_FAILED_COUNT + 1))
                    FAILED_MEMORIES+=("$MEMORY_ID")
                fi

                echo ""
            done < <(echo "$MEMORIES_JSON" | jq -c '.memories[]')
        fi

        # AgentCore Memory cleanup summary
        echo -e "${YELLOW}=== AgentCore Memory Cleanup Summary ===${NC}"
        echo -e "${GREEN}Successfully deleted: $MEMORY_SUCCESS_COUNT AgentCore Memory(ies)${NC}"

        if [ $MEMORY_FAILED_COUNT -gt 0 ]; then
            echo -e "${RED}Failed to delete: $MEMORY_FAILED_COUNT AgentCore Memory(ies)${NC}"
            echo ""
            echo -e "${RED}Failed memories:${NC}"
            for failed_memory in "${FAILED_MEMORIES[@]}"; do
                echo -e "  ${RED}- $failed_memory${NC}"
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

set -euo pipefail

CW_DELETED_AP_NORTHEAST_2=0
CW_DELETED_US_WEST_2=0

increment_cw_counter() {
    local region="$1"
    if [ "$region" = "ap-northeast-2" ]; then
        CW_DELETED_AP_NORTHEAST_2=$((CW_DELETED_AP_NORTHEAST_2 + 1))
    elif [ "$region" = "us-west-2" ]; then
        CW_DELETED_US_WEST_2=$((CW_DELETED_US_WEST_2 + 1))
    fi
}

delete_log_groups_by_prefix() {
    local region="$1"
    local prefix="$2"

    echo "  Deleting log groups matching: ${prefix}* (region: ${region})"
    local log_groups
    log_groups=$(aws logs describe-log-groups \
        --region "$region" \
        --log-group-name-prefix "$prefix" \
        --query 'logGroups[].logGroupName' \
        --no-paginate \
        --output text 2>/dev/null) || true

    if [ -z "$log_groups" ]; then
        echo "    No log groups found."
        return
    fi

    echo "$log_groups" | tr '\t' '\n' | while read -r lg; do
        [ -z "$lg" ] && continue
        echo "    Deleting: $lg"
        if aws logs delete-log-group \
            --region "$region" \
            --log-group-name "$lg" 2>/dev/null; then
            increment_cw_counter "$region"
            sleep 0.5
            if aws logs describe-log-groups \
                --region "$region" \
                --log-group-name-prefix "$lg" \
                --query "logGroups[?logGroupName=='$lg'].logGroupName" \
                --output text 2>/dev/null | grep -q .; then
                echo "    WARN: $lg was recreated by an active AWS service. Stop the service first."
            fi
        else
            echo "    WARN: Failed to delete $lg"
        fi
        sleep 0.2
    done
}

delete_log_group_exact() {
    local region="$1"
    local name="$2"

    echo "  Deleting log group: ${name} (region: ${region})"
    if aws logs delete-log-group \
        --region "$region" \
        --log-group-name "$name" 2>/dev/null; then
        increment_cw_counter "$region"
        sleep 0.5
        if aws logs describe-log-groups \
            --region "$region" \
            --log-group-name-prefix "$name" \
            --query "logGroups[?logGroupName=='$name'].logGroupName" \
            --output text 2>/dev/null | grep -q .; then
            echo "    WARN: $name was recreated by an active AWS service. Stop the service first."
        fi
    else
        echo "    Not found or failed: $name"
    fi
}

echo -e "${YELLOW}=== Part 5: CloudWatch Log Group Cleanup ===${NC}"
echo ""
echo "참고: 일부 로그 그룹은 활성 AWS 서비스(예: Batch, Lambda)에 의해 재생성될 수 있습니다."
echo "      삭제 실패 또는 재생성되더라도 무시해도 무방합니다."
echo "      영구 삭제하려면 연관된 AWS 서비스를 먼저 중지하세요."
echo ""

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
echo ""

#############################################
# Part 6: CDK ECR Repository Image Cleanup
#############################################

echo -e "${YELLOW}=== Part 6: CDK ECR Repository Image Cleanup ===${NC}"
echo ""

ECR_IMAGES_DELETED=0

# Find CDK ECR repositories (pattern: cdk-*-container-assets-*)
echo "Searching for CDK ECR repositories in $STACK_REGION..."
CDK_REPOS=$(aws ecr describe-repositories \
    --region "$STACK_REGION" \
    --query 'repositories[?starts_with(repositoryName, `cdk-`) && contains(repositoryName, `container-assets`)].repositoryName' \
    --output text 2>/dev/null) || CDK_REPOS=""

if [ -z "$CDK_REPOS" ]; then
    echo -e "${YELLOW}No CDK ECR repositories found. Skipping.${NC}"
else
    echo -e "${YELLOW}Found CDK ECR repository(s):${NC}"
    for repo in $CDK_REPOS; do
        echo "  - $repo"
    done
    echo ""

    PROCEED_ECR=true
    if [ "$SKIP_PROMPT" = false ]; then
        echo -e "${RED}NOTE: Only images will be deleted. Repositories will be kept for CDK usage.${NC}"
        read -p "$(echo -e ${YELLOW}Do you want to delete images from CDK ECR repositories? [y/N]: ${NC})" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}CDK ECR image cleanup skipped by user.${NC}"
            PROCEED_ECR=false
        fi
    fi

    if [ "$PROCEED_ECR" = true ]; then
        for repo in $CDK_REPOS; do
            echo -e "${YELLOW}Processing repository: $repo${NC}"

            # List all image IDs in the repository
            IMAGE_IDS=$(aws ecr list-images \
                --region "$STACK_REGION" \
                --repository-name "$repo" \
                --query 'imageIds[*]' \
                --output json 2>/dev/null) || IMAGE_IDS="[]"

            IMAGE_COUNT=$(echo "$IMAGE_IDS" | jq 'length')

            if [ "$IMAGE_COUNT" -eq 0 ]; then
                echo "  No images to delete."
            else
                echo "  Found $IMAGE_COUNT image(s). Deleting..."

                # Delete all images in the repository
                DELETE_RESULT=$(aws ecr batch-delete-image \
                    --region "$STACK_REGION" \
                    --repository-name "$repo" \
                    --image-ids "$IMAGE_IDS" \
                    --output json 2>&1)

                if [ $? -eq 0 ]; then
                    DELETED_COUNT=$(echo "$DELETE_RESULT" | jq '.imageIds | length')
                    FAILED_COUNT=$(echo "$DELETE_RESULT" | jq '.failures | length')

                    if [ "$DELETED_COUNT" -gt 0 ]; then
                        echo -e "${GREEN}  ✓ Successfully deleted $DELETED_COUNT image(s)${NC}"
                        ECR_IMAGES_DELETED=$((ECR_IMAGES_DELETED + DELETED_COUNT))
                    fi

                    if [ "$FAILED_COUNT" -gt 0 ]; then
                        echo -e "${RED}  ✗ Failed to delete $FAILED_COUNT image(s)${NC}"
                        echo "$DELETE_RESULT" | jq -r '.failures[] | "    Error: \(.failureReason) (ImageId: \(.imageId.imageDigest // .imageId.imageTag // "unknown"))"'
                    fi
                else
                    echo -e "${RED}  ✗ Failed to delete images from $repo${NC}"
                    echo "  Error: $DELETE_RESULT"
                fi
            fi
            echo ""
        done

        echo -e "${GREEN}Total images deleted from CDK ECR repositories: $ECR_IMAGES_DELETED${NC}"
    fi
fi

echo ""

#############################################
# Part 7: SageMaker Resource Cleanup (us-west-2)
#############################################

echo -e "${YELLOW}=== Part 7: SageMaker Resource Cleanup (us-west-2) ===${NC}"
echo ""

SAGEMAKER_REGION="us-west-2"
SAGEMAKER_ENDPOINT_DELETED=0
SAGEMAKER_ENDPOINT_CONFIG_DELETED=0
SAGEMAKER_MODEL_DELETED=0
SAGEMAKER_NOTEBOOK_DELETED=0
SAGEMAKER_TRAINING_STOPPED=0

# --- Inference Endpoints ---
echo -e "${YELLOW}Checking SageMaker Inference Endpoints...${NC}"
ENDPOINTS=$(aws sagemaker list-endpoints \
    --region "$SAGEMAKER_REGION" \
    --query 'Endpoints[].{Name:EndpointName,Status:EndpointStatus}' \
    --output json 2>/dev/null) || ENDPOINTS="[]"

ENDPOINT_COUNT=$(echo "$ENDPOINTS" | jq 'length')
if [ "$ENDPOINT_COUNT" -gt 0 ]; then
    echo -e "${RED}  Found $ENDPOINT_COUNT Inference Endpoint(s):${NC}"
    echo "$ENDPOINTS" | jq -r '.[] | "    - \(.Name) (Status: \(.Status))"'
    echo ""

    PROCEED_ENDPOINTS=true
    if [ "$SKIP_PROMPT" = false ]; then
        read -p "$(echo -e ${RED}Do you want to delete all SageMaker Endpoints? [y/N]: ${NC})" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Endpoint deletion skipped by user.${NC}"
            PROCEED_ENDPOINTS=false
        fi
    fi

    if [ "$PROCEED_ENDPOINTS" = true ]; then
        while read -r endpoint; do
            ENDPOINT_NAME=$(echo "$endpoint" | jq -r '.Name')
            echo -e "${YELLOW}Deleting Endpoint: $ENDPOINT_NAME${NC}"

            if aws sagemaker delete-endpoint \
                --endpoint-name "$ENDPOINT_NAME" \
                --region "$SAGEMAKER_REGION" 2>&1; then
                echo -e "${GREEN}  ✓ Endpoint deleted: $ENDPOINT_NAME${NC}"
                SAGEMAKER_ENDPOINT_DELETED=$((SAGEMAKER_ENDPOINT_DELETED + 1))
            else
                echo -e "${RED}  ✗ Failed to delete endpoint: $ENDPOINT_NAME${NC}"
            fi
        done < <(echo "$ENDPOINTS" | jq -c '.[]')
    fi
else
    echo -e "${GREEN}  No Inference Endpoints found.${NC}"
fi
echo ""

# --- Endpoint Configurations ---
echo -e "${YELLOW}Checking SageMaker Endpoint Configurations...${NC}"
ENDPOINT_CONFIGS=$(aws sagemaker list-endpoint-configs \
    --region "$SAGEMAKER_REGION" \
    --query 'EndpointConfigs[].EndpointConfigName' \
    --output json 2>/dev/null) || ENDPOINT_CONFIGS="[]"

CONFIG_COUNT=$(echo "$ENDPOINT_CONFIGS" | jq 'length')
if [ "$CONFIG_COUNT" -gt 0 ]; then
    echo -e "${RED}  Found $CONFIG_COUNT Endpoint Configuration(s)${NC}"

    PROCEED_CONFIGS=true
    if [ "$SKIP_PROMPT" = false ]; then
        read -p "$(echo -e ${RED}Do you want to delete all Endpoint Configurations? [y/N]: ${NC})" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Endpoint Configuration deletion skipped by user.${NC}"
            PROCEED_CONFIGS=false
        fi
    fi

    if [ "$PROCEED_CONFIGS" = true ]; then
        while read -r config_name; do
            [ -z "$config_name" ] && continue
            echo -e "${YELLOW}Deleting Endpoint Config: $config_name${NC}"

            if aws sagemaker delete-endpoint-config \
                --endpoint-config-name "$config_name" \
                --region "$SAGEMAKER_REGION" 2>&1; then
                echo -e "${GREEN}  ✓ Endpoint Config deleted: $config_name${NC}"
                SAGEMAKER_ENDPOINT_CONFIG_DELETED=$((SAGEMAKER_ENDPOINT_CONFIG_DELETED + 1))
            else
                echo -e "${RED}  ✗ Failed to delete config: $config_name${NC}"
            fi
        done < <(echo "$ENDPOINT_CONFIGS" | jq -r '.[]')
    fi
else
    echo -e "${GREEN}  No Endpoint Configurations found.${NC}"
fi
echo ""

# --- Models ---
echo -e "${YELLOW}Checking SageMaker Models...${NC}"
MODELS=$(aws sagemaker list-models \
    --region "$SAGEMAKER_REGION" \
    --query 'Models[].ModelName' \
    --output json 2>/dev/null) || MODELS="[]"

MODEL_COUNT=$(echo "$MODELS" | jq 'length')
if [ "$MODEL_COUNT" -gt 0 ]; then
    echo -e "${RED}  Found $MODEL_COUNT Model(s)${NC}"

    PROCEED_MODELS=true
    if [ "$SKIP_PROMPT" = false ]; then
        read -p "$(echo -e ${RED}Do you want to delete all SageMaker Models? [y/N]: ${NC})" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Model deletion skipped by user.${NC}"
            PROCEED_MODELS=false
        fi
    fi

    if [ "$PROCEED_MODELS" = true ]; then
        while read -r model_name; do
            [ -z "$model_name" ] && continue
            echo -e "${YELLOW}Deleting Model: $model_name${NC}"

            if aws sagemaker delete-model \
                --model-name "$model_name" \
                --region "$SAGEMAKER_REGION" 2>&1; then
                echo -e "${GREEN}  ✓ Model deleted: $model_name${NC}"
                SAGEMAKER_MODEL_DELETED=$((SAGEMAKER_MODEL_DELETED + 1))
            else
                echo -e "${RED}  ✗ Failed to delete model: $model_name${NC}"
            fi
        done < <(echo "$MODELS" | jq -r '.[]')
    fi
else
    echo -e "${GREEN}  No Models found.${NC}"
fi
echo ""

# --- Notebook Instances ---
echo -e "${YELLOW}Checking SageMaker Notebook Instances...${NC}"
NOTEBOOK_INSTANCES=$(aws sagemaker list-notebook-instances \
    --region "$SAGEMAKER_REGION" \
    --query 'NotebookInstances[].{Name:NotebookInstanceName,Status:NotebookInstanceStatus}' \
    --output json 2>/dev/null) || NOTEBOOK_INSTANCES="[]"

NOTEBOOK_COUNT=$(echo "$NOTEBOOK_INSTANCES" | jq 'length')
if [ "$NOTEBOOK_COUNT" -gt 0 ]; then
    echo -e "${RED}  Found $NOTEBOOK_COUNT Notebook Instance(s):${NC}"
    echo "$NOTEBOOK_INSTANCES" | jq -r '.[] | "    - \(.Name) (Status: \(.Status))"'
    echo ""

    PROCEED_NOTEBOOKS=true
    if [ "$SKIP_PROMPT" = false ]; then
        read -p "$(echo -e ${RED}Do you want to delete all Notebook Instances? [y/N]: ${NC})" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Notebook Instance deletion skipped by user.${NC}"
            PROCEED_NOTEBOOKS=false
        fi
    fi

    if [ "$PROCEED_NOTEBOOKS" = true ]; then
        while read -r notebook; do
            NOTEBOOK_NAME=$(echo "$notebook" | jq -r '.Name')
            NOTEBOOK_STATUS=$(echo "$notebook" | jq -r '.Status')

            echo -e "${YELLOW}Processing Notebook: $NOTEBOOK_NAME (Status: $NOTEBOOK_STATUS)${NC}"

            # Stop if running
            if [ "$NOTEBOOK_STATUS" = "InService" ]; then
                echo "  Stopping notebook instance..."
                if aws sagemaker stop-notebook-instance \
                    --notebook-instance-name "$NOTEBOOK_NAME" \
                    --region "$SAGEMAKER_REGION" 2>&1; then
                    echo -e "${GREEN}  ✓ Stop initiated${NC}"
                    echo "  Waiting for notebook to stop..."
                    aws sagemaker wait notebook-instance-stopped \
                        --notebook-instance-name "$NOTEBOOK_NAME" \
                        --region "$SAGEMAKER_REGION" 2>&1 || true
                fi
            fi

            # Delete
            echo "  Deleting notebook instance..."
            if aws sagemaker delete-notebook-instance \
                --notebook-instance-name "$NOTEBOOK_NAME" \
                --region "$SAGEMAKER_REGION" 2>&1; then
                echo -e "${GREEN}  ✓ Notebook Instance deleted: $NOTEBOOK_NAME${NC}"
                SAGEMAKER_NOTEBOOK_DELETED=$((SAGEMAKER_NOTEBOOK_DELETED + 1))
            else
                echo -e "${RED}  ✗ Failed to delete notebook: $NOTEBOOK_NAME${NC}"
            fi
        done < <(echo "$NOTEBOOK_INSTANCES" | jq -c '.[]')
    fi
else
    echo -e "${GREEN}  No Notebook Instances found.${NC}"
fi
echo ""

# --- Training Jobs (Stop only - cannot delete) ---
echo -e "${YELLOW}Checking SageMaker Training Jobs...${NC}"
TRAINING_JOBS=$(aws sagemaker list-training-jobs \
    --region "$SAGEMAKER_REGION" \
    --status-equals "InProgress" \
    --query 'TrainingJobSummaries[].{Name:TrainingJobName,Status:TrainingJobStatus}' \
    --output json 2>/dev/null) || TRAINING_JOBS="[]"

TRAINING_COUNT=$(echo "$TRAINING_JOBS" | jq 'length')
if [ "$TRAINING_COUNT" -gt 0 ]; then
    echo -e "${RED}  Found $TRAINING_COUNT In-Progress Training Job(s):${NC}"
    echo "$TRAINING_JOBS" | jq -r '.[] | "    - \(.Name) (Status: \(.Status))"'
    echo ""
    echo -e "${YELLOW}  Note: Training Jobs cannot be deleted, only stopped.${NC}"

    PROCEED_TRAINING=true
    if [ "$SKIP_PROMPT" = false ]; then
        read -p "$(echo -e ${RED}Do you want to stop all In-Progress Training Jobs? [y/N]: ${NC})" -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Training Job stop skipped by user.${NC}"
            PROCEED_TRAINING=false
        fi
    fi

    if [ "$PROCEED_TRAINING" = true ]; then
        while read -r job; do
            JOB_NAME=$(echo "$job" | jq -r '.Name')
            echo -e "${YELLOW}Stopping Training Job: $JOB_NAME${NC}"

            if aws sagemaker stop-training-job \
                --training-job-name "$JOB_NAME" \
                --region "$SAGEMAKER_REGION" 2>&1; then
                echo -e "${GREEN}  ✓ Training Job stopped: $JOB_NAME${NC}"
                SAGEMAKER_TRAINING_STOPPED=$((SAGEMAKER_TRAINING_STOPPED + 1))
            else
                echo -e "${RED}  ✗ Failed to stop training job: $JOB_NAME${NC}"
            fi
        done < <(echo "$TRAINING_JOBS" | jq -c '.[]')
    fi
else
    echo -e "${GREEN}  No In-Progress Training Jobs found.${NC}"
fi
echo ""

echo -e "${YELLOW}=== SageMaker Cleanup Summary ===${NC}"
echo -e "${GREEN}Endpoints Deleted:          $SAGEMAKER_ENDPOINT_DELETED${NC}"
echo -e "${GREEN}Endpoint Configs Deleted:   $SAGEMAKER_ENDPOINT_CONFIG_DELETED${NC}"
echo -e "${GREEN}Models Deleted:             $SAGEMAKER_MODEL_DELETED${NC}"
echo -e "${GREEN}Notebook Instances Deleted: $SAGEMAKER_NOTEBOOK_DELETED${NC}"
echo -e "${GREEN}Training Jobs Stopped:      $SAGEMAKER_TRAINING_STOPPED${NC}"
echo ""

#############################################
# Final Summary
#############################################

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Final Cleanup Summary${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${GREEN}CloudFormation Stacks Deleted:          $STACK_SUCCESS_COUNT${NC}"
echo -e "${GREEN}AgentCore Runtimes Deleted:             $AGENT_SUCCESS_COUNT${NC}"
echo -e "${GREEN}AgentCore Memories Deleted:             $MEMORY_SUCCESS_COUNT${NC}"
echo -e "${GREEN}IAM User 'APIuser' Deleted:             $IAM_USER_DELETED${NC}"
echo -e "${GREEN}S3 Bucket Deleted:                      $S3_BUCKET_DELETED${NC}"
echo -e "${GREEN}CW Log Groups Deleted (ap-northeast-2): $CW_DELETED_AP_NORTHEAST_2${NC}"
echo -e "${GREEN}CW Log Groups Deleted (us-west-2):      $CW_DELETED_US_WEST_2${NC}"
echo -e "${GREEN}CDK ECR Images Deleted:                 $ECR_IMAGES_DELETED${NC}"
echo -e "${GREEN}SageMaker Endpoints Deleted:            $SAGEMAKER_ENDPOINT_DELETED${NC}"
echo -e "${GREEN}SageMaker Endpoint Configs Deleted:     $SAGEMAKER_ENDPOINT_CONFIG_DELETED${NC}"
echo -e "${GREEN}SageMaker Models Deleted:               $SAGEMAKER_MODEL_DELETED${NC}"
echo -e "${GREEN}SageMaker Notebook Instances Deleted:   $SAGEMAKER_NOTEBOOK_DELETED${NC}"
echo -e "${GREEN}SageMaker Training Jobs Stopped:        $SAGEMAKER_TRAINING_STOPPED${NC}"
echo ""

# Determine exit code
TOTAL_FAILED=$((STACK_FAILED_COUNT + AGENT_FAILED_COUNT + MEMORY_FAILED_COUNT))
if [ $TOTAL_FAILED -gt 0 ]; then
    echo -e "${RED}Total Failed Operations: $TOTAL_FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All cleanup operations completed successfully!${NC}"
    exit 0
fi
