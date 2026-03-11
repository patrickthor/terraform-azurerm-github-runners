---
inclusion: auto
---

# Product Overview

Event-driven ephemeral GitHub Actions runner platform on Azure. Automatically scales Azure Container Instance (ACI) runners in response to GitHub webhook events.

## Core Functionality

- Receives GitHub workflow_job webhooks via Azure Function App
- Queues scale requests through Service Bus
- Dynamically creates/destroys ephemeral ACI runners on demand
- Authenticates via GitHub App (not PAT)
- Runners are ephemeral, single-use, and auto-cleanup after job completion

## Key Components

- Azure Function App (Python 3.11) with three functions:
  - `github_webhook`: HTTP trigger for GitHub events
  - `scale_worker`: Service Bus trigger for runner provisioning
  - `cleanup_timer`: Timer trigger (every 5 min) for stale runner removal
- Azure Container Registry (ACR) for runner images
- Azure Container Instances (ACI) for ephemeral runners
- Service Bus queue for scale request buffering
- Key Vault for GitHub App credentials

## Architecture Pattern

Webhook → Function → Queue → Worker → ACI Runners

Runners pull from ACR using managed identity, execute jobs, and self-terminate.
