output "storage_account_name" {
  description = "Name of the Terraform-state storage account."
  value       = local.storage_account_name
}

output "resource_group_name" {
  description = "Resource group containing the state storage account."
  value       = var.resource_group_name
}

output "container_name" {
  description = "Blob container holding state files."
  value       = azurerm_storage_container.tfstate.name
}

# Pretty-print snippet ready to paste into backend.hcl
output "backend_hcl_snippet" {
  description = "Copy-paste this block into backend.hcl at the repo root."
  value       = <<-EOT
    resource_group_name  = "${var.resource_group_name}"
    storage_account_name = "${local.storage_account_name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    key                  = "github-runners.tfstate"
    use_azuread_auth     = true
  EOT
}
