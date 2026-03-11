---
inclusion: auto
---

# Technology Stack

## Infrastructure as Code

- Terraform >= 1.3
- AzureRM provider ~> 4.55
- Remote state backend on Azure Storage (azurerm backend)
- Bootstrap module for state storage provisioning

## Azure Services

- Azure Functions (Consumption Y1 Linux)
- Azure Container Instances (ACI)
- Azure Container Registry (ACR)
- Azure Service Bus (Basic SKU)
- Azure Key Vault (RBAC-enabled)
- Azure Storage (state + function runtime)
- Application Insights (telemetry)
- Managed Identities (system + user-assigned)

## Function App Runtime

- Python 3.11
- Azure Functions Core Tools v4
- Dependencies:
  - azure-functions
  - azure-identity >= 1.16.0
  - azure-servicebus >= 7.12.0
  - requests >= 2.31.0
  - PyJWT[crypto] >= 2.8.0

## Authentication

- GitHub App (not PAT) with repository Administration + Actions permissions
- Azure OIDC federation for CI/CD (no secrets in GitHub)
- Managed identities for all Azure resource access
- Key Vault references for sensitive Function App settings

## Common Commands

### Terraform Operations

```bash
# Initialize with remote backend
terraform init -backend-config=backend.hcl

# Plan changes
terraform plan -var-file=terraform.tfvars

# Apply infrastructure
terraform apply -var-file=terraform.tfvars

# View outputs
terraform output
```

### Bootstrap (one-time state storage setup)

```bash
cd bootstrap
terraform init
terraform apply -var-file=terraform.tfvars
```

### Function Deployment

```bash
cd scaler-function
func azure functionapp publish <function-app-name> --python --build remote
```

### Azure CLI Helpers

```bash
# Get function key for webhook URL
az functionapp function keys list \
  --resource-group <rg> \
  --name <function-app-name> \
  --function-name github_webhook \
  --query default -o tsv

# Store GitHub App secrets in Key Vault
az keyvault secret set --vault-name <kv-name> \
  --name <secret-name> --value "<value>"

# List running ACI instances
az container list --resource-group <rg> --output table
```

## CI/CD

GitHub Actions workflows:
- `bootstrap.yml`: Provision state storage (manual trigger)
- `deploy.yml`: Terraform apply + Function publish (on push to main)
- `release.yml`: Semantic versioning + GitHub Release

## Naming Conventions

All resources follow Azure CAF patterns:
- Resource groups: `rg-{workload}-{env}-{instance}`
- Storage accounts: `st{workload}{env}{instance}` (alphanumeric only)
- Container registries: `cr{workload}{env}{instance}` (alphanumeric only)
- Key Vaults: `kv-{workload}-{env}-{instance}`
- Function Apps: `func-{workload}-{env}-{instance}`
- Service Bus: `sbns-{workload}-{env}-{instance}`
- ACI runners: `ci-{workload}-{env}-{instance}-{hash}`
