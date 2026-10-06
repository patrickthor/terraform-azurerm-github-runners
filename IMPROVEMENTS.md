# Improvement Plan: Event-Driven Ephemeral GitHub Runners on Azure

Verified against official Microsoft documentation and Azure Well-Architected Framework (March 2026).

---

## Remaining Improvements

### Runner image

#### Base OS and Azure CLI are both out of support

**Current**: `runner-image/Dockerfile` pins `ghcr.io/myoung34/docker-github-actions-runner`, which builds `FROM ubuntu:focal`. Ubuntu 20.04 left standard security support in May 2025. `azure-cli=2.72.0-1~focal` is the newest build in Microsoft's focal feed — verified against the repository index — while the noble feed is at `2.91.0`. Cloud-privileged workflow code therefore runs on an unsupported OS with a CLI that no longer receives monthly security fixes, and digest pinning freezes that exposure rather than resolving it.

**Recommended**: Rebase onto Ubuntu 24.04 and install from the matching noble feed. This cannot be done by changing `FROM` alone: the ephemeral registration flow, the `runner` account, gosu privilege-drop, and the `REPO_URL`/`RUNNER_TOKEN`/`EPHEMERAL` contract all come from the upstream entrypoint, so moving off that image means reimplementing it and revalidating runtime behavior. Add scheduled rebuilds so the digest does not go stale silently.

#### Workflow steps run as root

**Current**: The pinned upstream config sets no OCI `User`, and its entrypoint resolves `RUN_AS_ROOT=${RUN_AS_ROOT:="true"}`. The scaler's ACI environment does not override it, so workflow steps execute as root with the container filesystem, runner installation, and job credentials in reach.

**Recommended**: Have the scaler set `RUN_AS_ROOT=false` so the upstream entrypoint drops to the `runner` account via gosu, then validate representative Azure CLI and Terraform workflows as non-root before rollout. One-job ACI ephemerality limits persistence between jobs but does not protect secrets, OIDC tokens, or managed-identity tokens during a job.

#### No vulnerability, SBOM, or signature gate on the runner image

**Current**: CI builds the image and asserts the toolchain, but nothing produces an SBOM, scans for vulnerabilities, or attests provenance. A digest proves byte identity, not that the bytes are safe or that they came from a reviewed build.

**Recommended**: Generate an SBOM and provenance attestation for the built image, scan and fail on policy-defined critical/high findings, and sign the ACR manifest before the scaler is pointed at it.

#### Runner image reference is a mutable tag

**Current**: `local.scaler_base_settings` hard-codes `RUNNER_IMAGE = "${acr.login_server}/actions-runner:latest"`. Nothing captures the ACR manifest digest, so the infrastructure revision does not identify the image ACI executes. A rebuild or retag silently changes new runners, and rollback cannot select known bytes.

**Recommended**: Accept `runner_image_repository`, `runner_image_tag`, and an optional `runner_image_digest` (validated as `sha256:` plus 64 lowercase hex), resolve to `<acr>/<repo>@sha256:...` when a digest is supplied and `<acr>/<repo>:<tag>` otherwise, pass that single normalized reference through `RUNNER_IMAGE`, and expose it as an output. The scaler already forwards `RUNNER_IMAGE` to ACI unchanged and derives the registry from the first path segment, so a digest reference needs no scaler change.

### Reliability

#### Confirm the Service Bus provider floor against a clean namespace

**Current**: The module floor was raised to `azurerm >= 5.6.0` because 5.6.0 moved Service Bus to control-plane API `2026-01-01`. On 5.4.0 (API `2024-01-01`) a Basic namespace was observed provisioning into a `Failed` state, after which every retry returned `CreateNamespacePayloadDiffersFromExistingNamespaceInFailedState`. The module validates against 5.7.0, but the fix has not yet been confirmed by a successful apply from a clean state.

**Recommended**: Apply against a fresh namespace name (or after deleting the failed one) and confirm `provisioningState = Succeeded`, `status = Active`, SKU still `Basic`, `disableLocalAuth = true`, and that the queue is created. Until then, treat the provider version as the working diagnosis rather than a proven fix.

#### Pool `ServiceBusClient` in `_servicebus_send`

**Current**: Every webhook call creates a new `ServiceBusClient` + `DefaultAzureCredential`, opening a fresh AMQP connection.

