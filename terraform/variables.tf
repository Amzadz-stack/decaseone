# Snowflake Connection Variables
variable "snowflake_account" {
  description = "Snowflake account identifier"
  type        = string
  sensitive   = true
}

variable "snowflake_user" {
  description = "Snowflake username"
  type        = string
  sensitive   = true
}

variable "snowflake_password" {
  description = "Snowflake password"
  type        = string
  sensitive   = true
}

variable "snowflake_role" {
  description = "Snowflake role to use"
  type        = string
  default     = "SYSADMIN"
}

variable "snowflake_warehouse" {
  description = "Snowflake warehouse to use"
  type        = string
  default     = "COMPUTE_WH"
}

variable "snowflake_database" {
  description = "Snowflake database"
  type        = string
  default     = ""
}

variable "snowflake_schema" {
  description = "Snowflake schema"
  type        = string
  default     = ""
}

variable "snowflake_authenticator" {
  description = "Snowflake authenticator URL"
  type        = string
  default     = ""
}

variable "snowflake_client_trace_level" {
  description = "Client trace level (OFF, ON, DEBUG)"
  type        = string
  default     = "OFF"
}

variable "snowflake_log_level" {
  description = "Log level (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
}

# Database Resources Variables
variable "database_name" {
  description = "Name of the Snowflake database"
  type        = string
  default     = "DECASEONE_DB"
}

variable "schema_name" {
  description = "Name of the Snowflake schema"
  type        = string
  default     = "PUBLIC"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Project     = "decaseone"
  }
}
