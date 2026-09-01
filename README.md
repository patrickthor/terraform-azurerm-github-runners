# Event-Driven Ephemeral GitHub Runners on Azure

Terraform module that provisions an autoscaling, event-driven GitHub Actions runner platform on Azure. A Function App ingests GitHub webhook events, queues scale requests, and creates or destroys ephemeral Azure Container Instance (ACI) runners on demand.

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
Azure Function App (cleanup_timer)  [default: every 3 min]
     │  removes stale / completed runners
```

## What this repository is

A module and its control-plane code. Nothing more.

```
├── modules/runners/     # The Terraform module — all Azure resources
├── scaler-function/     # Python Function App code (the control plane)
├── examples/basic/      # Minimal module call
└── .github/workflows/   # fmt + validate, and semantic-release tagging
```

This repository deploys nothing on its own. It has no root module, no backend configuration, and no environment-specific values. You compose it from your own repository, which owns its state, its credentials, and its pipeline.

**Reference consumer**: [patrickthor/github-runner-customer-demo](https://github.com/patrickthor/github-runner-customer-demo) is a complete working setup — remote state, OIDC auth, and a `deploy-runners.yml` that runs Terraform, imports the runner image, and deploys the scaler function in one pipeline. Start there if you want something to copy.

---

## Usage

```hcl
module "runners" {
  source = "github.com/patrickthor/terraform-azurerm-github-runners//modules/runners?ref=v3.0.8"

  workload    = "runner"
  environment = "prod"
  instance    = "001"
  location    = "westeurope"

  github_org  = "your-org"
  github_repo = "your-org/your-repo"

