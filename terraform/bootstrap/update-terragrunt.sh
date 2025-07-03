#!/bin/bash

# Script to update terragrunt.hcl with the correct bucket name from bootstrap outputs
# Usage: ./update-terragrunt.sh

set -e

# Get the current bucket name from terraform outputs
echo "Getting bucket name from bootstrap outputs..."
BUCKET_NAME=$(terraform output -raw aws_s3_bucket_name)

if [ -z "$BUCKET_NAME" ]; then
    echo "Error: Could not get bucket name from terraform outputs"
    echo "Make sure you have run 'terraform apply' in the bootstrap directory"
    exit 1
fi

echo "Current bucket name: $BUCKET_NAME"

# Path to terragrunt.hcl file
TERRAGRUNT_FILE="../terragrunt.hcl"

if [ ! -f "$TERRAGRUNT_FILE" ]; then
    echo "Error: $TERRAGRUNT_FILE not found"
    exit 1
fi

# Create backup
cp "$TERRAGRUNT_FILE" "${TERRAGRUNT_FILE}.backup"
echo "Created backup: ${TERRAGRUNT_FILE}.backup"

# Update the bucket name in terragrunt.hcl
sed -i.tmp "s/backend_bucket = \".*\"/backend_bucket = \"$BUCKET_NAME\"/" "$TERRAGRUNT_FILE"
rm "${TERRAGRUNT_FILE}.tmp"

echo "Updated $TERRAGRUNT_FILE with bucket name: $BUCKET_NAME"

# Show the change
echo ""
echo "Updated line:"
grep "backend_bucket" "$TERRAGRUNT_FILE"

# Clean up generated files so they get regenerated with correct bucket name
echo ""
echo "Cleaning up generated files for regeneration..."

# Remove terragrunt-generated backend.tf files
find ../envs -name "backend.tf" -exec rm -f {} \;
echo "Removed terragrunt-generated backend.tf files"

# Remove bootstrap-generated backend files (they'll be regenerated on next bootstrap run)
rm -f generated/backend-aws.tf generated/backend-gcp.tf
echo "Removed bootstrap-generated backend configuration files"

echo ""
echo "✅ terragrunt.hcl has been updated successfully!"
echo "   Backup saved as: ${TERRAGRUNT_FILE}.backup"
echo "   Generated files cleaned up - they'll be regenerated automatically"
echo ""
echo "Next steps:"
echo "1. Run 'terragrunt plan' in your environment to regenerate backend.tf"
echo "2. Or run the bootstrap again to regenerate all backend files" 