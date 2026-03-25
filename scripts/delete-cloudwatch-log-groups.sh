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

echo "========================================"
echo "CloudWatch Log Group Cleanup"
echo "Profile: default"
echo "========================================"
echo ""
echo "참고: 일부 로그 그룹은 활성 AWS 서비스(예: Batch, Lambda)에 의해 재생성될 수 있습니다."
echo "      삭제 실패 또는 재생성되더라도 무시해도 무방합니다."
echo "      영구 삭제하려면 연관된 AWS 서비스를 먼저 중지하세요."

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