  github_app_id_secret_name              = "github-app-id"
  github_app_installation_id_secret_name = "github-app-installation-id"
  github_app_private_key_secret_name     = "github-app-private-key"
}
```

Always pin `ref` to a tag. `main` is not a stable interface.

### Requirements

| | |
|---|---|
| Terraform | >= 1.5 |
| azurerm provider | >= 4.63 |
| Azure CLI | for the post-apply steps |
| GitHub App | `Administration: Read and write` + `Actions: Read` on the target repo |

The module declares no `provider` block and no `backend`. Configure both in your root module. `subscription_id` is not a module input — the module reads it from `data.azurerm_client_config.current`.

### Setup order

1. [Create a GitHub App](#create-a-github-app) and collect its App ID, installation ID, and private key
2. [Provision the deploying identity](#deploying-identity-permissions) so your pipeline can authenticate to Azure
3. Call the module and `terraform apply`
4. [Import the runner image and deploy the scaler function](#post-apply-steps)
5. [Store the GitHub App secrets in Key Vault](#store-the-github-app-secrets-in-key-vault)
6. [Register the webhook](#register-the-webhook)

Steps 3–4 are what the reference consumer's workflow automates.

---

## Inputs

### Required

| Variable | Description |
|---|---|
| `workload` | Short workload identifier (e.g. `runner`) — 2–12 lowercase alphanumeric |
| `environment` | Environment identifier (e.g. `poc`, `dev`, `prod`) — 2–8 lowercase alphanumeric |
| `instance` | Instance identifier for uniqueness (e.g. `bvt`, `001`) — 2–8 lowercase alphanumeric |
| `location` | Azure region (e.g. `westeurope`) |
| `github_org` | GitHub organisation name |
| `github_repo` | Repository in `org/repo` format |
| `github_app_id_secret_name` | Key Vault secret name holding the GitHub App ID |
| `github_app_installation_id_secret_name` | Key Vault secret name holding the installation ID |
| `github_app_private_key_secret_name` | Key Vault secret name holding the private key PEM |

The three secret names are required with no defaults — the module creates the Key Vault and wires the references, but you populate the secrets after the first apply.

### Resource name overrides

Names are generated from `workload`/`environment`/`instance` using Azure CAF conventions. Override any of them individually:

| Variable | Default pattern | Example (`runner`/`poc`/`bvt`) |
|---|---|---|
| `resource_group_name` | `rg-{w}-{e}-{i}` | `rg-runner-poc-bvt` |
| `acr_name` | `cr{w}{e}{i}` | `crrunnerpocbvt` |
| `aci_name` | `ci-{w}-{e}-{i}` | `ci-runner-poc-bvt` |
| `key_vault_name` | `kv-{w}-{e}-{i}` | `kv-runner-poc-bvt` |
| `function_app_name` | `func-{w}-{e}-{i}` | `func-runner-poc-bvt` |
| `function_storage_account_name` | `stfn{w}{e}{i}` | `stfnrunnerpocbvt` |
| `servicebus_namespace_name` | `sbns-{w}-{e}-{i}` | `sbns-runner-poc-bvt` |
| `log_analytics_workspace_name` | `log-{w}-{e}-{i}` | `log-runner-poc-bvt` |

### Optional

| Variable | Default | Description |
|---|---|---|
| `create_resource_group` | `true` | Whether the module creates the resource group |
| `create_log_analytics_workspace` | `true` | Create a workspace, or set `false` and pass `log_analytics_workspace_id` |
| `log_analytics_workspace_id` | `null` | Existing workspace ID, required when the above is `false` |
| `log_analytics_retention_days` | `30` | Retention, 30–730 days |
| `subnet_id` | `null` | Subnet for Function App VNet integration |
| `enable_public_network_access` | `true` | Set `false` for private endpoint environments |
| `webhook_secret_secret_name` | `null` | Key Vault secret for webhook HMAC validation — see the warning below |
| `runner_min_instances` | `0` | Minimum live runners (above `0` keeps warm runners) |
| `runner_max_instances` | `5` | Maximum live runners the scaler may create |
| `runner_completed_ttl_minutes` | `5` | Minutes to retain a completed runner before deletion |
| `max_runner_runtime_hours` | `2` | Hard cap on runner lifetime |
| `cpu` | `2` | CPU cores per runner (1–4) |
| `memory` | `4` | Memory GB per runner (1–16) |
| `runner_labels` | `azure,container-instance,self-hosted` | Comma-separated runner labels |
| `cleanup_timer_schedule` | `0 */3 * * * *` | NCRONTAB schedule for the cleanup timer |
| `servicebus_queue_name` | `runner-scale-requests` | Scale request queue name |
| `function_runtime_version` | `3.11` | Python version for the scaler |
| `runner_workload_roles` | `[]` | Azure roles granted to the runner identity — see the warning below |
| `enable_resource_locks` | `false` | `CanNotDelete` locks on the Key Vault and Function App storage |
| `acr_sku` | `Basic` | Container Registry SKU (`Premium` for private endpoints) |
| `storage_account_replication_type` | `LRS` | Function storage replication |
| `github_webhook_ip_ranges` | GitHub webhook CIDRs | Ranges allowed to reach the Function App; `[]` disables the restriction |
| `deployment_ip_ranges` | `[]` | Additional CIDRs to allow through (e.g. a static deploy IP) |
| `tags` | `{}` | Merged with the module's generated tags |

> **`runner_workload_roles` is granted at subscription scope.** The default is empty deliberately. Setting `["Contributor"]` gives every ephemeral runner container Contributor across the whole subscription. Grant the narrowest role your workflows actually need.

> **`webhook_secret_secret_name` defaults to `null`, which disables signature validation.** With it unset, anyone who learns the Function App URL and function key can inject fake `workflow_job` events. Set it in any environment you care about.

## Outputs

| Output | Description |
|---|---|
| `resource_group_name` | Resource group name |
| `function_app_name` | Function App name — the scaler deployment target |
| `function_app_default_hostname` | Function App hostname, used to build the webhook URL |
| `acr_login_server` | ACR login server URL |
| `acr_id` | ACR resource ID |
| `key_vault_uri` | Key Vault URI |
| `key_vault_id` | Key Vault resource ID |
| `servicebus_namespace_name` | Service Bus namespace name |
| `servicebus_queue_name` | Service Bus queue name |
| `runner_pull_identity` | User-assigned identity (`id`, `client_id`, `principal_id`) used for ACR pull |
| `scaler_identity_principal_id` | Function App system-assigned principal ID |
| `log_analytics_workspace_id` | Workspace used for diagnostics |
| `application_insights_connection_string` | App Insights connection string (sensitive) |

## Provisioned resources

| Resource | Name pattern | Example (`poc` / `bvt`) | Purpose |
|---|---|---|---|
| Resource group | `rg-{workload}-{env}-{instance}` | `rg-runner-poc-bvt` | Container for all resources |
| Container Registry | `cr{workload}{env}{instance}` | `crrunnerpocbvt` | Runner image store |
| Key Vault | `kv-{workload}-{env}-{instance}` | `kv-runner-poc-bvt` | GitHub App credentials |
| Service Bus namespace | `sbns-{workload}-{env}-{instance}` | `sbns-runner-poc-bvt` | Scale request queue |
| Function App | `func-{workload}-{env}-{instance}` | `func-runner-poc-bvt` | Control plane |
| Function storage | `stfn{workload}{env}{instance}` | `stfnrunnerpocbvt` | Functions runtime + deployment storage |
| App Service plan | `asp-{workload}-{env}-{instance}` | `asp-runner-poc-bvt` | Flex Consumption FC1 (Linux) |
| Application Insights | `appi-{workload}-{env}-{instance}` | `appi-runner-poc-bvt` | Telemetry |
| Log Analytics | `log-{workload}-{env}-{instance}` | `log-runner-poc-bvt` | Diagnostics and log retention |
| Managed identity | `id-{workload}-{env}-{instance}` | `id-runner-poc-bvt` | ACI → ACR pull |

ACI runners are created at runtime by the scaler, not by Terraform. They are named `ci-{workload}-{env}-{instance}-{hash}`.

---

## Create a GitHub App

- Personal: `https://github.com/settings/apps/new`
- Organisation: `https://github.com/organizations/<org>/settings/apps/new`

