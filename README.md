# Event-Driven Ephemeral GitHub Runners on Azure

Terraform module that provisions a fully event-driven, autoscaling GitHub Actions runner platform on Azure. A Function App ingests GitHub webhook events, queues scale requests, and dynamically creates or destroys ephemeral Azure Container Instance (ACI) runners on demand.

## Architecture

```
GitHub Webhook
     │
     ▼
Azure Function App (github_webhook)
     │  enqueues scale request
     ▼
Service Bus Queue
     │
     ▼
Azure Function App (scale_worker)
     │  create / delete ACI runners
     ▼
Azure Container Instances  ──►  ACR (actions-runner image)
     │
     ▼
Azure Function App (cleanup_timer)  [runs every 5 min]
     │  removes stale / completed runners
```

**Provisioned resources**

| Resource | Name pattern | Purpose |
|---|---|---|
| Resource group | `rg-{workload}-{env}-{instance}` | Container for all resources |
| Container Registry | `cr{workload}{env}{instance}` | Runner image store |
| Key Vault | `kv-{workload}-{env}-{instance}` | GitHub App credentials |
| Service Bus namespace | `sbns-{workload}-{env}-{instance}` | Scale request queue |
| Function App | `func-{workload}-{env}-{instance}` | Control plane |
| Function storage | `st{...}` | Functions runtime storage |
| App Service plan | `asp-{workload}-{env}-{instance}` | Consumption Y1 (Linux) |
| Application Insights | `appi-{workload}-{env}-{instance}` | Telemetry |
| Managed identity | `id-{workload}-{env}-{instance}` | ACI → ACR pull |
| State storage | `st{...}` (bootstrap) | Terraform remote state |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (logged in: `az login`)
- [Azure Functions Core Tools v4](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local) (`npm i -g azure-functions-core-tools@4`)
- A GitHub App with `Administration: Read and write` + `Actions: Read` repository permissions


---

## Fresh deployment — step by step

### 1. Create a GitHub App

If you don't already have one:

- Personal: `https://github.com/settings/apps/new`
- Organisation: `https://github.com/organizations/<org>/settings/apps/new`

Minimum permissions:
- `Repository → Administration: Read and write` (required — mints runner registration tokens)
- `Repository → Actions: Read` (recommended)

Disable the webhook on the App unless you have a separate use for it — this module receives webhooks directly on the Function App.

Install the app on the target repository. After creation collect:
- **App ID** (shown on the app settings page)
- **Installation ID**: `gh api /repos/<org>/<repo>/installation --jq .id`
- **Private key PEM** (generate from the app settings page)

---

### 2. Bootstrap — provision remote state storage

The bootstrap module creates the Storage Account and blob container that holds Terraform remote state. It runs with **local state** by design and only needs to run once per environment.

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in rg, location, storage name
terraform init
terraform apply
```

If the storage account already exists (e.g. re-running on an existing environment), set `use_existing_storage = true` in `bootstrap/terraform.tfvars` — the module will adopt it instead of creating it.

Generate the backend config file:

```bash
terraform output -raw backend_hcl_snippet > ../backend.hcl
cd ..
```

---

### 3. Configure main module

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
resource_group_name  = "rg-runner-poc-bvt"
location             = "westeurope"
acr_name             = "crrunnerpocbvt"       # alphanumeric only
aci_name             = "ci-runner-poc-bvt"    # also seeds id-, asp-, appi- names
key_vault_name       = "kv-runner-poc-bvt"
storage_account_name = "strunnerpocbvt"       # state storage (managed by bootstrap)

github_org  = "your-org"
github_repo = "your-org/your-repo"

servicebus_namespace_name     = "sbns-runner-poc-bvt"
function_app_name             = "func-runner-poc-bvt"
function_storage_account_name = "stfnrunnerpocbvt"   # alphanumeric only

runner_min_instances = 0
runner_max_instances = 10
```

---

### 4. Deploy infrastructure

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Or use the Makefile:

```bash
make infra
```

---

### 5. Store GitHub App secrets in Key Vault

```bash
KV=kv-runner-poc-bvt   # your Key Vault name

# Grant yourself write access (once)
az role assignment create \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --role "Key Vault Secrets Officer" \
  --scope $(az keyvault show --name $KV --query id -o tsv)

# Store secrets
az keyvault secret set --vault-name $KV \
  --name runnerpocbouvet-github-app-id --value "<APP_ID>"

az keyvault secret set --vault-name $KV \
  --name runnerpocbouvet-github-app-installation-id --value "<INSTALLATION_ID>"

az keyvault secret set --vault-name $KV \
  --name runnerpocbouvet-github-app-private-key --file <path/to/private-key.pem>

# Optional — webhook signature validation
az keyvault secret set --vault-name $KV \
  --name runnerpocbouvet-webhook-secret --value "<WEBHOOK_SECRET>"
```

Default secret names expected by this module:

| Variable | Default secret name |
|---|---|
| `github_app_id_secret_name` | `runnerpocbouvet-github-app-id` |
| `github_app_installation_id_secret_name` | `runnerpocbouvet-github-app-installation-id` |
| `github_app_private_key_secret_name` | `runnerpocbouvet-github-app-private-key` |
| `webhook_secret_secret_name` | *(optional, set to `null` to disable)* |

