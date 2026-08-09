output "vm_public_ip" {
  description = "Public IP address of the IIS VM."
  value       = azurerm_public_ip.pip.ip_address
}

output "vm_site_url" {
  description = "URL to browse to once IIS has been provisioned."
  value       = "http://${azurerm_public_ip.pip.ip_address}"
}

output "storage_account_name" {
  description = "Existing storage account hosting IIS.ps1."
  value       = data.azurerm_storage_account.existing.name
}

output "script_blob_url" {
  description = "URL of the uploaded IIS.ps1 script in blob storage."
  value       = "https://${data.azurerm_storage_account.existing.name}.blob.core.windows.net/${azurerm_storage_container.scripts.name}/${azurerm_storage_blob.iis_script.name}"
}

output "iis_health_check" {
  description = "Result of curling the site URL after deployment — OK/FAILED plus HTTP status."
  value       = data.local_file.iis_health_check.content
}
