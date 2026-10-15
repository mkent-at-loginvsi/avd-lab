resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  vnet_address_space    = "10.70.0.0/16"
  subnet_address_prefix = "10.70.1.0/24"

  # Same cloud-init shape as LoginVSI's vSphere example (Appliance-Terraform-vSphere-Example),
  # minus the static-IP step: Azure hands out the address via DHCP.
  userdata = templatefile("${path.module}/templates/userdata.yml", {
    adminpassword = base64encode(var.appliance_admin_password)
    domainname    = var.appliance_domain_name
  })
}

resource "azurerm_resource_group" "lab" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-leappliance-${random_id.suffix.hex}"
  location = var.location
  tags     = var.labmgr_tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  resource_group_name     = var.create_resource_group ? azurerm_resource_group.lab[0].name : data.azurerm_resource_group.existing[0].name
  resource_group_location = var.create_resource_group ? azurerm_resource_group.lab[0].location : data.azurerm_resource_group.existing[0].location
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-leappliance-${random_id.suffix.hex}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  address_space       = [local.vnet_address_space]
  tags                = var.labmgr_tags
}

resource "azurerm_subnet" "lab" {
  name                 = "snet-leappliance"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [local.subnet_address_prefix]
}

resource "azurerm_network_security_group" "lab" {
  name                = "nsg-leappliance-${random_id.suffix.hex}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  tags                = var.labmgr_tags

  security_rule {
    name                       = "AllowHTTPSFromAdmin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSHFromAdmin"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "lab" {
  subnet_id                 = azurerm_subnet.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}

resource "azurerm_public_ip" "appliance" {
  name                = "pip-leappliance-${random_id.suffix.hex}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.labmgr_tags
}

resource "azurerm_network_interface" "appliance" {
  name                = "nic-leappliance-${random_id.suffix.hex}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  tags                = var.labmgr_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.appliance.id
  }
}

# Storage for the VHD. The blob is copied server-side by Azure straight from
# vhd_source_url, so nothing is downloaded to or uploaded from the machine
# running Terraform. It must be a page blob to be usable as an image source.
resource "azurerm_storage_account" "vhd" {
  name                     = "stleapp${random_id.suffix.hex}"
  location                 = local.resource_group_location
  resource_group_name      = local.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.labmgr_tags
}

resource "azurerm_storage_container" "vhd" {
  name                  = "vhds"
  storage_account_name  = azurerm_storage_account.vhd.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "appliance_vhd" {
  name                   = "LoginEnterprise.vhd"
  storage_account_name   = azurerm_storage_account.vhd.name
  storage_container_name = azurerm_storage_container.vhd.name
  type                   = "Page"
  source_uri             = var.vhd_source_url
}

# Managed image built from the copied VHD. The appliance is Linux and
# Hyper-V Generation 1 only (Gen 2 is not supported).
resource "azurerm_image" "appliance" {
  name                = "img-leappliance-${random_id.suffix.hex}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  hyper_v_generation  = "V1"
  tags                = var.labmgr_tags

  os_disk {
    os_type  = "Linux"
    os_state = "Generalized"
    blob_uri = azurerm_storage_blob.appliance_vhd.url
    caching  = "ReadWrite"
  }
}

resource "azurerm_linux_virtual_machine" "appliance" {
  name                            = "vm-leappliance"
  computer_name                   = "leappliance"
  location                        = local.resource_group_location
  resource_group_name             = local.resource_group_name
  size                            = var.vm_size
  admin_username                  = var.vm_admin_username
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.appliance.id]
  source_image_id                 = azurerm_image.appliance.id
  custom_data                     = base64encode(local.userdata)
  tags                            = var.labmgr_tags

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 128
  }
}
