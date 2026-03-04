terraform {
  required_version = ">= 1.0"

  # Partial backend — supply the remaining values with:
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example for the required keys.
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.55"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
