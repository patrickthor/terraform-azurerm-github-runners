# ==============================================================================
# Basic example — minimal module usage for consuming projects
#
# This shows the minimum configuration needed to deploy the runner platform.
# Copy this to your project and adjust the values.
# ==============================================================================

module "runners" {
  source = "github.com/patrickthor/github-runners//modules/runners?ref=v2.0.0"

  # Core naming — generates all resource names automatically
  workload    = "runner"
  environment = "prod"
  instance    = "001"
  location    = "westeurope"

  # GitHub configuration
  github_org  = "your-org"
  github_repo = "your-org/your-repo"

  # Key Vault secret names — these secrets must exist in the Key Vault
  # before the Function App can start. See README for setup instructions.
  github_app_id_secret_name              = "github-app-id"
  github_app_installation_id_secret_name = "github-app-installation-id"
  github_app_private_key_secret_name     = "github-app-private-key"

  # Optional: webhook signature validation
  # webhook_secret_secret_name = "github-webhook-secret"

  # Optional: grant Azure roles to runner identity (empty = least privilege)
  # runner_workload_roles = ["Contributor"]

  # Optional: tune runner sizing
  # cpu                  = 2
  # memory               = 4
  # runner_max_instances  = 10
  # runner_labels         = "azure,container-instance,self-hosted"
}

# ==============================================================================
# Outputs — useful for webhook setup and debugging
# ==============================================================================

output "function_app_hostname" {
  description = "Use this hostname to configure the GitHub webhook"
  value       = module.runners.function_app_default_hostname
}

output "resource_group_name" {
  value = module.runners.resource_group_name
}

output "acr_login_server" {
  description = "Push your runner image here"
  value       = module.runners.acr_login_server
}

output "key_vault_uri" {
  description = "Store GitHub App secrets here"
  value       = module.runners.key_vault_uri
}
