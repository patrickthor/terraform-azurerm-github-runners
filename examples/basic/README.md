# Basic Example — Consuming the Runners Module

This example shows the minimum setup needed to deploy the GitHub runners platform in your own project.

## Files

```
├── main.tf                                  # Module call with your configuration
├── variables.tf                             # Subscription ID variable
├── versions.tf                              # Provider and backend configuration
└── .github/workflows/deploy-runners.yml     # CI/CD workflow (copy to your repo)
```

## Quick start

1. Copy this entire directory into your project (e.g., as `infra/runners/`)
2. Copy `.github/workflows/deploy-runners.yml` to your repo's `.github/workflows/`
3. Update `main.tf` with your values (org, repo, location, etc.)
4. Configure GitHub secrets and variables (see workflow header comments)
5. Push to `main` — the workflow handles everything:
   - Terraform apply (infrastructure)
   - ACR image import (runner container image)
   - Scaler function deployment (Python code fetched from module repo)

## After first deploy

1. Store GitHub App secrets in the Key Vault (see main repo README step 6)
2. Register the GitHub webhook pointing at the Function App (see main repo README step 7)
3. Trigger a workflow with `runs-on: [self-hosted, azure, container-instance]` to test
