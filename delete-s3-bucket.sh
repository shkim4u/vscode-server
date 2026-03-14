#############################################
# Delete S3 Bucket for CloudFormation template upload (vscode-server-template-<account-id>-<region>)
#############################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Display current AWS identity
CALLER_IDENTITY=$(aws sts get-caller-identity --output json)
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
USER_ARN=$(echo "$CALLER_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)

echo -e "${YELLOW}Current AWS Identity:${NC}"
echo "  Account: $ACCOUNT_ID"
echo "  ARN:     $USER_ARN"
echo ""

AWS_REGION=ap-northeast-2

echo -e "${YELLOW}=== Part 4: S3 Bucket Cleanup ===${NC}"
echo ""

S3_BUCKET_DELETED=false
S3_BUCKET_NAME="vscode-server-template-${ACCOUNT_ID}-${AWS_REGION}"

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
        if aws s3api delete-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" 2>&1; then
            echo -e "${GREEN}✓ S3 Bucket '$S3_BUCKET_NAME' deleted successfully${NC}"
            S3_BUCKET_DELETED=true
        else
            echo -e "${RED}✗ Failed to delete S3 Bucket '$S3_BUCKET_NAME'${NC}"
        fi
    fi
else
    echo -e "${YELLOW}S3 Bucket '$S3_BUCKET_NAME' does not exist. Skipping.${NC}"
fi