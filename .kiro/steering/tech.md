---
inclusion: auto
---

# Technology Stack

## Infrastructure as Code

- Terraform >= 1.5
- AzureRM provider >= 4.63
- No backend in this repository — consumers configure their own remote state

## Azure Services

- Azure Functions on Flex Consumption (`FC1`, Linux) — VNet support via `subnet_id`
- Azure Container Instances (ACI) — created at runtime by the scaler, not by Terraform
- Azure Container Registry (ACR, Basic by default)
- Azure Service Bus (Basic SKU — no dead-letter queue, deliberate)
- Azure Key Vault (RBAC-enabled, purge protection on)
- Azure Storage (Function App runtime + deployment container)
- Application Insights + Log Analytics
- Managed identities (system-assigned for the Function App, user-assigned for ACR pull)

## Function App Runtime

- Python 3.11
- Dependencies: `azure-functions`, `azure-identity`, `azure-servicebus`, `requests`, `PyJWT[crypto]`
- `host.json`: extension bundle `[4.*, 5.0.0)`, `serviceBus.maxConcurrentCalls: 1`

## Authentication

- GitHub App (not PAT) with `Administration: Read and write` + `Actions: Read`
- Azure OIDC federation for consumer CI/CD — no client secrets
- Managed identities for all Azure resource access
- Key Vault references for sensitive Function App settings

## Common Commands

### Validate the module

```bash
terraform fmt -recursive
cd modules/runners && terraform init -backend=false && terraform validate
```

There is no `terraform plan` or `apply` in this repository. To exercise the module, run it from `examples/basic` or from the consumer repo.

### Scaler function

```bash
cd scaler-function
python -m compileall -q function_app.py
python -c "import function_app"
```

Deployment uses zip deploy, not `func publish` — Flex Consumption needs
`az functionapp deployment source config-zip` with dependencies vendored into
`.python_packages/lib/site-packages`. See `scaler-function/DEPLOYMENT.md`.

### Azure CLI helpers

```bash
# Function key for the webhook URL
az functionapp function keys list \
  --resource-group <rg> --name <function-app-name> \
  --function-name github_webhook --query default -o tsv

# Store GitHub App secrets
az keyvault secret set --vault-name <kv-name> --name <secret-name> --value "<value>"

# Live runners
az container list --resource-group <rg> --output table
```

## CI/CD

- `validate.yml`: `terraform fmt -check`, module `validate`, Python compile and import checks. No Azure credentials, no plan, no apply.
- `release.yml`: semantic-release on push to `main`, producing the tags consumers pin to.

Commit messages must follow Conventional Commits — they drive the version bump. Breaking module input or output changes need `feat!:` or a `BREAKING CHANGE:` footer.
