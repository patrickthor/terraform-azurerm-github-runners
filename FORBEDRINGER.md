# Forbedringsplan: Event-Driven Ephemeral GitHub Runners on Azure

Verifisert mot offisiell Microsoft-dokumentasjon og Azure Well-Architected Framework via MCP-verktøy (mars 2026).

---

## 1. Arkitekturvalg: ACI vs Container Apps Jobs

### Container Apps Jobs — IKKE anbefalt for denne modulen

Microsoft anbefaler Container Apps Jobs for self-hosted runners ([offisiell tutorial](https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs)), og det ville forenklet arkitekturen dramatisk (fjerner Function App, Service Bus, ~500 linjer Python). Men det har en kritisk begrensning:

> **"Container apps and jobs don't support running Docker in containers. Any steps in your workflows that use Docker commands fail when run on a self-hosted runner."**
> — [Microsoft Learn](https://learn.microsoft.com/azure/container-apps/tutorial-ci-cd-runners-jobs)

For en modul som skal brukes av flere kunder er Docker-støtte (`docker build`, `docker push`, Docker Compose, Testcontainers) et vanlig krav. Å utelukke dette begrenser modulens bruksområde for mye.

### ACI — riktig valg, men kan forbedres

Den nåværende ACI-arkitekturen er det riktige valget fordi:
- ACI kjører ekte Linux-containere med full kontroll over runtime
- Docker-in-Docker (DinD) eller socket-montering er mulig med riktig runner-image
- Ingen begrensninger på hva workflows kan kjøre

**Anbefaling**: Behold ACI som compute-plattform. Fokuser forbedringene på Function App, sikkerhet, observability og modulstruktur (se punkt 2–8).

**Vurder å tilby begge varianter**: En `aci`-variant (full Docker-støtte) og en `container-apps`-variant (enklere, billigere, men uten Docker). Kunder velger basert på behov. Dette kan implementeres som separate Terraform-moduler eller en variabel som styrer compute-backend.

---

## 2. Høy: Sikkerhet og RBAC

### 2a. Stram inn Function App / Container Apps RBAC-scope

**Nåværende**: Scaler Function App har `Contributor` på hele resource group.

**Anbefalt**: Bruk en custom role med kun de nødvendige ACI/Container Apps-operasjonene, eller scope Contributor ned til kun de spesifikke ressursene som trengs.

**Kilde**: [Azure best practices — least privilege](https://learn.microsoft.com/azure/role-based-access-control/best-practices)

### 2b. Runner workload-roller er for brede

**Nåværende**: `runner_workload_roles` default er `["Contributor"]` på subscription scope.

**Anbefalt**: Default bør være en tom liste eller en mer begrenset rolle. Kunder bør eksplisitt velge hvilke roller runnerne trenger. Dokumenter risikoen ved Contributor på subscription scope.

### 2c. Hardkodet subscription ID i demo

**Nåværende**: `demo/variables.tf` og `demo-storage.yml` har hardkodet subscription ID `61a5c972-...`.

**Anbefalt**: Fjern default-verdien fra variabelen. Bruk GitHub secrets i workflow.

---

## 3. Høy: Function App-forbedringer (hvis ACI-arkitekturen beholdes)

Disse punktene gjelder kun hvis dere velger å IKKE migrere til Container Apps Jobs.

### 3a. Migrer fra Y1 til Flex Consumption (FC1)

**Nåværende**: `sku_name = "Y1"` (Consumption plan).

**Anbefalt**: Flex Consumption (FC1). Microsoft anbefaler nå FC1 over Y1 for alle nye serverless Function Apps.

**Fordeler**:
- VNet-integrasjon (Y1 støtter det ikke)
- Raskere cold start med always-ready instances
- Skalerer til 1000 instanser (vs 200 for Y1)
- Managed identity for storage-tilkobling (se 3b)

**Terraform-støtte**: Offisielt støttet i azurerm provider. Se [Microsoft Terraform quickstart for Flex Consumption](https://learn.microsoft.com/azure/azure-functions/functions-create-first-function-terraform).

**Merk**: Kan ikke konvertere in-place — krever nye ressurser med nytt navn.

### 3b. Fjern storage access key — bruk managed identity

**Nåværende**: `storage_account_access_key = azurerm_storage_account.functions.primary_access_key`

**Anbefalt**: Bruk identity-basert tilkobling med `AzureWebJobsStorage__accountName` i stedet for connection string/access key. Tildel rollene `Storage Blob Data Contributor`, `Storage Queue Data Contributor`, og `Storage Table Data Contributor` til Function App sin managed identity.

**Kilde**: [Tutorial: Function App med managed identity for storage](https://learn.microsoft.com/azure/azure-functions/functions-identity-based-connections-tutorial)

### 3c. Fjern instrumentation key — bruk kun connection string

**Nåværende**: Bruker både `application_insights_connection_string` og `application_insights_key`.

**Anbefalt**: Fjern `application_insights_key`. Instrumentation key-basert ingestion mistet support 31. mars 2025. Bruk kun connection string.

**Kilde**: [Migrate from instrumentation keys to connection strings](https://learn.microsoft.com/azure/azure-monitor/app/migrate-from-instrumentation-keys-to-connection-strings)

---

## 4. Middels: Observability og compliance

### 4a. Legg til Log Analytics Workspace

**Nåværende**: Application Insights uten tilknyttet Log Analytics workspace.

**Anbefalt**: Opprett `azurerm_log_analytics_workspace` og koble Application Insights til den. Dette er nå standard for nye Application Insights-ressurser og gir bedre query-muligheter og data-retensjon.

### 4b. Legg til diagnostic settings

**Nåværende**: Ingen diagnostic settings på noen ressurser.

**Anbefalt**: Legg til `azurerm_monitor_diagnostic_setting` for:
- Key Vault (AuditEvent-logger — påkrevd av CIS Azure Benchmark)
- Service Bus namespace
- Function App / Container Apps Environment

**Kilde**: [CIS Azure Benchmark 5.3 — Diagnostic Logs](https://learn.microsoft.com/azure/azure-monitor/fundamentals/security-controls-policy), [Enable Key Vault logging](https://learn.microsoft.com/azure/key-vault/general/howto-logging)

### 4c. Legg til resource locks på kritiske ressurser

**Nåværende**: Ingen management locks.

**Anbefalt**: `CanNotDelete` lock på:
- Key Vault (inneholder GitHub App credentials)
- State storage account (Terraform state)

Gjør dette konfigurerbart via en variabel slik at kunder kan slå det av i dev-miljøer.

**Kilde**: [Microsoft anbefaler locks på storage accounts](https://learn.microsoft.com/azure/storage/common/lock-account-resource), [AVM Terraform lock interface](https://learn.microsoft.com/github/AvmGithubIo/azure.github.io/Azure-Verified-Modules/specs/tf/interfaces/#resource-locks)

---

## 5. Middels: GitHub Actions-forbedringer

### 5a. Legg til `terraform validate` i deploy workflow

**Nåværende**: `deploy.yml` kjører `init → plan → apply` uten validate.

**Anbefalt**: Legg til `terraform validate` mellom init og plan. Fanger syntaksfeil tidlig.

### 5b. Vurder GitHub Environment protection rules

**Nåværende**: `terraform apply -auto-approve` kjører automatisk på push til main.

**Anbefalt**: For en modul som brukes av flere kunder, vurder å legge til et GitHub Environment med required reviewers for produksjons-apply. Dokumenter dette som anbefalt oppsett.

### 5c. Pin GitHub Actions til SHA

**Nåværende**: Actions pinnet til major version (`@v4`, `@v2`, `@v3`).

**Anbefalt**: For en sikkerhetsbevisst modul, pin til full commit SHA for supply chain security. Legg til Dependabot for automatiske oppdateringer.

---

## 6. Middels: Python Function App-forbedringer

### 6a. Ikke eksponer exception-detaljer i HTTP-respons

**Nåværende**: `return func.HttpResponse(f"error: {exc}", status_code=500)`

**Anbefalt**: Returner en generisk feilmelding. Logg detaljer til Application Insights.

```python
except Exception:
    logging.exception("Webhook processing failed")
    return func.HttpResponse("internal error", status_code=500)
```

### 6b. Bruk `requests.Session()` for connection pooling

**Nåværende**: Oppretter ny HTTP-tilkobling for hvert ARM API-kall.

**Anbefalt**: Bruk en modul-nivå `requests.Session()` for å gjenbruke TCP-tilkoblinger. Gir bedre ytelse ved mange samtidige runner-operasjoner.

---

## 7. Lavt: Forenklinger for multi-kunde bruk

### 7a. Pakk som Terraform-modul

**Nåværende**: Flat repo-struktur med alle ressurser i rot `main.tf`.

**Anbefalt**: Strukturer som en ekte Terraform-modul med `modules/`-mappe slik at kunder kan konsumere den via `source = "github.com/..."` med versjonspinning. Legg til `examples/`-mappe med ferdig oppsett.

### 7b. Forenkle variabel-mengden

**Nåværende**: 25+ variabler, mange med navnekonvensjoner som kunden må følge manuelt.

**Anbefalt**: Reduser til et minimum av input-variabler (workload name, environment, location, subscription_id, github_org, github_repo) og generer alle ressursnavn automatisk via locals basert på CAF-konvensjoner. Behold muligheten for override via optional variabler.

### 7c. Opprett resource group i modulen

**Nåværende**: Resource group må eksistere på forhånd.

**Anbefalt**: Gi modulen en optional `create_resource_group` variabel (default `true`) som oppretter resource group. Forenkler onboarding for nye kunder.

---

## 8. Service-valg: Oppsummering

| Komponent | Nåværende | Anbefalt | Begrunnelse |
|-----------|-----------|----------|-------------|
| Runner compute | ACI | ACI (behold) | Docker-støtte kreves — Container Apps Jobs støtter ikke DinD |
| Orkestrering | Function App + Service Bus | Behold, men forbedre (FC1, managed identity) | Nødvendig for ACI-orkestrering |
| Function plan | Y1 Consumption | FC1 Flex Consumption | VNet, raskere cold start, managed identity storage |
| Container registry | ACR | ACR (behold) | Riktig valg for private runner images |
| Secrets | Key Vault | Key Vault (behold) | Riktig valg, godt konfigurert |
| State storage | Azure Blob | Azure Blob (behold) | Riktig valg med versioning og AAD auth |
| Monitoring | App Insights (standalone) | App Insights + Log Analytics Workspace | Bedre query og retensjon |

---

## Prioritert rekkefølge

1. **Fjern hardkodet subscription ID** fra demo (rask fix, sikkerhetshygiene)
2. **Stram inn RBAC** — runner workload roles og scaler scope
3. **Migrer til Flex Consumption (FC1)** — VNet, managed identity storage, raskere cold start
4. **Fjern storage access key** — bruk managed identity
5. **Legg til diagnostic settings og resource locks** (compliance)
6. **Fjern instrumentation key** — bruk kun connection string
7. **GitHub Actions hardening** — validate, environment protection, SHA pinning
8. **Modul-strukturering** for multi-kunde bruk
9. **Vurder Container Apps Jobs-variant** som alternativ for kunder uten Docker-behov
