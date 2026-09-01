# Basic example

Smallest possible call of the `modules/runners` module. Local state, literal values, no CI/CD.

```bash
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

terraform init
terraform plan
```

Edit `github_org`, `github_repo`, and the naming inputs in `main.tf` before applying.

`terraform apply` provisions the infrastructure only. Two manual steps follow, both covered in the [module README](../../README.md):

1. Import the runner image into ACR and deploy the [`scaler-function/`](../../scaler-function) code to the Function App
2. Store the GitHub App secrets in Key Vault and register the webhook

## Looking for a full setup?

For remote state, OIDC authentication, and a workflow that wires all of the above together, use the reference consumer repository:

**[patrickthor/github-runner-customer-demo](https://github.com/patrickthor/github-runner-customer-demo)**

It contains a ready-to-copy `deploy-runners.yml` that runs Terraform, imports the runner image, and deploys the scaler function in one pipeline — plus a `storage-demo` workflow for verifying the runners once they are live.
