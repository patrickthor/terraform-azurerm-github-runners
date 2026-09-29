# No backend block — this example uses local state so it can be run as-is.
# Configure a remote backend in your own root module.

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"

      # The module floor is ">= 5.6.0" (first release with Service Bus API
      # 2026-01-01). A root module should pin tighter than the module it calls,
      # so the exact patch line is reproducible.
      version = "~> 5.7.0"
    }
  }
}

provider "azurerm" {
  features {}

  # subscription_id is read from the ARM_SUBSCRIPTION_ID environment variable:
  #   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
}
