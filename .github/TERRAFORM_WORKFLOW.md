# GitHub Actions Terraform CI/CD Workflow

This GitHub Actions workflow automates Terraform operations for infrastructure management.

## 📋 Workflow Overview

### Triggers

- **Pull Requests** to `main`: Validates and plans changes
- **Push to main**: Applies Terraform changes to production
- **Push to feature/terraform-infrastructure**: Validates configuration

### Jobs

#### 1. **Terraform Validate** (Always runs)
- Checks code formatting
- Initializes Terraform
- Validates configuration syntax

#### 2. **Terraform Plan** (On Pull Requests)
- Plans infrastructure changes
- Comments plan details on PR
- Allows review before applying

#### 3. **Terraform Apply** (On Push to main)
- Applies approved changes
- Updates Snowflake infrastructure
- Comments results on commit

## 🔐 Required Secrets

Set these in GitHub repository settings (`Settings → Secrets and variables → Actions`):

| Secret | Description | Example |
|--------|-------------|---------|
| `TF_VAR_SNOWFLAKE_ACCOUNT` | Snowflake account ID | `xy12345.us-east-1` |
| `TF_VAR_SNOWFLAKE_USER` | Snowflake username | `terraform_user` |
| `TF_VAR_SNOWFLAKE_PASSWORD` | Snowflake password | `your-secure-password` |

**Optional for Remote State:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### How to Add Secrets

1. Go to repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each secret with the exact name from the table above
4. Click "Add secret"

## 🚀 Usage

### Creating a Pull Request

1. Create a feature branch:
   ```bash
   git checkout -b feature/my-changes
   ```

2. Make Terraform changes:
   ```bash
   git add terraform/
   git commit -m "Add new Snowflake resources"
   ```

3. Push and create PR:
   ```bash
   git push origin feature/my-changes
   ```

4. GitHub Actions will:
   - Validate your Terraform code
   - Create a plan and comment on the PR
   - Allow you to review before merging

### Merging Changes

When you merge the PR to `main`:
- GitHub Actions automatically applies the changes
- Snowflake infrastructure is updated
- A comment confirms completion

## 📊 Workflow File Structure

```yaml
name: Terraform CI/CD           # Workflow name
on:                             # Triggers
  push/pull_request
env:                            # Environment variables
jobs:
  terraform-validate            # Job 1: Validate
  terraform-plan                # Job 2: Plan (PR only)
  terraform-apply               # Job 3: Apply (main only)
```

## ✅ Best Practices

### 1. **Branch Protection Rules**

Require PR approval before merging:
1. Go to Settings → Branches
2. Add rule for `main` branch
3. Enable "Require status checks to pass"
4. Require "terraform-validate" to pass

### 2. **Review Process**

Before merging to `main`:
- Review the plan output in PR comments
- Verify changes are expected
- Request changes if needed
- Approve once confident

### 3. **Secrets Management**

- Store sensitive data in GitHub Secrets
- Never commit `terraform.tfvars`
- Rotate credentials regularly
- Use IAM roles in CI/CD when possible

### 4. **Notifications**

Monitor workflow results:
- Check "Actions" tab in GitHub
- Subscribe to workflow notifications
- Set up Slack/email alerts

## 🔧 Troubleshooting

### Workflow Fails to Run

**Issue**: Workflow doesn't trigger on push
- Check branch name matches workflow trigger
- Verify file path changes trigger the workflow
- Check if branch protection rules are blocking

### Plan Fails with Authentication Error

**Issue**: `Error: Error reading Snowflake account`
- Verify secrets are set correctly in GitHub
- Check Snowflake account ID format
- Ensure credentials have proper permissions

### Apply Fails in Production

**Issue**: Terraform apply fails on main branch
- Check Snowflake service availability
- Verify account has required permissions
- Review plan output for conflicts

### Secrets Not Available

**Issue**: `TF_VAR_* not found`
- Confirm secrets are added to correct repository
- Check secret names match exactly (case-sensitive)
- Verify workflow has permission to access secrets

## 📝 Monitoring

### View Workflow Runs

```
Repository → Actions → Terraform CI/CD
```

### Check Job Logs

Click on a workflow run to see:
- Job status
- Step-by-step output
- Error messages
- Terraform plan/apply results

### Download Artifacts

Some workflows may generate artifacts:
```
Jobs → Download artifacts
```

## 🔄 Manual Workflow Triggers

To manually trigger the workflow:

```bash
git push origin feature/terraform-infrastructure
```

Or use GitHub CLI:

```bash
gh workflow run terraform.yml --ref main
```

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Terraform GitHub Actions](https://registry.terraform.io/modules/hashicorp/setup-terraform/latest)
- [Snowflake Terraform Provider](https://registry.terraform.io/providers/Snowflake-Labs/snowflake/latest/docs)

---

**Last Updated**: August 29, 2026
