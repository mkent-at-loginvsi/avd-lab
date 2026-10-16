resource "azurerm_virtual_desktop_host_pool" "lab" {
  name                     = "hp-avdlab-${random_id.suffix.hex}"
  location                 = azurerm_resource_group.lab.location
  resource_group_name      = azurerm_resource_group.lab.name
  type                     = "Pooled"
  load_balancer_type       = "BreadthFirst"
  maximum_sessions_allowed = 10
  validate_environment     = false
  # Users assigned to both the desktop and a RemoteApp group only see the type chosen here.
  preferred_app_group_type = var.preferred_app_group_type != "" ? var.preferred_app_group_type : (length(local.remote_apps) > 0 ? "RailApplications" : "Desktop")
  start_vm_on_connect      = false
  # Entra-join: single sign-on to the Entra-joined host. Domain-joined: no SSO, so the user gets
  # the Windows Security prompt and signs in with their AD credentials.
  custom_rdp_properties = var.deploy_domain_controller ? "enablecredsspsupport:i:1;" : "targetisaadjoined:i:1;enablerdsaadauth:i:1;"
  tags                  = var.labmgr_tags
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

# RemoteApps: a second application group on the same host pool, registered with the same
# workspace. The apps must already be installed on the session hosts at the given paths.
locals {
  # Application resource names allow only letters, digits and hyphens here; the display name is kept as given.
  remote_apps = { for name, app in var.remote_apps : replace(name, "/[^A-Za-z0-9]+/", "-") => { friendly_name = name, path = app.path, arguments = app.arguments, icon_path = app.icon_path, icon_index = app.icon_index } }
}

resource "azurerm_virtual_desktop_application_group" "remoteapp" {
  count               = length(local.remote_apps) > 0 ? 1 : 0
  name                = "rag-avdlab-${random_id.suffix.hex}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  type                = "RemoteApp"
  host_pool_id        = azurerm_virtual_desktop_host_pool.lab.id
  friendly_name       = "AVD Lab Apps"
  tags                = var.labmgr_tags
}

resource "azurerm_virtual_desktop_application" "app" {
  for_each                     = local.remote_apps
  name                         = each.key
  application_group_id         = azurerm_virtual_desktop_application_group.remoteapp[0].id
  friendly_name                = each.value.friendly_name
  path                         = each.value.path
  icon_path                    = each.value.icon_path != "" ? each.value.icon_path : each.value.path
  icon_index                   = each.value.icon_index
  command_line_argument_policy = each.value.arguments != "" ? "Require" : "DoNotAllow"
  command_line_arguments       = each.value.arguments != "" ? each.value.arguments : null
  show_in_portal               = true
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "remoteapp" {
  count                = length(local.remote_apps) > 0 ? 1 : 0
  workspace_id         = azurerm_virtual_desktop_workspace.lab.id
  application_group_id = azurerm_virtual_desktop_application_group.remoteapp[0].id
}
