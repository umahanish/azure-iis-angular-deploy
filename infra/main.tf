# ---------------------------------------------------------------------------
# Resource Group (for the new VM / NIC / public IP / NSG)
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# ---------------------------------------------------------------------------
# EXISTING Storage Account — script is uploaded here
# ---------------------------------------------------------------------------
data "azurerm_storage_account" "existing" {
  name                = var.existing_storage_account_name
  resource_group_name = var.existing_storage_account_rg
}

resource "azurerm_storage_container" "scripts" {
  name                  = var.container_name
  storage_account_name  = data.azurerm_storage_account.existing.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "iis_script" {
  name                   = "IIS.ps1"
  storage_account_name   = data.azurerm_storage_account.existing.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = var.script_local_path
  content_md5            = filemd5(var.script_local_path)
}

# ---------------------------------------------------------------------------
# EXISTING VNet / Subnet — VM's NIC is attached here
# ---------------------------------------------------------------------------
data "azurerm_virtual_network" "existing" {
  name                = var.existing_vnet_name
  resource_group_name = var.existing_vnet_rg
}

data "azurerm_subnet" "existing" {
  name                 = var.existing_subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing.name
  resource_group_name  = var.existing_vnet_rg
}

# ---------------------------------------------------------------------------
# NSG — allows inbound HTTP (80); RDP (3389) optional for management
# ---------------------------------------------------------------------------
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.allowed_rdp_source != "" ? [1] : []
    content {
      name                       = "Allow-RDP"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = var.allowed_rdp_source
      destination_address_prefix = "*"
    }
  }
}

# ---------------------------------------------------------------------------
# Public IP
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "pip" {
  name                = "${var.prefix}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ---------------------------------------------------------------------------
# NIC — attached to the EXISTING subnet, with the new public IP + NSG
# ---------------------------------------------------------------------------
resource "azurerm_network_interface" "nic" {
  name                = "${var.prefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = data.azurerm_subnet.existing.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ---------------------------------------------------------------------------
# Windows VM
# ---------------------------------------------------------------------------
resource "azurerm_windows_virtual_machine" "vm" {
  name                = "${var.prefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

# ---------------------------------------------------------------------------
# Custom Script Extension: pulls IIS.ps1 from the existing storage account
# and runs it to install/configure IIS
# ---------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "install_iis" {
  name                       = "install-iis"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    fileUris = [
      "https://${data.azurerm_storage_account.existing.name}.blob.core.windows.net/${azurerm_storage_container.scripts.name}/${azurerm_storage_blob.iis_script.name}"
    ]
  })

  protected_settings = jsonencode({
    storageAccountName = data.azurerm_storage_account.existing.name
    storageAccountKey  = data.azurerm_storage_account.existing.primary_access_key
    commandToExecute   = "powershell -ExecutionPolicy Unrestricted -File IIS.ps1"
  })

  depends_on = [azurerm_storage_blob.iis_script]
}

# ---------------------------------------------------------------------------
# Health check: curl the site after the extension finishes and record the
# result so it can be surfaced as a Terraform output.
# Requires `curl` on the machine running `terraform apply` (Linux/macOS/WSL).
# ---------------------------------------------------------------------------
resource "null_resource" "wait_for_iis" {
  depends_on = [azurerm_virtual_machine_extension.install_iis]

  triggers = {
    public_ip = azurerm_public_ip.pip.ip_address
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      URL="http://${azurerm_public_ip.pip.ip_address}"
      echo "Checking $URL ..."
      STATUS="000"
      for i in $(seq 1 ${var.health_check_retries}); do
        STATUS=$(curl -s -o /dev/null -w "%%{http_code}" --max-time 10 "$URL" || echo "000")
        if [ "$STATUS" = "200" ]; then
          echo "OK: $URL responded HTTP $STATUS (attempt $i/${var.health_check_retries})" > "${path.module}/iis_health_check.txt"
          exit 0
        fi
        echo "Attempt $i/${var.health_check_retries}: HTTP $STATUS, retrying in ${var.health_check_interval_seconds}s..."
        sleep ${var.health_check_interval_seconds}
      done
      echo "FAILED: $URL did not return HTTP 200 after ${var.health_check_retries} attempts (last status: $STATUS)" > "${path.module}/iis_health_check.txt"
    EOT
  }
}

data "local_file" "iis_health_check" {
  filename   = "${path.module}/iis_health_check.txt"
  depends_on = [null_resource.wait_for_iis]
}
