---
inclusion: auto
---

# Project Structure

This repository publishes a Terraform module. It deploys nothing itself: there is no root module, no backend configuration, and no environment-specific values. Consumers compose the module from their own repository and own their state, credentials, and pipeline.

```
modules/runners/      # The module — every Azure resource lives here
scaler-function/      # Python Function App code (the control plane)
examples/basic/       # Minimal module call, local state, literal values
.github/workflows/    # validate.yml (fmt + validate), release.yml (semantic-release)
```

The reference consumer is [patrickthor/github-runner-customer-demo](https://github.com/patrickthor/github-runner-customer-demo). It owns the remote state, the OIDC identity, and the deploy pipeline.

## The module

```
modules/runners/
  main.tf        # ACR, Key Vault, Service Bus, Function App, identities, RBAC, diagnostics, locks
  variables.tf   # Inputs with validation rules
  outputs.tf     # Exported values (function hostname, ACR server, Key Vault URI, etc.)
  versions.tf    # Terraform + azurerm version constraints only
```

Rules for this directory:
- No `provider` block and no `backend` block. Both belong to the consumer's root module.
- No `subscription_id` input. Read it from `data.azurerm_client_config.current`.
- Every resource the module locks or references must be a resource the module owns. Do not add data sources that assume resources exist outside the module's own scope.
- New inputs need a validation rule where a constraint exists, and a row in the README table.
- Breaking input or output changes require a major version bump via a `feat!:` or `BREAKING CHANGE:` commit.

## Function App code

```
scaler-function/
  function_app.py              # Three functions: webhook, worker, timer
  requirements.txt             # Python dependencies
  host.json                    # Functions runtime configuration
  local.settings.example.json  # Local development template
  DEPLOYMENT.md                # Deployment instructions
```

Deployed separately from Terraform. Consumers fetch this directory from a release tag tarball rather than vendoring it. Any new app setting read here must be added to `local.scaler_base_settings` in the module, and any setting removed there must be removed here.

### Function responsibilities

- `github_webhook`: validates GitHub signatures, filters to self-hosted jobs, enqueues to Service Bus
- `scale_worker`: deduplicates per `workflow_job_id`, computes desired count, creates/deletes ACI
- `cleanup_timer`: removes completed, stale, or over-TTL runners on the configured schedule

## Examples

`examples/basic/` is documentation, not a deployment. Local state, literal values, no workflow. It pins the module to a published tag, so CI format-checks it but does not `init` it — that would validate the released module rather than the working tree.

Full CI/CD patterns belong in the consumer repository, not here. Do not reintroduce a workflow under `examples/`.

## Key design patterns

### Naming

All names derive from `workload`/`environment`/`instance` via Azure CAF conventions, each overridable by a variable:

- Resource groups: `rg-{workload}-{env}-{instance}`
- Storage accounts: `stfn{workload}{env}{instance}` (alphanumeric only)
- Container registries: `cr{workload}{env}{instance}` (alphanumeric only)
- Key Vaults: `kv-{workload}-{env}-{instance}`
- Function Apps: `func-{workload}-{env}-{instance}`
- Service Bus: `sbns-{workload}-{env}-{instance}`
- ACI runners: `ci-{workload}-{env}-{instance}-{hash}` (created at runtime by the scaler)

### Security model

- RBAC everywhere; no shared access keys except where FC1 deployment storage still requires them
- Managed identities for all Azure resource authentication
- GitHub App rather than PAT for GitHub API access
- Key Vault references for Function App secrets
- OIDC federation for consumer CI/CD
- `runner_workload_roles` defaults to `[]`. It grants at subscription scope, so a broad value gives every ephemeral container that scope.
- `webhook_secret_secret_name` defaults to `null`, which disables signature validation entirely

### Scale logic

- Scale formula: `max(scale_hint, queue_backlog)` — never a sum
- Deduplication: one runner per `workflow_job_id`
- Terminated containers are not counted as active
- At capacity or out of ACI quota: defer and retry rather than fail
