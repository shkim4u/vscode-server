#!/bin/bash

# Reset Script for IAM User 'mspuser'
# This script deletes all Access Keys, Bedrock Bearer Tokens (service-specific credentials),
# resets the console login password, and deactivates/deletes all MFA devices for the 'mspuser' IAM user.
# The user itself is NOT deleted.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

IAM_USER="mspuser"

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --yes    Skip confirmation prompts (for automation)"
    echo "  -h, --help   Show this help message"
    exit 0
}

# Parse command line arguments
SKIP_PROMPT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -y|--yes)
            SKIP_PROMPT=true
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            echo ""
            usage
            ;;
    esac
done

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Reset IAM User '${IAM_USER}'${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Check AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials are not configured or invalid${NC}"
    echo "Please configure AWS credentials using 'aws configure' or set environment variables."
    exit 1
fi
echo -e "${GREEN}AWS credentials OK${NC}"
echo ""

# Display current AWS identity
CALLER_IDENTITY=$(aws sts get-caller-identity --output json)
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
USER_ARN=$(echo "$CALLER_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)

echo -e "${YELLOW}Current AWS Identity:${NC}"
echo "  Account: $ACCOUNT_ID"
echo "  ARN:     $USER_ARN"
echo ""

# Check if the user exists
if ! aws iam get-user --user-name "$IAM_USER" &>/dev/null; then
    echo -e "${RED}Error: IAM User '${IAM_USER}' does not exist.${NC}"
    exit 1
fi

echo -e "${GREEN}Found IAM User '${IAM_USER}'${NC}"
echo ""

# Confirmation prompt
if [ "$SKIP_PROMPT" = false ]; then
    echo -e "${RED}WARNING: This script will:${NC}"
    echo -e "${RED}  1. Delete all Access Keys for '${IAM_USER}'${NC}"
    echo -e "${RED}  2. Delete all Bedrock Bearer Tokens (service-specific credentials) for '${IAM_USER}'${NC}"
    echo -e "${RED}  3. Delete the console login password for '${IAM_USER}'${NC}"
    echo -e "${RED}  4. Deactivate and delete all MFA devices for '${IAM_USER}'${NC}"
    echo -e "${RED}The user '${IAM_USER}' itself will NOT be deleted.${NC}"
    echo ""
    read -p "$(echo -e ${RED}Are you sure you want to proceed? [y/N]: ${NC})" -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Aborted by user.${NC}"
        exit 0
    fi
    echo ""
fi

ACCESS_KEYS_DELETED=0
SERVICE_CREDS_DELETED=0
LOGIN_PROFILE_DELETED=false
MFA_DEVICES_DELETED=0

#############################################
# Step 1: Delete all Access Keys
#############################################

echo -e "${YELLOW}=== Step 1: Delete Access Keys ===${NC}"
echo ""

ACCESS_KEYS=$(aws iam list-access-keys --user-name "$IAM_USER" --query 'AccessKeyMetadata[].AccessKeyId' --output text)
if [ -n "$ACCESS_KEYS" ]; then
    for key in $ACCESS_KEYS; do
        aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$key"
        echo -e "${GREEN}  ✓ Access key deleted: $key${NC}"
        ACCESS_KEYS_DELETED=$((ACCESS_KEYS_DELETED + 1))
    done
else
    echo "  No access keys to delete"
fi

echo ""

#############################################
# Step 2: Delete Bedrock Bearer Tokens
#         (service-specific credentials)
#############################################

echo -e "${YELLOW}=== Step 2: Delete Service-Specific Credentials (Bedrock Bearer Tokens) ===${NC}"
echo ""

SERVICE_CREDS=$(aws iam list-service-specific-credentials --user-name "$IAM_USER" --query 'ServiceSpecificCredentials[].ServiceSpecificCredentialId' --output text 2>/dev/null || echo "")
if [ -n "$SERVICE_CREDS" ]; then
    for cred in $SERVICE_CREDS; do
        aws iam delete-service-specific-credential --user-name "$IAM_USER" --service-specific-credential-id "$cred"
        echo -e "${GREEN}  ✓ Service-specific credential deleted: $cred${NC}"
        SERVICE_CREDS_DELETED=$((SERVICE_CREDS_DELETED + 1))
    done
else
    echo "  No service-specific credentials to delete"
fi

echo ""

#############################################
# Step 3: Delete Console Login Password
#############################################

echo -e "${YELLOW}=== Step 3: Delete Console Login Password ===${NC}"
echo ""

if aws iam get-login-profile --user-name "$IAM_USER" &>/dev/null; then
    if aws iam delete-login-profile --user-name "$IAM_USER"; then
        echo -e "${GREEN}  ✓ Console login password deleted${NC}"
        LOGIN_PROFILE_DELETED=true
    else
        echo -e "${RED}  ✗ Failed to delete console login password${NC}"
    fi
else
    echo "  No console login password to delete"
fi

echo ""

#############################################
# Step 4: Deactivate and Delete MFA Devices
#############################################

echo -e "${YELLOW}=== Step 4: Deactivate and Delete MFA Devices ===${NC}"
echo ""

MFA_DEVICES=$(aws iam list-mfa-devices --user-name "$IAM_USER" --query 'MFADevices[].SerialNumber' --output text 2>/dev/null || echo "")
if [ -n "$MFA_DEVICES" ]; then
    for device in $MFA_DEVICES; do
        # Deactivate MFA device
        if aws iam deactivate-mfa-device --user-name "$IAM_USER" --serial-number "$device" 2>/dev/null; then
            echo -e "${GREEN}  ✓ MFA device deactivated: $device${NC}"

            # If it's a virtual MFA device (contains 'mfa/' in the ARN), delete it
            if [[ "$device" == *"mfa/"* ]]; then
                if aws iam delete-virtual-mfa-device --serial-number "$device" 2>/dev/null; then
                    echo -e "${GREEN}  ✓ Virtual MFA device deleted: $device${NC}"
                else
                    echo -e "${YELLOW}  ⚠ Virtual MFA device deactivated but could not be deleted: $device${NC}"
                fi
            fi

            MFA_DEVICES_DELETED=$((MFA_DEVICES_DELETED + 1))
        else
            echo -e "${RED}  ✗ Failed to deactivate MFA device: $device${NC}"
        fi
    done
else
    echo "  No MFA devices to deactivate"
fi

echo ""

#############################################
# Summary
#############################################

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Reset Summary for '${IAM_USER}'${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo -e "${GREEN}Access Keys Deleted:               $ACCESS_KEYS_DELETED${NC}"
echo -e "${GREEN}Service-Specific Credentials Deleted: $SERVICE_CREDS_DELETED${NC}"
echo -e "${GREEN}Console Login Password Deleted:     $LOGIN_PROFILE_DELETED${NC}"
echo -e "${GREEN}MFA Devices Deactivated/Deleted:   $MFA_DEVICES_DELETED${NC}"
echo ""
echo -e "${GREEN}Reset operations completed successfully!${NC}"
