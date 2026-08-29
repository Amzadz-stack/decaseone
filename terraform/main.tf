# Main Terraform Configuration
# This file serves as the entry point for Terraform configuration

locals {
  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = "decaseone"
    }
  )
}
