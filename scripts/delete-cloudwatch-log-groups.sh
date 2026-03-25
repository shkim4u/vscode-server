#!/bin/bash
###
## CloudWatch Log Group 일괄 삭제 스크립트
## AWS Profile: default
## 대상 리전: ap-northeast-2, us-west-2
###

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
