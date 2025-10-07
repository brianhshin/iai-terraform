terraform {
  required_providers {
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "1.0.3"
    }
  }
  backend "s3" {
    bucket = "iai-us-east-1"
    region = "us-east-1"
    key    = "iai-terraform/snowflake.tfstate"
  }
}

# providers
provider "snowflake" {
  alias             = "accountadmin"
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = "iai"
  password          = var.snowflake_password
  role              = "accountadmin"
}

provider "snowflake" {
  alias             = "useradmin"
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = "iai"
  password          = var.snowflake_password
  role              = "useradmin"
}

provider "snowflake" {
  alias             = "sysadmin"
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = "iai"
  password          = var.snowflake_password
  role              = "sysadmin"
}

# -----------------------------------------
# Warehouse, Database, Schemas
# -----------------------------------------
resource "snowflake_warehouse" "iai_svc_wh" {
  provider          = snowflake.accountadmin
  name              = "IAI_SVC_WH"
  warehouse_size    = "X-SMALL"
  warehouse_type    = "STANDARD"
  auto_suspend      = 60
  auto_resume       = true
}

resource "snowflake_database" "iai_home" {
  provider = snowflake.accountadmin
  name     = "IAI_HOME"
}

resource "snowflake_schema" "prod" {
  provider = snowflake.accountadmin
  name     = "PROD"
  database = snowflake_database.iai_home.name
}

resource "snowflake_schema" "util" {
  provider = snowflake.accountadmin
  name     = "UTIL"
  database = snowflake_database.iai_home.name
}

# -----------------------------------------
# Read role
# -----------------------------------------
resource "snowflake_account_role" "read_standard" {
  provider = snowflake.useradmin
  name     = "READ_STANDARD_ROLE"
}

# Grant the role broad read access
resource "snowflake_grant_privileges_to_account_role" "read_standard_database" {
  provider          = snowflake.accountadmin
  account_role_name = snowflake_account_role.read_standard.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.iai_home.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "read_standard_schema" {
  provider          = snowflake.accountadmin
  account_role_name = snowflake_account_role.read_standard.name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = snowflake_schema.prod.fully_qualified_name
  }
}

# Grant SELECT on all existing tables
resource "snowflake_grant_privileges_to_account_role" "read_standard_tables" {
  provider          = snowflake.accountadmin
  account_role_name = snowflake_account_role.read_standard.name
  privileges        = ["SELECT"]

  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.iai_home.name}\".\"${snowflake_schema.prod.name}\""
    }
  }
}

# Grant SELECT on all future tables
resource "snowflake_grant_privileges_to_account_role" "read_standard_future_tables" {
  provider          = snowflake.accountadmin
  account_role_name = snowflake_account_role.read_standard.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = "\"${snowflake_database.iai_home.name}\".\"${snowflake_schema.prod.name}\""
    }
  }
}

# -----------------------------------------
# Service user with default warehouse and role
# -----------------------------------------
resource "snowflake_service_user" "iai_svc_user" {
  provider          = snowflake.useradmin
  name              = "IAI_SVC_USER"
  email             = "iai.wps.lab@gmail.com"
  disabled          = false
  default_warehouse = snowflake_warehouse.iai_svc_wh.fully_qualified_name
  default_role      = snowflake_account_role.read_standard.fully_qualified_name
}

resource "snowflake_grant_account_role" "assign_read_role" {
  provider = snowflake.useradmin

  role_name = snowflake_account_role.read_standard.name
  user_name = snowflake_service_user.iai_svc_user.name
}