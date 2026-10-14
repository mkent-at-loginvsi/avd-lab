# Entra ID identities that can sign in to AVD (web client / Windows App): cloud-only test users in
# Entra-join mode, or AD users synced by Cloud Sync when deploy_domain_controller is true.

data "azuread_domains" "initial" {
  only_initial = true
}

locals {
  # Cloud-only users are created only in Entra-join mode. With the domain controller the
  # users live in AD and are synced to Entra by Cloud Sync (see ansible/cloudsync.yml).
  create_cloud_users = !var.deploy_domain_controller
  entra_domain       = data.azuread_domains.initial.domains[0].domain_name
  test_users = {
    for i in range(var.test_user_count) :
    format("testuser%02d", i + 1) => format("testuser%02d@%s", i + 1, local.entra_domain)
  }
}

resource "azuread_group" "session_desktop" {
  display_name     = "SessionDesktop-${random_id.suffix.hex}"
  description      = "AVD lab test users"
  security_enabled = true
}

resource "azuread_user" "test" {
  for_each              = local.create_cloud_users ? local.test_users : {}
  user_principal_name   = each.value
  display_name          = each.key
  mail_nickname         = each.key
  password              = var.test_user_password
  force_password_change = false
}

resource "azuread_group_member" "test" {
  for_each         = azuread_user.test
  group_object_id  = azuread_group.session_desktop.object_id
  member_object_id = each.value.object_id
}

# The group may launch the published desktop and sign in to the Entra-joined VMs.
resource "azurerm_role_assignment" "group_desktop" {
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = azuread_group.session_desktop.object_id
}

resource "azurerm_role_assignment" "group_vm_login" {
  count                = local.create_cloud_users ? 1 : 0
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = azuread_group.session_desktop.object_id
}

# Optional extra user or group (e.g. yourself).
resource "azurerm_role_assignment" "avd_user" {
  count                = var.avd_user_object_id != "" ? 1 : 0
  scope                = azurerm_virtual_desktop_application_group.desktop.id
  role_definition_name = "Desktop Virtualization User"
  principal_id         = var.avd_user_object_id
}

resource "azurerm_role_assignment" "avd_user_vm_login" {
  count                = var.avd_user_object_id != "" && local.create_cloud_users ? 1 : 0
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Virtual Machine User Login"
  principal_id         = var.avd_user_object_id
}
