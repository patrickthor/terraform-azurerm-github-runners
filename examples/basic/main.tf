# ==============================================================================
# Basic example — minimal module usage
#
# Nine inputs is all the module needs. Every resource name is generated from
# workload/environment/instance using Azure CAF conventions.
#
# This example uses local state and literal values so it stays readable. For a
# production-shaped setup with remote state and CI/CD, see:
#   https://github.com/patrickthor/github-runner-customer-demo
# ==============================================================================

module "runners" {
  source = "github.com/patrickthor/terraform-azurerm-github-runners//modules/runners?ref=v3.0.8"

  # Core naming
  workload    = "runner"
  environment = "dev"
  instance    = "001"
  location    = "westeurope"

  # GitHub configuration
  github_org  = "your-org"
  github_repo = "your-org/your-repo"

  # Key Vault secret names — the secrets themselves are created out-of-band,
  # after the first apply. See the module README.
  github_app_id_secret_name              = "github-app-id"
  github_app_installation_id_secret_name = "github-app-installation-id"
  github_app_private_key_secret_name     = "github-app-private-key"
}

# ==============================================================================
# Outputs — needed to deploy the scaler function and register the webhook
# ==============================================================================

output "resource_group_name" {
  description = "Resource group holding the runner platform"
  value       = module.runners.resource_group_name
}

output "function_app_name" {
  description = "Function App name — target for the scaler code deployment"
  value       = module.runners.function_app_name
}

output "function_app_default_hostname" {
  description = "Use this hostname to build the GitHub webhook payload URL"
  value       = module.runners.function_app_default_hostname
}

output "acr_login_server" {
  description = "Import or push the actions-runner image here"
  value       = module.runners.acr_login_server
}

output "key_vault_uri" {
  description = "Store the GitHub App secrets here"
  value       = module.runners.key_vault_uri
}
