# The Service Bus floor is deliberate: azurerm 5.6.0 moved the Service Bus
# resources to control-plane API 2026-01-01. Earlier 5.x builds use 2024-01-01,
# which can leave a Basic namespace in a Failed provisioning state whose
# server-populated properties then no longer match the create payload
# (CreateNamespacePayloadDiffersFromExistingNamespaceInFailedState on retry).
#
# No upper bound — the consuming root module owns the exact 5.x patch policy.

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.6.0"
    }
  }
}
