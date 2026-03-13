# ==============================================================================
# Root outputs — pass through from module
# ==============================================================================

output "resource_group_name" {
  description = "The resource group name (created or referenced)"
  value       = module.runners.resource_group_name
}

output "acr_login_server" {
  description = "The login server URL for the Azure Container Registry"
  value       = module.runners.acr_login_server
}

output "acr_id" {
  description = "The ID of the Azure Container Registry"
  value       = module.runners.acr_id
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = module.runners.key_vault_uri
}

output "key_vault_id" {
  description = "The ID of the Key Vault"
  value       = module.runners.key_vault_id
}

output "function_app_name" {
  description = "Event-driven scaler Function App name"
  value       = module.runners.function_app_name
}

output "function_app_default_hostname" {
  description = "Default hostname of scaler Function App"
  value       = module.runners.function_app_default_hostname
}

output "servicebus_namespace_name" {
  description = "Service Bus namespace name used for scale events"
  value       = module.runners.servicebus_namespace_name
}

output "servicebus_queue_name" {
  description = "Service Bus queue name used for scale requests"
  value       = module.runners.servicebus_queue_name
}

output "runner_pull_identity" {
  description = "User-assigned identity used by ACI runners for ACR pull"
  value       = module.runners.runner_pull_identity
}

output "scaler_identity_principal_id" {
  description = "System-assigned principal ID for scaler Function App"
  value       = module.runners.scaler_identity_principal_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID used for diagnostics"
  value       = module.runners.log_analytics_workspace_id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = module.runners.application_insights_connection_string
  sensitive   = true
}