Suggested name: `ghapp-{workload}-{env}-{instance}`.

Minimum permissions:
- `Repository → Administration: Read and write` — required, mints runner registration tokens
- `Repository → Actions: Read` — recommended

Disable the App's own webhook unless you have a separate use for it; this module receives webhooks directly on the Function App.

Install the App on the target repository, then collect:
- **App ID** — on the App settings page
- **Installation ID** — `gh api /repos/<org>/<repo>/installation --jq .id`
- **Private key PEM** — generate from the App settings page

> The App must be installed on the specific repository that sends webhook events. An org-level App still needs to be installed on the target repo.

## Deploying identity permissions

Your pipeline needs an Azure identity with OIDC trust to your repository. One-time setup:

```bash
APP_NAME=sp-runner-prod-001
GITHUB_ORG=your-org
GITHUB_REPO=your-repo          # repo name only, not org/repo

SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# App Registration + service principal
CLIENT_ID=$(az ad app create --display-name $APP_NAME --query appId -o tsv)
az ad sp create --id $CLIENT_ID

# OIDC federated credential — no client secret needed
az ad app federated-credential create --id $CLIENT_ID --parameters "{
  \"name\": \"github-actions-main\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:$GITHUB_ORG/$GITHUB_REPO:ref:refs/heads/main\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"

PRINCIPAL_ID=$(az ad sp show --id $CLIENT_ID --query id -o tsv)
SUB_SCOPE=/subscriptions/$SUBSCRIPTION_ID

# Creates and modifies all module resources
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role Contributor --scope $SUB_SCOPE

# Creates the module's internal role assignments
# (AcrPull, Managed Identity Operator, Key Vault Secrets User, storage data roles)
az role assignment create \
  --assignee-object-id $PRINCIPAL_ID --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" --scope $SUB_SCOPE

echo "AZURE_CLIENT_ID:       $CLIENT_ID"
echo "AZURE_TENANT_ID:       $(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

> **These grants are broad.** Subscription-scope `Contributor` plus `User Access Administrator` is convenient for a proof of concept and too much for production. Scope both to the target resource group instead, pre-creating the group and setting `create_resource_group = false`. Note that `runner_workload_roles` assigns at subscription scope, so using it requires role-assignment rights at that scope — a further reason to leave it empty.

The `subject` must match your repository and branch exactly, or the workflow fails with `AADSTS700024`.

Your identity also needs `Storage Blob Data Contributor` on whichever storage account holds your Terraform state. The reference consumer's workflow grants this automatically when it creates the state account.

## Post-apply steps

Terraform provisions the infrastructure. Two things still need to reach it: the runner image and the scaler code.

```bash
# 1. Import the runner image into your ACR
ACR_NAME=$(terraform output -raw acr_login_server | cut -d. -f1)
az acr import --name "$ACR_NAME" \
  --source ghcr.io/myoung34/docker-github-actions-runner:latest \
  --image actions-runner:latest --force

