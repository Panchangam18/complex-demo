# Terraform Bootstrap

This directory contains the bootstrap infrastructure for Terraform backend state management. It creates:

- AWS S3 bucket for storing Terraform state files
- AWS DynamoDB table for state locking
- GCP Cloud Storage bucket for storing Terraform state files

## Bucket Naming Issue

The bucket names include a random suffix to ensure global uniqueness. However, the `terragrunt.hcl` file currently has a hardcoded bucket name, which can cause issues if you run bootstrap multiple times.

## Quick Start

1. **Bootstrap with existing suffix** (recommended if you have existing infrastructure):
   ```bash
   ./run-bootstrap.sh hp9dga
   ```

2. **Update terragrunt.hcl automatically**:
   ```bash
   ./update-terragrunt.sh
   ```

## Detailed Usage

### Option 1: Use the existing bucket (Recommended)

If you already have a bootstrap environment, use the existing bucket:

```bash
# Get the current bucket name
terraform output -raw aws_s3_bucket_name
```

Make sure your `terragrunt.hcl` file uses this bucket name.

### Option 2: Create with specific suffix

To maintain consistency, use the provided script:

```bash
# Use existing suffix
./run-bootstrap.sh hp9dga

# Or create with new suffix
./run-bootstrap.sh mynewsuffix
```

### Option 3: Manual bootstrap

```bash
# Initialize terraform
terraform init

# Plan with specific suffix (optional)
terraform plan -var="bucket_suffix=hp9dga"

# Apply with specific suffix
terraform apply -var="bucket_suffix=hp9dga"
```

## Updating Terragrunt Configuration

### Automatic Update (Recommended)

Use the provided script to automatically update your `terragrunt.hcl` file:

```bash
./update-terragrunt.sh
```

This script will:
- Get the bucket name from terraform outputs
- Create a backup of your `terragrunt.hcl` file
- Update the bucket name automatically

### Manual Update

After bootstrap, update your `terragrunt.hcl` file with the correct bucket name:

```hcl
locals {
  # Backend bucket name - update this after bootstrap
  backend_bucket = "complex-demo-tfstate-YOURSUFFIX"
  # ... rest of config
}
```

## Important Notes

1. **Bucket Naming**: If you don't specify a `bucket_suffix`, a random one will be generated
2. **State Consistency**: Make sure your `terragrunt.hcl` file uses the correct bucket name
3. **Prevent Destroy**: The S3 bucket and DynamoDB table have `prevent_destroy = true` to avoid accidental deletion

## Scripts

- `run-bootstrap.sh`: Bootstrap with optional custom suffix
- `update-terragrunt.sh`: Automatically update terragrunt.hcl with correct bucket name

## Outputs

The bootstrap creates the following outputs:

- `aws_s3_bucket_name`: S3 bucket name for state storage
- `aws_dynamodb_table_name`: DynamoDB table name for state locking  
- `gcp_storage_bucket_name`: GCP storage bucket name
- `backend_configuration`: Complete backend configuration for reference

## Variables

- `aws_region`: AWS region for backend resources (default: us-east-1)
- `gcp_project_id`: GCP project ID (required for GCP resources)
- `gcp_region`: GCP region (default: us-central1)
- `bucket_suffix`: Custom suffix for bucket names (optional, generates random if not provided)

## Troubleshooting

If you encounter issues:

1. **Wrong bucket name**: Run `./update-terragrunt.sh` to fix the bucket name
2. **Random suffix changed**: Always use the same suffix when re-running bootstrap
3. **State inconsistency**: Check that your `terragrunt.hcl` matches the actual bucket name 