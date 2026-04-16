# 1. Configure the Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# 2. Create the Resource Group
resource "azurerm_resource_group" "rg_network" {
  name     = "rg-enterprise-network-eastus"
  location = "eastus"
}

# 3. Create the Central Hub Virtual Network
resource "azurerm_virtual_network" "hub_vnet" {
  name                = "vnet-hub-eastus"
  location            = azurerm_resource_group.rg_network.location
  resource_group_name = azurerm_resource_group.rg_network.name
  address_space       = ["10.0.0.0/16"]
}

# 4. Create the mandatory Azure Firewall Subnet
# WARNING: This name MUST be exactly "AzureFirewallSubnet" or the deployment will fail.
resource "azurerm_subnet" "firewall_subnet" {
  name                 = "AzureFirewallSubnet" 
  resource_group_name  = azurerm_resource_group.rg_network.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.1.0/26"] 
}

# 5. Create the Management Subnet (Mandatory for Basic SKU Firewall)
resource "azurerm_subnet" "firewall_management_subnet" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.rg_network.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["10.0.2.0/26"]
}

# 6. Pubklic IP for Standard Firewall Data Traffic
resource "azurerm_public_ip" "firewall_pip" {
  name                = "pip-firewall-eastus"
  location            = azurerm_resource_group.rg_network.location
  resource_group_name = azurerm_resource_group.rg_network.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 7. Public IP for Firewall Management Traffic
resource "azurerm_public_ip" "firewall_management_pip" {
  name                = "pip-firewall-mgmt-eastus"
  location            = azurerm_resource_group.rg_network.location
  resource_group_name = azurerm_resource_group.rg_network.name
  allocation_method   = "Static"
  sku = "Standard"
}

# 8. Azure Firewall (Basic Tier)
resource "azurerm_firewall" "hub_firewall" {
  name                = "fw-hub-eastus"
  location            = azurerm_resource_group.rg_network.location
  resource_group_name = azurerm_resource_group.rg_network.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"

  ip_configuration {
    name                 = "fw-data-config"
    subnet_id            = azurerm_subnet.firewall_subnet.id
    public_ip_address_id = azurerm_public_ip.firewall_pip.id
  }

  management_ip_configuration {
    name                 = "fw-mgmt-config"
    subnet_id            = azurerm_subnet.firewall_management_subnet.id
    public_ip_address_id = azurerm_public_ip.firewall_management_pip.id
  }
}

# 9 Production Spoke Virtual Network
resource "azurerm_virtual_network" "spoke_prod_vnet" {
  name                = "vnet-spoke-prod-eastus"
  location            = azurerm_resource_group.rg_network.location
  resource_group_name = azurerm_resource_group.rg_network.name
  address_space       = ["10.1.0.0/16"]
}

# 10. Create the Production Workload Subnet
resource "azurerm_subnet" "spoke_prod_subnet" {
  name                 = "snet-prod-eastus"
  resource_group_name  = azurerm_resource_group.rg_network.name
  virtual_network_name = azurerm_virtual_network.spoke_prod_vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}

# 11. Development Spoke Virtual Network
resource "azurerm_virtual_network" "spoke_dev_vnet" {
  name                = "vnet-spoke-dev-eastus"
  location            = azurerm_resource_group.rg_network.location
  resource_group_name = azurerm_resource_group.rg_network.name
  address_space       = ["10.2.0.0/16"]
}

# 12. Development Workload Subnet
resource "azurerm_subnet" "spoke_dev_subnet" {
  name                 = "snet-dev-eastus"
  resource_group_name  = azurerm_resource_group.rg_network.name
  virtual_network_name = azurerm_virtual_network.spoke_dev_vnet.name
  address_prefixes     = ["10.2.1.0/24"]
}

# 13. Peering: Hub to Production Spoke
resource "azurerm_virtual_network_peering" "hub_to_spoke_prod" {
  name                         = "peer-hub-to-prod"
  resource_group_name          = azurerm_resource_group.rg_network.name
  virtual_network_name         = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_prod_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# 14. Peering: Production Spoke to Hub
resource "azurerm_virtual_network_peering" "spoke_prod_to_hub" {
  name                         = "peer-prod-to-hub"
  resource_group_name          = azurerm_resource_group.rg_network.name
  virtual_network_name         = azurerm_virtual_network.spoke_prod_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.hub_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# 15. Peering: Hub to Development Spoke
resource "azurerm_virtual_network_peering" "hub_to_spoke_dev" {
  name                         = "peer-hub-to-dev"
  resource_group_name          = azurerm_resource_group.rg_network.name
  virtual_network_name         = azurerm_virtual_network.hub_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke_dev_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# 16. Peering: Development Spoke to Hub
resource "azurerm_virtual_network_peering" "spoke_dev_to_hub" {
  name                         = "peer-dev-to-hub"
  resource_group_name          = azurerm_resource_group.rg_network.name
  virtual_network_name         = azurerm_virtual_network.spoke_dev_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.hub_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# 17. Create Route Table
resource "azurerm_route_table" "spoke_route_table" {
  name                          = "rt-spokes-to-firewall"
  location                      = azurerm_resource_group.rg_network.location
  resource_group_name           = azurerm_resource_group.rg_network.name
  disable_bgp_route_propagation = false

  # The actual Route: Send EVERYTHING to the Firewall
  route {
    name                   = "route-all-traffic-to-fw"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.1.4" # exact firewall IP
  }
}

# 18. Associate Route Table with Production Subnet
resource "azurerm_subnet_route_table_association" "prod_subnet_rt_assoc" {
  subnet_id      = azurerm_subnet.spoke_prod_subnet.id
  route_table_id = azurerm_route_table.spoke_route_table.id
}

# 19. Associate Route Table with Development Subnet
resource "azurerm_subnet_route_table_association" "dev_subnet_rt_assoc" {
  subnet_id      = azurerm_subnet.spoke_dev_subnet.id
  route_table_id = azurerm_route_table.spoke_route_table.id
}

# 20. Network Interface for Production VM
resource "azurerm_network_interface" "prod_nic" {
  name                = "nic-prod-vm"
  location            = azurerm_resource_group.rg_network.location
  resource_group_name = azurerm_resource_group.rg_network.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.spoke_prod_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 21. Production Virtual Machine (Linux)
resource "azurerm_linux_virtual_machine" "prod_vm" {
  name                            = "vm-prod-spoke"
  resource_group_name             = azurerm_resource_group.rg_network.name
  location                        = azurerm_resource_group.rg_network.location
  size                            = "Standard_D2s_v3"
  admin_username                  = "azureadmin"
  admin_password                  = "SuperSecretPassword123!" # For lab testing only!
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.prod_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# 22. Network Interface for Development VM
resource "azurerm_network_interface" "dev_nic" {
  name                = "nic-dev-vm"
  location            = azurerm_resource_group.rg_network.location
  resource_group_name = azurerm_resource_group.rg_network.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.spoke_dev_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 23. Development Virtual Machine (Linux)
resource "azurerm_linux_virtual_machine" "dev_vm" {
  name                            = "vm-dev-spoke"
  resource_group_name             = azurerm_resource_group.rg_network.name
  location                        = azurerm_resource_group.rg_network.location
  size                            = "Standard_D2s_v3"
  admin_username                  = "azureadmin"
  admin_password                  = "SuperSecretPassword123!" # For lab testing only!
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.dev_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}