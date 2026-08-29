terraform {
  required_version = ">= 1.0"
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.89"
    }
  }

  # Uncomment below for remote state management with S3
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "decaseone/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "snowflake" {
  account             = var.snowflake_account
  user                = var.snowflake_user
  password            = var.snowflake_password
  role                = var.snowflake_role
  warehouse           = var.snowflake_warehouse
  database            = var.snowflake_database
  schema              = var.snowflake_schema
  authenticator       = var.snowflake_authenticator
  client_trace_level  = var.snowflake_client_trace_level
  log_level           = var.snowflake_log_level
}
