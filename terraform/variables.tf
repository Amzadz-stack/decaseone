Based on your request to merge the first file up to line 62 and then continue picking the remaining variables from the second file into a single .tf format, here is the combined Terraform variables file.
# Trade Pipeline — Terraform Variables
# — Snowflake Connection ————————————————————————————————

variable "snowflake_account" {
  description = "Snowflake account identifier"
  type        = string
}

variable "snowflake_user" {
  description = "Snowflake username for Terraform"
  type        = string
}

variable "snowflake_password" {
  description = "Snowflake password (use env var TF_VAR_snowflake_password)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "snowflake_role" {
  description = "Snowflake role for object creation"
  type        = string
}

variable "snowflake_warehouse" {
  description = "Snowflake warehouse for task execution"
  type        = string
}

variable "snowflake_authenticator" {
  description = "Authentication method (snowflake, externalbrowser, etc.)"
  type        = string
  default     = "snowflake"
}

# — Target Environment ——————————————————————————————————

variable "database_name" {
  description = "Database where pipeline objects are created"
  type        = string
}

variable "schema_name" {
  description = "Schema where pipeline objects are created"
  type        = string
}

# — Pipeline Configuration ——————————————————————————————

variable "notification_integration_name" {
  description = "Email notification integration name (created by ACCOUNTADMIN)"
  type        = string
  default     = "TRADE_PIPELINE_EMAIL_NI"
}

variable "alert_email_recipients" {
  description = "Email address(es) for alert notifications"
  type        = string
  default     = "ops-team@yourcompany.com"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}

