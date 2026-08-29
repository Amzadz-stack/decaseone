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
resource "snowflake_account_role" "decaseone_role" {
  name    = "DECASEONE_ROLE"
  comment = "Role for decaseone application"
}

# Grant database privileges to role
resource "snowflake_grant_privileges_to_account_role" "decaseone_db_grant" {
  account_role_name = snowflake_account_role.decaseone_role.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.decaseone.name
  }
}

# Grant schema privileges to role
resource "snowflake_grant_privileges_to_account_role" "decaseone_schema_grant" {
  account_role_name = snowflake_account_role.decaseone_role.name
  privileges        = ["USAGE"]
  on_schema {
    all_schemas_in_database = snowflake_database.decaseone.name # or specific schema scope below if needed
    # Alternatively, for a specific schema:
    # schema_name = "${snowflake_database.decaseone.name}.${snowflake_schema.public.name}"
  }
}

# Grant warehouse privileges to role
resource "snowflake_grant_privileges_to_account_role" "warehouse_grant" {
  account_role_name = snowflake_account_role.decaseone_role.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.compute.name
  }
}

# Example Table
resource "snowflake_table" "example_table" {
  database = snowflake_database.decaseone.name
  schema   = snowflake_schema.public.name
  name     = "EXAMPLE_TABLE"
  comment  = "Example table managed by Terraform"

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
resource "snowflake_grant_privileges_to_account_role" "example_table_grant" {
  account_role_name = snowflake_account_role.decaseone_role.name
  privileges        = ["SELECT"]
  on_schema_object {
    object_type = "TABLE"
    object_name = "${snowflake_database.decaseone.name}.${snowflake_schema.public.name}.${snowflake_table.example_table.name}"
  }
}
