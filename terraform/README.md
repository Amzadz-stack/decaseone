# Terraform — Trade Pipeline Infrastructure

Provisions all 22 Snowflake objects for the Trade Data Engineering Pipeline using the [Snowflake Terraform Provider](https://app.snowflake.com).

## Resources Managed

| Type | Count | Objects |
| :--- | :--- | :--- |
| Tables | 4 | `TRADE_EVENTS_RAW` , `TRADES_VALID` , `TRADES_REJECTED` , `PIPELINE_RUN_LOG` |
| Stage | 1 | `TRADE_INGEST_STAGE` |
| File Format | 1 | `TRADE_JSON_FF` |
| Stream | 1 | `TRADE_EVENTS_STREAM` (append-only CDC) |
| Procedures | 3 | `PROCESS_TRADE_EVENTS` , `LOAD_TRADES_FROM_STAGE` , `EXPIRE_STALE_TRADES` |
| Tasks | 3 | `TASK_LOAD_FROM_STAGE` $\rightarrow$ `TASK_PROCESS_TRADES` $\rightarrow$ `TASK_EXPIRE_TRADES` |
| Alerts | 3 | Pipeline failure, high rejection rate, stalled pipeline |
| Views | 3 | `V_TRADE_BOOK_SUMMARY` , `V_REJECTION_SUMMARY` , `V_PIPELINE_HEALTH` |

## Prerequisites

* Terraform >= 1.0
* Snowflake account with a role that can create tables, procedures, tasks, alerts, and views.
* Notification integration created by ACCOUNTADMIN (for alerts):

```sql
CREATE OR REPLACE NOTIFICATION INTEGRATION TRADE_PIPELINE_EMAIL_NI
  TYPE = EMAIL ENABLED = TRUE;
GRANT USAGE ON INTEGRATION TRADE_PIPELINE_EMAIL_NI TO ROLE <your_role>;

## Quick Start

Quick cd terraform

# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Snowflake connection details

# 2. Set password via environment variable (don't put in tfvars)
export TF_VAR_snowflake_password="your_password"

# 3. Initialize Terraform
terraform init

# 4. Preview changes
terraform plan

# 5. Apply
terraform apply 

terraform/
├── .gitignore              # Ignores .terraform/, *.tfstate, terraform.tfvars
├── providers.tf            # Snowflake provider config + optional S3 backend
├── main.tf                 # Locals (tags, FQN references)
├── variables.tf            # Input variables (connection + pipeline config)
├── snowflake.tf            # All 22 Snowflake resources
├── outputs.tf              # Object names grouped by type
├── terraform.tfvars.example # Template – copy to terraform.tfvars
└── README.md               # This file


| Variable | Required | Description |
| :--- | :--- | :--- |
| `snowflake_account` | Yes | Account identifier |
| `snowflake_user` | Yes | Username |
| `snowflake_password` | Yes | Password (use `TF_VAR_snowflake_password`) |
| `snowflake_role` | Yes | Role for object creation |
| `snowflake_warehouse` | Yes | Warehouse for tasks and alerts |
| `database_name` | Yes | Target database |
| `schema_name` | Yes | Target schema |
| `notification_integration_name` | No | Email integration (default: `TRADE_PIPELINE_EMAIL_NI`) |
| `alert_email_recipients` | No | Alert email address |
| `environment` | No | Environment tag (default: `dev`) |


Destroy
to remove all pip lines objects 

terraform destroy


Notes
 State management: By default, state is stored locally. Uncomment the S3 backend block in ⁠providers.tf⁠ for remote state in production.
 Sensitive values: ⁠terraform.tfvars⁠ is in ⁠.gitignore⁠ — never commit real credentials. Use ⁠terraform.tfvars.example⁠ as a template.
 Alerts require ACCOUNTADMIN setup: The notification integration must exist before ⁠terraform apply⁠. Alerts will fail to create without it.
 Tasks start immediately: Tasks are created with ⁠enabled = true⁠. They will begin executing on schedule after apply.



