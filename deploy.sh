#!/bin/bash
set -e

# TerraPerf Landing Page Deployment Script
# Deploys static files to S3 and invalidates CloudFront cache

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_PROFILE="${AWS_PROFILE:-terraperf-workloads-prod}"
S3_BUCKET="terraperf-landing-prod"
CLOUDFRONT_DISTRIBUTION_ID=""

echo "=========================================="
echo "TerraPerf Landing Page Deployment"
echo "=========================================="
echo "AWS Profile: $AWS_PROFILE"
echo "S3 Bucket: $S3_BUCKET"
echo ""

# Check AWS credentials
echo "Checking AWS credentials..."
aws sts get-caller-identity --profile "$AWS_PROFILE" > /dev/null 2>&1 || {
    echo "ERROR: AWS credentials not configured. Run: aws sso login --profile $AWS_PROFILE"
    exit 1
}

# Get CloudFront distribution ID from Terraform state
if [ -f "$SCRIPT_DIR/terraform/terraform.tfstate" ]; then
    CLOUDFRONT_DISTRIBUTION_ID=$(cd "$SCRIPT_DIR/terraform" && terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
fi

# If no state file, try to get from AWS directly
if [ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
    echo "Getting CloudFront distribution ID from AWS..."
    CLOUDFRONT_DISTRIBUTION_ID=$(aws cloudfront list-distributions --profile "$AWS_PROFILE" \
        --query "DistributionList.Items[?Aliases.Items[?contains(@, 'terraperf.com')]].Id" \
        --output text 2>/dev/null || echo "")
fi

echo "CloudFront Distribution: ${CLOUDFRONT_DISTRIBUTION_ID:-Not found}"
echo ""

# Sync files to S3
echo "Uploading files to S3..."
aws s3 sync "$SCRIPT_DIR/" "s3://$S3_BUCKET/" \
    --profile "$AWS_PROFILE" \
    --exclude "terraform/*" \
    --exclude ".git/*" \
    --exclude "api/*" \
    --exclude "deploy.sh" \
    --exclude "README.md" \
    --exclude ".gitignore" \
    --delete

# Set correct content types
echo "Setting content types..."
aws s3 cp "s3://$S3_BUCKET/index.html" "s3://$S3_BUCKET/index.html" \
    --profile "$AWS_PROFILE" \
    --content-type "text/html" \
    --metadata-directive REPLACE

aws s3 cp "s3://$S3_BUCKET/styles.css" "s3://$S3_BUCKET/styles.css" \
    --profile "$AWS_PROFILE" \
    --content-type "text/css" \
    --metadata-directive REPLACE

aws s3 cp "s3://$S3_BUCKET/favicon.svg" "s3://$S3_BUCKET/favicon.svg" \
    --profile "$AWS_PROFILE" \
    --content-type "image/svg+xml" \
    --metadata-directive REPLACE

aws s3 cp "s3://$S3_BUCKET/privacy.html" "s3://$S3_BUCKET/privacy.html" \
    --profile "$AWS_PROFILE" \
    --content-type "text/html" \
    --metadata-directive REPLACE

# Invalidate CloudFront cache
if [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
    echo ""
    echo "Invalidating CloudFront cache..."
    aws cloudfront create-invalidation \
        --profile "$AWS_PROFILE" \
        --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "/*" \
        --query "Invalidation.Id" \
        --output text
    echo "Cache invalidation started"
fi

echo ""
echo "=========================================="
echo "Deployment complete!"
echo "=========================================="
echo "Site: https://terraperf.com"
echo ""
