---
inclusion: auto
---

# Project Structure

## Root Module (Main Infrastructure)

The root directory contains the primary Terraform module that provisions all runtime resources.

```
main.tf           # Core resources: ACR, Key Vault, Service Bus, Function App, identities
variables.tf      # Input variable definitions with validation rules
outputs.tf        # Exported values (function hostname, ACR server, etc.)
providers.tf      # Azure provider configuration
versions.tf       # Terraform version constraints + azurerm backend config
terraform.tfvars.example  # Template for variable values
backend.hcl.example       # Template for backend configuration
```

## Bootstrap Module

One-time setup for Terraform remote state storage. Uses local state by design.

```
bootstrap/
  main.tf                    # Storage account + blob container provisioning
  variables.tf               # Bootstrap-specific variables
  outputs.tf                 # State storage details
  versions.tf                # No backend (local state)
  terraform.tfvars.example   # Bootstrap variable template
```

## Function App Code

Python Azure Functions that implement the control plane.

```
scaler-function/
  function_app.py            # Three functions: webhook, worker, timer
  requirements.txt           # Python dependencies
  host.json                  # Functions runtime configuration
  local.settings.example.json  # Local development settings template
  DEPLOYMENT.md              # Deployment instructions
  .python_packages/          # Local development cache
```

### Function Responsibilities

- `github_webhook`: Validates GitHub signatures, filters self-hosted jobs, enqueues to Service Bus
- `scale_worker`: Deduplicates runners, computes desired count, creates/deletes ACI
- `cleanup_timer`: Removes stale/completed runners every 5 minutes

## Demo Environment

Example configuration for testing the module.

```
demo/
  main.tf           # Module invocation example
  providers.tf      # Provider configuration
  variables.tf      # Demo-specific variables
  outputs.tf        # Pass-through outputs
  versions.tf       # Version constraints + backend
  terraform.tfvars  # Demo values (may contain sensitive data)
```

## CI/CD Workflows

```
.github/workflows/
  bootstrap.yml     # Stage 1: Provision state storage
  deploy.yml        # Stage 2: Terraform apply + Stage 3: Function publish
  release.yml       # Semantic versioning + GitHub Release
```

## Key Design Patterns

### State Management

- Bootstrap module uses local state (one-time setup)
- Main module uses azurerm backend (remote state in Azure Storage)
- Backend config supplied via `-backend-config=backend.hcl` at init time

### Resource Ownership

- Bootstrap owns: state storage account
- Main module owns: all runtime resources (ACR, Function App, Service Bus, etc.)
- Main module references (data source): state storage account

### Naming Strategy

- All resource names derived from input variables
- Consistent prefixes/patterns for resource type identification
- Alphanumeric-only names for globally unique resources (ACR, Storage)
- Hyphenated names for other resources (Key Vault, Function App)

### Security Model

- No shared access keys (Key Vault, Storage)
- RBAC for all access control
- Managed identities for Azure resource authentication
- GitHub App (not PAT) for GitHub API access
- Key Vault references for Function App secrets
- OIDC federation for CI/CD (no secrets in GitHub)

### Scale Logic

- Scale formula: `max(scale_hint, queue_backlog)` — never sums
- Deduplication: one runner per workflow_job_id
- Non-terminal state check: terminated containers don't count as active
- Capacity handling: defer jobs when at max_instances
- Quota handling: defer jobs when ACI quota exhausted
