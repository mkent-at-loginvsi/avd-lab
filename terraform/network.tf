resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  vnet_address_space    = "10.60.0.0/16"
  subnet_address_prefix = "10.60.1.0/24"
  dc_private_ip         = cidrhost(local.subnet_address_prefix, 4)
  session_host_ips      = [for i in range(var.session_host_count) : cidrhost(local.subnet_address_prefix, 10 + i)]
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-avdlab-${random_id.suffix.hex}"
  location = var.location
  tags     = var.labmgr_tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-avdlab-${random_id.suffix.hex}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [local.vnet_address_space]
  dns_servers         = [local.dc_private_ip]
  tags                = var.labmgr_tags
}

resource "azurerm_subnet" "lab" {
  name                 = "snet-avdlab"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [local.subnet_address_prefix]
}

resource "azurerm_network_security_group" "lab" {
  name                = "nsg-avdlab-${random_id.suffix.hex}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.labmgr_tags

  security_rule {
    name                       = "AllowRDPFromAdmin"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowWinRMFromAdmin"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985"
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "lab" {
  subnet_id                 = azurerm_subnet.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}
