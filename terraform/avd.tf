resource "azurerm_virtual_desktop_host_pool" "lab" {
  name                     = "hp-avdlab-${random_id.suffix.hex}"
  location                 = azurerm_resource_group.lab.location
  resource_group_name      = azurerm_resource_group.lab.name
  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = 10
  validate_environment     = false
  start_vm_on_connect      = false
  tags                     = var.labmgr_tags
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "lab" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.lab.id
  expiration_date = timeadd(timestamp(), "24h")
}

resource "azurerm_virtual_desktop_application_group" "desktop" {
  name                = "dag-avdlab-${random_id.suffix.hex}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  type                = "Desktop"
  host_pool_id        = azurerm_virtual_desktop_host_pool.lab.id
  friendly_name       = "AVD Lab Desktop"
  tags                = var.labmgr_tags
}

resource "azurerm_virtual_desktop_workspace" "lab" {
  name                = "ws-avdlab-${random_id.suffix.hex}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  friendly_name       = "AVD Lab"
  tags                = var.labmgr_tags
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "lab" {
  workspace_id         = azurerm_virtual_desktop_workspace.lab.id
  application_group_id = azurerm_virtual_desktop_application_group.desktop.id
}

resource "azurerm_role_assignment" "avd_user" {
  count                = var.avd_user_object_id != "" ? 1 : 0
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = var.avd_user_object_id
}
