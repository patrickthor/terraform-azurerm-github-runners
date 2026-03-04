# ==============================================================================
# Three-step deployment workflow
#
#   make bootstrap   — provision (or adopt) the remote-state storage account
#   make infra        — initialise the remote backend and apply main infra
#   make deploy       — publish the Function App code via Azure Functions Core Tools
#   make all          — run all three steps in order
#
# Prerequisites:
#   - az login (or workload-identity env vars set)
#   - terraform >= 1.0
#   - Azure Functions Core Tools v4 (npm i -g azure-functions-core-tools@4)
#   - backend.hcl present at repo root (copy from backend.hcl.example)
# ==============================================================================

FUNCTION_APP_NAME ?= func-runner-poc-bvt
RESOURCE_GROUP    ?= rg-runner-poc-bvt
BOOTSTRAP_DIR     := bootstrap
SCALER_DIR        := scaler-function

.PHONY: all bootstrap infra deploy clean

all: bootstrap infra deploy

# ------------------------------------------------------------------
# Step 1 — Remote-state foundation
# ------------------------------------------------------------------
bootstrap:
	@echo "==> [1/3] Bootstrap: provisioning state storage..."
	@cd $(BOOTSTRAP_DIR) && \
	  [ -f terraform.tfvars ] || (echo "ERROR: copy bootstrap/terraform.tfvars.example to bootstrap/terraform.tfvars first" && exit 1)
	cd $(BOOTSTRAP_DIR) && terraform init -input=false
	cd $(BOOTSTRAP_DIR) && terraform apply -auto-approve
	@echo ""
	@echo "==> Bootstrap done. If backend.hcl does not exist yet, run:"
	@echo "    cd $(BOOTSTRAP_DIR) && terraform output -raw backend_hcl_snippet > ../backend.hcl"
	@echo ""

# ------------------------------------------------------------------
# Step 2 — Main infrastructure
# ------------------------------------------------------------------
infra:
	@echo "==> [2/3] Infrastructure: initialising remote backend and applying..."
	@[ -f backend.hcl ] || (echo "ERROR: backend.hcl not found — see backend.hcl.example" && exit 1)
	@[ -f terraform.tfvars ] || (echo "ERROR: terraform.tfvars not found — see terraform.tfvars.example" && exit 1)
	terraform init -input=false -backend-config=backend.hcl
	terraform apply -auto-approve
	@echo ""

# ------------------------------------------------------------------
# Step 3 — Function App code deploy
# ------------------------------------------------------------------
deploy:
	@echo "==> [3/3] Code deploy: publishing scaler function..."
	cd $(SCALER_DIR) && func azure functionapp publish $(FUNCTION_APP_NAME) --python --build remote
	@echo ""

# ------------------------------------------------------------------
# Utility
# ------------------------------------------------------------------

# Migrate an existing state: remove the storage account from the old managed
# resource so Terraform no longer tries to manage what bootstrap owns.
migrate-state:
	@echo "==> Migrating state: removing azurerm_storage_account.storage from main module state..."
	terraform state rm azurerm_storage_account.storage || true
	@echo "==> Done. Re-run 'make infra' to re-initialise the remote backend."

clean:
	rm -rf .terraform bootstrap/.terraform
	rm -f .terraform.lock.hcl bootstrap/.terraform.lock.hcl
