# Database Resource
resource "snowflake_database" "decaseone" {
  name                        = var.database_name
  comment                     = "Database managed by Terraform for decaseone project"
  data_retention_time_in_days = 1
}

# Schema Resource
resource "snowflake_schema" "public" {
  name                        = var.schema_name
  database                    = snowflake_database.decaseone.name
  comment                     = "Public schema for decaseone"
  data_retention_time_in_days = 1
  is_managed                  = false
}

# Warehouse for computation
resource "snowflake_warehouse" "compute" {
  name           = "COMPUTE_WH"
  warehouse_size = "XSMALL"
  comment        = "Compute warehouse for decaseone"
  auto_suspend   = 10
  auto_resume    = true
}

# Role for data access
resource "snowflake_role" "decaseone_role" {
  name    = "DECASEONE_ROLE"
  comment = "Role for decaseone application"
}

# Grant database privileges to role
resource "snowflake_database_grant" "decaseone_db_grant" {
  database_name = snowflake_database.decaseone.name
  privilege     = "USAGE"
  roles         = [snowflake_role.decaseone_role.name]
}

# Grant schema privileges to role
resource "snowflake_schema_grant" "decaseone_schema_grant" {
  database_name = snowflake_database.decaseone.name
  schema_name   = snowflake_schema.public.name
  privilege     = "USAGE"
  roles         = [snowflake_role.decaseone_role.name]
}

# Grant warehouse privileges to role
resource "snowflake_warehouse_grant" "warehouse_grant" {
  warehouse_name = snowflake_warehouse.compute.name
  privilege      = "USAGE"
  roles          = [snowflake_role.decaseone_role.name]
}

# Example Table (update this based on your DDL)
resource "snowflake_table" "example_table" {
  database  = snowflake_database.decaseone.name
  schema    = snowflake_schema.public.name
  name      = "EXAMPLE_TABLE"
  comment   = "Example table managed by Terraform"

  column {
    name    = "ID"
    type    = "NUMBER(38,0)"
    comment = "Primary identifier"
  }

  column {
    name    = "NAME"
    type    = "VARCHAR(255)"
    comment = "Entity name"
  }

  column {
    name    = "CREATED_AT"
    type    = "TIMESTAMP_NTZ"
    comment = "Record creation timestamp"
  }

  column {
    name    = "UPDATED_AT"
    type    = "TIMESTAMP_NTZ"
    comment = "Record update timestamp"
  }
}

# Grant table privileges to role
resource "snowflake_table_grant" "example_table_grant" {
  database_name = snowflake_database.decaseone.name
  schema_name   = snowflake_schema.public.name
  table_name    = snowflake_table.example_table.name
  privilege     = "SELECT"
  roles         = [snowflake_role.decaseone_role.name]
}