**Recommended**: Use a module-level singleton (like `_http_session`) to pool the connection. Reduces latency and resource churn under burst webhook traffic.

#### Re-list after prune doesn't re-check for duplicate runners

**Current**: After `_prune_stale_runners` triggers a re-list, the duplicate check `_has_runner_for_workflow_job` ran against the old list. The re-listed runners aren't checked for duplicates.

**Recommended**: Move the duplicate check after the conditional re-list. Edge case but possible under heavy concurrent load.

### Security & RBAC

#### Tighten Function App RBAC scope

**Current**: Scaler Function App has `Contributor` on the entire resource group.

**Recommended**: Use a custom role with only the required ACI operations, or scope Contributor down to only the specific resources needed.

**Source**: [Azure best practices — least privilege](https://learn.microsoft.com/azure/role-based-access-control/best-practices)

#### Pin GitHub Actions to commit SHAs

**Current**: ~~Actions pinned to major version tags (`@v4`, `@v2`, `@v3`).~~ **Done** — all actions pinned to commit SHAs across all workflows.

**Recommended**: ~~Pin to full commit SHA for supply chain security.~~ Add Dependabot for automatic SHA update PRs.

#### Pin semantic-release dependencies

**Current**: `release.yml` runs `npm install -g semantic-release @semantic-release/...` without version pins.

**Recommended**: Pin exact versions or use a lockfile to prevent unexpected breaking changes. The `release.yml` job has `contents: write`, `issues: write`, and `pull-requests: write` permissions — unpinned packages execute with these privileges.

#### Allow scope override for runner workload roles

**Current**: `runner_workload_roles` is granted at subscription scope (`/subscriptions/{id}`). The default is `[]` and the README warns against broad values, but a consumer setting `["Contributor"]` still gives every ephemeral runner container Contributor on the entire subscription.

**Recommended**: Add a `runner_workload_role_scope` variable so consumers can target a resource group instead. Consider a validation rule that rejects `Owner` outright.

#### Key Vault network ACL defaults to Allow

**Current**: Key Vault `network_acls { default_action = "Allow" }` when `enable_public_network_access = true` (default). The Key Vault holds GitHub App private key, installation ID, and webhook secret.

**Recommended**: For production, set `default_action = "Deny"` with appropriate bypass rules, or document the tradeoff. The Function App accesses Key Vault via `@Microsoft.KeyVault` references which work through Azure backbone, so a Deny default with `bypass = "AzureServices"` would still work.

#### Function App storage account network open with shared key enabled

**Current**: `azurerm_storage_account.functions` has `network_rules { default_action = "Allow" }` and shared key access is enabled (required for FC1 deployment storage due to [Azure bug](https://github.com/hashicorp/terraform-provider-azurerm/issues/29993)).

**Recommended**: Track the upstream FC1 MSI issue. Once resolved, disable shared key access and tighten network rules. Until then, this is an accepted risk.

#### Webhook secret validation is optional — no warning when disabled

**Current**: `webhook_secret_secret_name` defaults to `null`. When unset, `_verify_github_signature()` returns `True` for any request. Anyone who discovers the Function App URL + function key can inject fake webhook events.

**Recommended**: Log a warning at Function App startup when `WEBHOOK_SECRET` is not configured. Consider making it required or adding a prominent note in the README.

#### Runner image imported from third-party source without digest pinning

**Current**: The documented import step and the reference consumer's workflow both use `az acr import --source ghcr.io/myoung34/docker-github-actions-runner:latest`. No SHA digest verification. A compromised upstream image is pulled into ACR on every deploy.

**Recommended**: Pin to a specific digest (e.g. `ghcr.io/myoung34/docker-github-actions-runner@sha256:abc...`) or build a custom runner image from a trusted base. ACR Basic SKU does not support content trust.

### Performance

#### Pool `DefaultAzureCredential` as a module-level singleton

**Current**: `_arm_token()` creates a new `DefaultAzureCredential()` on every call. Inside `_arm_request`'s retry loop, each attempt instantiates a fresh credential.

**Recommended**: Create the credential once at module level. `DefaultAzureCredential` handles its own internal token caching and refresh.

### Python / Function App

#### Eliminate duplicate `SERVICEBUS_NAMESPACE_FQDN` app setting

**Current**: Both `SERVICEBUS_NAMESPACE_FQDN` and `SERVICEBUS_CONNECTION__fullyQualifiedNamespace` contain the same value. The Python code reads `SERVICEBUS_NAMESPACE_FQDN` in `_servicebus_send()`.

**Recommended**: Change `_servicebus_send()` to read `SERVICEBUS_CONNECTION__fullyQualifiedNamespace` instead, and remove the duplicate `SERVICEBUS_NAMESPACE_FQDN` app setting.

#### Pin Python dependencies

**Current**: `requirements.txt` uses minimum version constraints (`azure-identity>=1.16.0`) without upper bounds.

**Recommended**: Pin exact versions (e.g., `azure-functions==1.21.3`) for reproducible deployments.

#### Verify `host.json` extension bundle version range

**Current**: Extension bundle version is `[4.*, 5.0.0)`.

**Recommended**: Verify this is still the recommended range for Azure Functions v4 runtime. Update if a newer bundle is available.

---

## Completed ✅

### Architecture & Module Structure
- **Raise the azurerm floor to `>= 5.6.0`** — first release carrying Service Bus control-plane API `2026-01-01`, which addresses Basic namespaces provisioning into a `Failed` state on earlier 5.x builds. No upper bound in the module; `examples/basic` pins `~> 5.7.0` as a root module should. Rejected two non-fixes: `zone_redundant` on the namespace (automatic in Azure, absent from the resource schema) and switching to Premium. This raises the module's minimum major provider version, so it is a breaking change for consumers still on azurerm 4.x
- **Reduce the repository to a pure consumption module** — removed the root module (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf` with its backend block, `terraform.tfvars.example`, `backend.hcl.example`), the `bootstrap/` state-storage module, and the `bootstrap.yml` / `deploy.yml` / `demo-storage.yml` workflows. The repo no longer deploys anything; consumers own their state, credentials, and pipeline. Reference consumer: [github-runner-customer-demo](https://github.com/patrickthor/github-runner-customer-demo)
- **Remove bootstrap coupling from the module** — `data.azurerm_storage_account.state` and `azurerm_management_lock.state_storage` assumed Terraform state lived in the runner resource group as `st{workload}{env}{instance}`. That is false for any consumer, so `enable_resource_locks = true` would have failed on lookup. Replaced with a lock on the module-owned Function App storage account; dropped the orphaned `storage_account_name` variable
- **Collapse examples** — `examples/demo/` removed (it lives in the consumer repo as `storage-demo`); `examples/basic/` reduced to a literal-value module call with no backend, no variable indirection, and no duplicated workflow
- **Replace deploy CI with `validate.yml`** — `terraform fmt -check`, module `validate`, and a Python compile/import check, with no Azure credentials
- Package as Terraform module — resources moved to `modules/runners/`
- Simplify variable surface — 3 core variables (`workload`, `environment`, `instance`) generate all resource names via Azure CAF conventions, with override support
- Configurable resource group creation via `create_resource_group`
- Remove stale `moved` blocks — 25 migration blocks removed after state migration completed

### Security & RBAC
- Runner workload roles default changed from `["Contributor"]` to `[]` (least privilege)
- Hardcoded subscription ID removed from demo
- Generic error messages in webhook (no exception details exposed)
- Disable shared key access on consumer state storage account (`--allow-shared-key-access false`)

### Infrastructure
- Migrate to FC1 Flex Consumption — `sku_name = "FC1"`, VNet support via `subnet_id`
- Remove storage access key — managed identity with `AzureWebJobsStorage__accountName`
- Remove instrumentation key — connection string only (instrumentation key deprecated March 2025)
- Fix `storage_account_replication_type` variable — now actually used in function storage account (was declared but hardcoded to LRS)
- Align provider versions — bootstrap, demo, and module all require `>= 4.63`

### Observability
- Log Analytics Workspace — created and linked to Application Insights
- Diagnostic settings — Key Vault, Service Bus, Function App
- Resource locks — configurable via `enable_resource_locks`

### CI/CD Workflows
- Terraform validate step added to deploy workflow
- Fix demo workflow retry logic — loops now correctly exit with failure after 3 attempts
- Improve deploy workflow role parsing — use `jq` instead of `python3` for CSV→JSON conversion
- Demo workflow uses `terraform init -upgrade` to handle lock file version updates
- Demo workflow retry for transient Azure WAF blocks on ephemeral ACI IPs

### Function App / Scaler
- Module-level HTTP session pooling (`requests.Session()`)
- Add `urllib3` retry adapter to HTTP session — automatic retries for transport-level errors (connection resets, DNS failures), simplifying `_arm_request`
- GitHub API rate limit handling in `_is_job_still_queued` — checks `X-RateLimit-Remaining` header and backs off gracefully
- Remove unused app settings — `RUNNER_IDLE_TIMEOUT_MIN` and `EVENT_POLL_INTERVAL_SEC` removed (never read by Python code)
- Fix at-capacity DLQ spam — sleep 100s between retries, check GitHub job status before retrying, ACI quota retry with backoff
- Update stale references — `local.settings.example.json`, `DEPLOYMENT.md`, and README now use CAF naming conventions
- Fix README Key Vault secret names to match deploy workflow defaults
- Update README scaler internals documentation

- Remove private key material from logs — `_github_installation_access_token` no longer logs the first 30 chars of the private key (security hygiene)
- Remove stale `storage_account_id` from README outputs table (was removed from code in previous cleanup)
- Make cleanup timer schedule configurable — new `cleanup_timer_schedule` variable (NCRONTAB), default changed from every 1 minute to every 3 minutes to reduce ARM API calls at scale

### Module Cleanup
- Remove unused `runner_idle_timeout_minutes` and `event_poll_interval_seconds` variables — declared but never read by Python code
- Remove redundant GitHub App auth precondition — first precondition already enforces all-set
- Remove `storage_account_id` output — only relevant to bootstrap, confusing for consumers
- Fix `storage_account_name` variable description — clarify only used with `enable_resource_locks`
- Fix stale "managed identity — no access keys" comment on function storage section
- Remove dead `GITHUB_ENVIRONMENT` app setting and variable — set by Terraform but never read by Python code
- Fix demo workflow stale plan retry — re-plan before re-apply instead of reusing stale plan file
- Fix demo workflow Terraform version pin — aligned to `~> 1.9` like all other workflows
- Fix CHANGELOG.md links — updated from old repo name to `patrickthor/terraform-azurerm-github-runners`
- Rewrite DEPLOYMENT.md for Flex Consumption — removed stale Consumption plan references and `func publish` method
- Add auth context comment to `backend.hcl.example` — clarify `use_azuread_auth` vs `use_oidc`
- Fix README `subscription_id` listed as required module variable — it's a provider setting, not a module input
- Add `examples/demo/README.md`
- Remove stale `GITHUB_ENVIRONMENT` from `local.settings.example.json`

---

## Not Implemented (Deliberate Decision)

### Container Apps Jobs as alternative to ACI

Microsoft recommends Container Apps Jobs for self-hosted runners ([official tutorial](https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs)), and it would dramatically simplify the architecture (removes Function App, Service Bus, ~500 lines of Python). However, it has a critical limitation:

> **"Container apps and jobs don't support running Docker in containers. Any steps in your workflows that use Docker commands fail when run on a self-hosted runner."**
> — [Microsoft Learn](https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs)

For a module intended for multiple consumers, Docker support (`docker build`, `docker push`, Docker Compose, Testcontainers) is a common requirement. Excluding this limits the module's applicability too much.

**Decision**: Keep ACI as the sole compute platform. A Container Apps Jobs variant could be offered as an alternative, but the complexity of maintaining two separate implementations does not outweigh the benefits.

### Service Bus Basic SKU — no dead-letter queue

The module uses Service Bus Basic tier (`sku = "Basic"`), which does not support dead-letter queue (DLQ) forwarding. Messages that exhaust all 30 delivery attempts are silently discarded.

This is acceptable because:
- Permanent config errors (missing env vars, bad values) are caught and consumed silently by the `scale_worker` to avoid DLQ spam regardless of tier
- Transient failures (ARM throttling, quota exhaustion) are retried within the function invocation itself (sleep + retry loops), so messages rarely exhaust all 30 Service Bus attempts
- The at-capacity retry logic sleeps 100s between attempts, giving ~50 minutes of retry window before the message is abandoned
- All failures are logged to Application Insights, which is the primary debugging tool — not the DLQ

Upgrading to Standard tier (~$10/month) would enable DLQ inspection for post-mortem analysis, but adds cost with minimal operational benefit given the current retry and logging strategy.

**Decision**: Keep Basic tier. The retry logic and Application Insights logging provide sufficient observability. Upgrade to Standard if you need DLQ inspection for compliance or audit requirements.
