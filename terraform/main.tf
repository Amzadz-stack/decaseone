# -----------------------------------------------------------------------------
# Main Terraform Configuration
# Entry point for the Trade Pipeline IaC
# -----------------------------------------------------------------------------

locals {
  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = "trade-pipeline"
    }
  )

  # Fully qualified references used across resources
  fqn_database  = var.database_name
  fqn_schema    = var.schema_name
  fqn_warehouse = var.snowflake_warehouse
}
