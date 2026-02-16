# --- SQL Server 1 ---

resource "azurerm_mssql_server" "sql" {
  name                         = "${var.resource_name_prefix}-sql"
  resource_group_name          = azurerm_resource_group.this.name
  location                     = azurerm_resource_group.this.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password

  tags = {
    SecurityControl = "Ignore"
  }
}

resource "azurerm_mssql_firewall_rule" "sql_allow_azure" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# --- SQL Server 2 ---

resource "azurerm_mssql_server" "sql2" {
  name                         = "${var.resource_name_prefix}-sql2"
  resource_group_name          = azurerm_resource_group.this.name
  location                     = azurerm_resource_group.this.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password

  tags = {
    SecurityControl = "Ignore"
  }
}

resource "azurerm_mssql_firewall_rule" "sql2_allow_azure" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.sql2.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
