# No backend block — this example uses local state so it can be run as-is.
# Configure a remote backend in your own root module.

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.63"
    }
  }
}

provider "azurerm" {
  features {}

  # subscription_id is read from the ARM_SUBSCRIPTION_ID environment variable:
  #   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
}