The Function App is granted `Key Vault Secrets User` automatically by this module.

---

### 6. Deploy the Function App code

```bash
cd scaler-function
func azure functionapp publish func-runner-poc-bvt --python --build remote
```

Or:

```bash
make deploy
```

---

### 7. Register the webhook in GitHub

From the Terraform output:

```bash
terraform output function_app_default_hostname
```

In your GitHub repository: **Settings → Webhooks → Add webhook**

- **Payload URL**: `https://<hostname>/api/webhook/github?code=<function_key>`
- **Content type**: `application/json`
- **Events**: `Workflow jobs`

Retrieve the function key:

```bash
az functionapp function keys list \
  --resource-group rg-runner-poc-bvt \
  --name func-runner-poc-bvt \
  --function-name github_webhook \
  --query default -o tsv
```

---

## Makefile targets

```
make bootstrap       # Step 2 — provision remote state storage
make infra           # Step 4 — init + apply main module
make deploy          # Step 6 — publish Function App code
make all             # bootstrap → infra → deploy

make migrate-state   # One-time: remove azurerm_storage_account.storage from
                     # existing local state before switching to remote backend
```

---

## Variables reference

### Required

| Variable | Description |
|---|---|
| `resource_group_name` | Azure resource group |
| `location` | Azure region (e.g. `westeurope`) |
| `acr_name` | Container Registry name — alphanumeric only, globally unique |
| `aci_name` | ACI runner name prefix; seeds `id-`, `asp-`, `appi-` names |
| `key_vault_name` | Key Vault name — globally unique |
| `storage_account_name` | State storage account name (provisioned by bootstrap) |
| `function_storage_account_name` | Function App runtime storage — alphanumeric only, globally unique |
| `function_app_name` | Function App name — globally unique |
| `servicebus_namespace_name` | Service Bus namespace name — globally unique |
| `github_org` | GitHub organisation name |
| `github_repo` | Repository in `org/repo` format |
| `github_app_id_secret_name` | Key Vault secret name for GitHub App ID |
| `github_app_installation_id_secret_name` | Key Vault secret name for installation ID |
| `github_app_private_key_secret_name` | Key Vault secret name for private key PEM |

### Optional

| Variable | Default | Description |
|---|---|---|
| `webhook_secret_secret_name` | `null` | Key Vault secret name for webhook HMAC validation |
| `runner_min_instances` | `0` | Minimum live runners |
| `runner_max_instances` | `10` | Maximum live runners |
| `runner_idle_timeout_minutes` | `15` | Minutes before idle runner is terminated |
| `runner_completed_ttl_minutes` | `5` | Minutes to retain a completed runner before deletion |
| `max_runner_runtime_hours` | `2` | Hard cap on runner lifetime |
| `cpu` | `2` | CPU cores per runner |
| `memory` | `4` | Memory (GB) per runner |
| `runner_labels` | `azure,container-instance,self-hosted` | Comma-separated runner labels |
| `acr_sku` | `Standard` | Container Registry SKU |
| `storage_account_replication_type` | `LRS` | State storage replication |
| `enable_public_network_access` | `true` | Set to `false` for private endpoint environments |
| `tags` | `{Environment, ManagedBy, Purpose}` | Common resource tags |

---

## Outputs

| Output | Description |
|---|---|
| `function_app_name` | Function App name |
| `function_app_default_hostname` | Function App hostname (use for webhook URL) |
| `acr_login_server` | ACR login server URL |
| `acr_id` | ACR resource ID |
| `key_vault_uri` | Key Vault URI |
| `key_vault_id` | Key Vault resource ID |
| `servicebus_namespace_name` | Service Bus namespace name |
| `servicebus_queue_name` | Service Bus queue name |
| `storage_account_id` | State storage account ID |
| `function_storage_account_id` | Function App storage account ID |

---

## Runner image

On every `terraform apply`, this module imports the public runner image into ACR:

- **Source**: `ghcr.io/myoung34/docker-github-actions-runner:latest`
- **Target**: `<acr_login_server>/actions-runner:latest`

The Function App always uses the ACR-hosted image. To use a custom image, push it to ACR as `actions-runner:latest` before runners are needed.

---

## Scaler function internals

The control plane (`scaler-function/function_app.py`) has three functions:

| Function | Trigger | Role |
|---|---|---|
| `github_webhook` | HTTP | Validates signature, filters to `self-hosted` jobs, enqueues scale request |
| `scale_worker` | Service Bus | Deduplicates runners per job, computes desired count, creates/deletes ACI |
| `cleanup_timer` | Timer (5 min) | Removes completed, stale, or over-TTL runners |

Key behaviours:
- `maxConcurrentCalls: 1` on the Service Bus trigger prevents duplicate scale operations
- Scale formula: `max(scale_hint, queue_backlog)` — never sums, avoids over-provisioning
- Non-terminal runner deduplication — terminated containers are not counted as active
