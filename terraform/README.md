# Decaseone Terraform Configuration

This directory contains Terraform Infrastructure as Code (IaC) for managing the Snowflake infrastructure for the decaseone project.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Directory Structure](#directory-structure)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Usage](#usage)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

This Terraform configuration manages:
- **Snowflake Database**: Main database for the decaseone project
- **Schemas**: Database schemas for organizing tables
- **Warehouse**: Compute resources for running queries
- **Roles**: Access control and permissions
- **Tables**: Data structures (customize based on your DDL)
- **Grants**: Database privileges for roles

## Prerequisites

1. **Terraform** >= 1.0 installed
   ```bash
   terraform version
   ```

2. **Snowflake CLI** (optional, for debugging)
   ```bash
   brew install snowflake-cli
   ```

3. **Snowflake Account** with administrator access

4. **AWS Account** (if using S3 for remote state - optional)

5. **Environment Variables** or credentials file configured

## Directory Structure

```
terraform/
├── main.tf                  # Entry point with locals and common configuration
├── providers.tf             # Provider configuration and version requirements
├── variables.tf             # Input variable definitions
├── outputs.tf               # Output value definitions
├── snowflake.tf             # Snowflake resource definitions
├── terraform.tfvars.example # Example variables file (copy and customize)
├── .gitignore              # Git ignore rules for Terraform files
└── README.md               # This file
```

## Getting Started

### Step 1: Initialize Terraform

```bash
cd terraform
terraform init
```

This command:
- Downloads required providers (Snowflake)
- Creates `.terraform/` directory
- Initializes the backend (local by default)

### Step 2: Create terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your Snowflake credentials:

```hcl
snowflake_account  = "xy12345.us-east-1"
snowflake_user     = "your-username"
snowflake_password = "your-password"
```

**⚠️ IMPORTANT**: Never commit `terraform.tfvars` to version control!

### Step 3: Validate Configuration

```bash
terraform validate
```

### Step 4: Plan Infrastructure

```bash
terraform plan -out=tfplan
```

This shows what resources will be created, modified, or destroyed.

### Step 5: Apply Configuration

```bash
terraform apply tfplan
```

Review the plan and type `yes` to confirm.

## Configuration

### Snowflake Provider Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `snowflake_account` | Snowflake account ID | - | Yes |
| `snowflake_user` | Snowflake username | - | Yes |
| `snowflake_password` | Snowflake password | - | Yes |
| `snowflake_role` | Snowflake role | `SYSADMIN` | No |
| `snowflake_warehouse` | Snowflake warehouse | `COMPUTE_WH` | No |
| `database_name` | Database name | `DECASEONE_DB` | No |
| `schema_name` | Schema name | `PUBLIC` | No |
| `environment` | Environment (dev/staging/prod) | `dev` | No |

### Using Environment Variables

For CI/CD pipelines, use environment variables instead of `terraform.tfvars`:

```bash
export TF_VAR_snowflake_account="xy12345.us-east-1"
export TF_VAR_snowflake_user="your-username"
export TF_VAR_snowflake_password="your-password"
export TF_VAR_environment="prod"
```

## Usage

### View Current State

```bash
terraform state list
terraform state show snowflake_database.decaseone
```

### Modify Resources

Edit `snowflake.tf` to add/remove resources, then:

```bash
terraform plan
terraform apply
```

### Destroy Infrastructure

```bash
terraform destroy
```

⚠️ This will delete all managed resources in Snowflake!

### Get Outputs

```bash
terraform output
terraform output database_name
```

### Refresh State

```bash
terraform refresh
```

## Best Practices

### 1. **State Management**

- Use remote state (S3, Terraform Cloud) for team environments
- Enable state locking to prevent concurrent modifications
- Keep state files encrypted and access-controlled

### 2. **Sensitive Data**

- Never commit `terraform.tfvars` to version control
- Use environment variables or Terraform Cloud for secrets
- Mark sensitive outputs appropriately

### 3. **Version Control**

- Track `*.tf` files and `.terraform.lock.hcl`
- Ignore `*.tfvars`, `.terraform/`, and `*.tfstate` files
- Use meaningful commit messages

### 4. **Code Organization**

- Keep related resources in the same file
- Use descriptive resource names
- Add comments explaining complex logic

### 5. **Testing**

- Use `terraform validate` before committing
- Use `terraform plan` to review changes
- Test in dev environment before production

### 6. **Documentation**

- Document custom resources and variables
- Keep README updated with changes
- Use comments in code for clarity

### 7. **Security**

- Use IAM roles instead of static credentials in CI/CD
- Rotate passwords regularly
- Audit Terraform access logs

## Remote State Setup (AWS S3)

For team collaboration, configure remote state:

### 1. Create S3 Bucket

```bash
aws s3api create-bucket \
  --bucket your-terraform-state-bucket \
  --region us-east-1
```

### 2. Enable Versioning

```bash
aws s3api put-bucket-versioning \
  --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled
```

### 3. Create DynamoDB Table for Locking

```bash
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1
```

### 4. Uncomment Backend in `providers.tf`

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "decaseone/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### 5. Reinitialize

```bash
terraform init
```

## GitHub Actions CI/CD Integration

See `.github/workflows/terraform.yml` for the automated CI/CD pipeline.

### Workflow Triggers

- **On Pull Request**: Plan and validate
- **On Merge to main**: Apply changes to production

### Required Secrets

Set these in GitHub repository settings:

- `TF_VAR_SNOWFLAKE_ACCOUNT`
- `TF_VAR_SNOWFLAKE_USER`
- `TF_VAR_SNOWFLAKE_PASSWORD`
- `AWS_ACCESS_KEY_ID` (for S3 state)
- `AWS_SECRET_ACCESS_KEY` (for S3 state)

## Troubleshooting

### Error: "Could not load plugin"

```bash
terraform init -upgrade
```

### Error: "Invalid or unknown provider"

Verify provider configuration in `providers.tf`:

```bash
terraform providers
```

### Error: "Authentication failed"

Check Snowflake credentials:

```bash
snowflake-cli connection test
```

### Error: "Resource already exists"

Import existing resource:

```bash
terraform import snowflake_database.decaseone "DECASEONE_DB"
```

### State Lock Stuck

Force unlock (use with caution):

```bash
terraform force-unlock <LOCK_ID>
```

## Additional Resources

- [Snowflake Terraform Provider Documentation](https://registry.terraform.io/providers/Snowflake-Labs/snowflake/latest/docs)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices.html)
- [Snowflake Documentation](https://docs.snowflake.com)

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review Snowflake and Terraform documentation
3. Open an issue in the repository

---

**Last Updated**: August 29, 2026