# 2. Deploy the scaler function
FUNC_APP=$(terraform output -raw function_app_name)
RG=$(terraform output -raw resource_group_name)

cd scaler-function
pip install --target=".python_packages/lib/site-packages" -r requirements.txt
zip -r ../deploy.zip . -x "local.settings*.json" -x "__pycache__/*" -x "*.pyc" -x "DEPLOYMENT.md"
cd ..

az functionapp deployment source config-zip \
  --resource-group "$RG" --name "$FUNC_APP" --src deploy.zip --timeout 300
```

The Function App restricts inbound traffic to GitHub webhook ranges by default, so a manual deploy needs the deploying machine's IP allowed through — temporarily via `az functionapp config access-restriction add`, or permanently via `deployment_ip_ranges`.

You do not need to vendor the Python code into your project. Fetch it from a release tag, as the reference consumer does:

```bash
curl -sL "https://github.com/patrickthor/terraform-azurerm-github-runners/archive/refs/tags/v3.0.8.tar.gz" \
  | tar xz --wildcards --strip-components=1 -C . "*/scaler-function"
```

The scaler always pulls the ACR-hosted image. To use a custom runner image, push it to ACR as `actions-runner:latest`.

## Store the GitHub App secrets in Key Vault

```bash
KV=<key-vault-name>

# Grant yourself write access (once)
az role assignment create \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --role "Key Vault Secrets Officer" \
  --scope $(az keyvault show --name $KV --query id -o tsv)

# Names must match the *_secret_name values you passed to the module
az keyvault secret set --vault-name $KV --name github-app-id --value "<APP_ID>"
az keyvault secret set --vault-name $KV --name github-app-installation-id --value "<INSTALLATION_ID>"
az keyvault secret set --vault-name $KV --name github-app-private-key --file <path/to/private-key.pem>

# Recommended — enables webhook signature validation
az keyvault secret set --vault-name $KV --name github-webhook-secret --value "<WEBHOOK_SECRET>"
```

The Function App is granted `Key Vault Secrets User` by the module, so it can read these without further configuration.

## Register the webhook

In the repository: **Settings → Webhooks → Add webhook**

- **Payload URL**: `https://<function_app_default_hostname>/api/webhook/github?code=<function_key>`
- **Content type**: `application/json`
- **Events**: *Workflow jobs*
- **Secret**: the value stored as `github-webhook-secret`

```bash
az functionapp function keys list \
  --resource-group <rg> --name <function-app-name> \
  --function-name github_webhook --query default -o tsv
```

---

## Scaler function internals

`scaler-function/function_app.py` contains three functions:

| Function | Trigger | Role |
|---|---|---|
| `github_webhook` | HTTP | Validates the signature, filters to `self-hosted` jobs, enqueues a scale request |
| `scale_worker` | Service Bus | Deduplicates per job, computes desired count, creates/deletes ACI |
| `cleanup_timer` | Timer (default 3 min) | Removes completed, stale, or over-TTL runners |

Behaviours worth knowing:
- Scale formula is `max(scale_hint, queue_backlog)` — never a sum
- `maxConcurrentCalls: 1` on the Service Bus trigger prevents duplicate scale operations
- One runner per `workflow_job_id`; terminated containers are not counted as active
- At capacity, the worker re-checks the GitHub API for whether the job is still queued and sleeps 100s between attempts, giving roughly a 50-minute retry window over 30 deliveries
- ACI quota exhaustion retries three times with 35s backoff
- Permanent config errors are consumed silently rather than filling the queue with retries

Service Bus runs on Basic tier, which has no dead-letter queue. Application Insights is the debugging surface; see [IMPROVEMENTS.md](IMPROVEMENTS.md) for the reasoning and the current backlog.

## Developing this module

```bash
terraform fmt -recursive
cd modules/runners && terraform init -backend=false && terraform validate
```

CI runs the same checks plus a Python import check on the scaler, with no Azure credentials involved. `release.yml` runs semantic-release on merges to `main` and produces the tags consumers pin to, so commit messages must follow [Conventional Commits](https://www.conventionalcommits.org/).

## License

[MIT](LICENSE)
