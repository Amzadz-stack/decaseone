# Database Outputs
output "database_name" {
  description = "Name of the created Snowflake database"
  value       = snowflake_database.decaseone.name
}

output "database_id" {
  description = "ID of the created Snowflake database"
  value       = snowflake_database.decaseone.id
}

# Schema Outputs
output "schema_name" {
  description = "Name of the created schema"
  value       = snowflake_schema.public.name
}

# Warehouse Outputs
output "warehouse_name" {
  description = "Name of the compute warehouse"
  value       = snowflake_warehouse.compute.name
}

output "warehouse_id" {
  description = "ID of the compute warehouse"
  value       = snowflake_warehouse.compute.id
}

# Role Outputs
output "role_name" {
  description = "Name of the created role"
  value       = snowflake_role.decaseone_role.name
}

# Table Outputs
output "example_table_name" {
  description = "Name of the example table"
  value       = snowflake_table.example_table.name
}

output "example_table_id" {
  description = "ID of the example table"
  value       = snowflake_table.example_table.id
}

# Connection Info
output "connection_info" {
  description = "Connection information for Snowflake"
  value = {
    account   = var.snowflake_account
    database  = snowflake_database.decaseone.name
    schema    = snowflake_schema.public.name
    warehouse = snowflake_warehouse.compute.name
    role      = snowflake_role.decaseone_role.name
  }
  sensitive = true
}
