.PHONY: help install run build deploy undeploy check-env check-config check-tools init-config create-infrastructure create-artifact-registry create-gke-cluster create-static-ip create-managed-certificate grant-iam-role test

# Global Configuration
APP_NAME := adk-agent
APP_NAMESPACE := $(APP_NAME)-ns
CONFIG_FILE := config.yaml

# Macro to extract values from config.yaml safely
# Usage in recipe: VAR=$(call get_config,section,key)
# Logic: Find section start, ignore subsequent lines starting with non-space (next section), find key, print value.
get_config = $$(awk '/^$(1):/{f=1;next} /^[a-zA-Z]/{f=0} f && /$(2):/{print $$2}' $(CONFIG_FILE) | tr -d '"')

# Helper to resolve the full image tag logic shared between build and deploy
# Expects BUILD_PROJECT, REPO_NAME, REPO_LOCATION, IMAGE_NAME to be set in the shell context
define resolve_image_tag
	REPO_LOCATION_FULL="$$REPO_LOCATION"; \
	if [[ "$$REPO_LOCATION_FULL" != *"pkg.dev"* ]] && [[ "$$REPO_LOCATION_FULL" != *"gcr.io"* ]]; then \
		REPO_LOCATION_FULL="$$REPO_LOCATION-docker.pkg.dev"; \
	fi; \
	IMAGE_TAG="$$REPO_LOCATION_FULL/$$BUILD_PROJECT/$$REPO_NAME/$$IMAGE_NAME:latest"
endef

help: ## Show this help message
	@echo "Usage: make <target>"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'

install: ## Install Python dependencies using uv
	uv sync

init-config: ## Initialize config.yaml from sample
	@if [ ! -f "$(CONFIG_FILE)" ]; then \
		echo "Creating $(CONFIG_FILE) from $(CONFIG_FILE).sample"; \
		cp $(CONFIG_FILE).sample $(CONFIG_FILE); \
	else \
		echo "$(CONFIG_FILE) already exists. Skipping init-config."; \
	fi

run: install ## Run the agent locally
	uv run uvicorn main:app --host 0.0.0.0 --port 8000

# --- Checks ---

check-config:
	@if [ ! -f "$(CONFIG_FILE)" ]; then \
		echo "Error: $(CONFIG_FILE) not found."; \
		echo "Run 'make init-config' and edit the file with your settings."; \
		exit 1; \
	fi

check-tools: ## Verify required tools (helm, gcloud) are installed
	@command -v helm >/dev/null 2>&1 || { echo "Error: helm not found. Install: https://helm.sh/docs/intro/install/"; exit 1; }
	@command -v gcloud >/dev/null 2>&1 || { echo "Error: gcloud not found. Install: https://cloud.google.com/sdk/docs/install"; exit 1; }

check-env: check-config check-tools

# --- Infrastructure ---

create-infrastructure: create-artifact-registry create-gke-cluster create-static-ip create-managed-certificate ## Create all infrastructure resources

create-artifact-registry: check-env ## Create the Artifact Registry repository
	@echo "Creating Artifact Registry repository..."
	@BUILD_PROJECT=$(call get_config,build,project); \
	REPO_NAME=$(call get_config,build,repository_name); \
	REPO_LOCATION=$(call get_config,build,repository_location); \
	if gcloud artifacts repositories describe $$REPO_NAME --location=$$REPO_LOCATION --project=$$BUILD_PROJECT >/dev/null 2>&1; then \
		echo "Repository '$$REPO_NAME' already exists."; \
	else \
		gcloud artifacts repositories create $$REPO_NAME --repository-format=docker --location=$$REPO_LOCATION --project=$$BUILD_PROJECT; \
	fi

create-gke-cluster: check-env ## Create the GKE Autopilot cluster
	@echo "Creating GKE cluster (this may take several minutes)..."
	@GKE_PROJECT=$(call get_config,deploy,gke_project); \
	GKE_REGION=$(call get_config,deploy,gke_region); \
	GKE_CLUSTER=$(call get_config,deploy,gke_cluster); \
	if gcloud container clusters describe $$GKE_CLUSTER --region=$$GKE_REGION --project=$$GKE_PROJECT >/dev/null 2>&1; then \
		echo "Cluster '$$GKE_CLUSTER' already exists."; \
	else \
		gcloud container clusters create-auto $$GKE_CLUSTER --project=$$GKE_PROJECT --location=$$GKE_REGION; \
	fi

create-static-ip: check-env ## Create the global static IP
	@echo "Creating static IP address..."
	@GKE_PROJECT=$(call get_config,deploy,gke_project); \
	STATIC_IP_NAME=$(call get_config,deploy,static_ip_name); \
	if gcloud compute addresses describe $$STATIC_IP_NAME --global --project=$$GKE_PROJECT >/dev/null 2>&1; then \
		echo "Static IP '$$STATIC_IP_NAME' already exists."; \
	else \
		gcloud compute addresses create $$STATIC_IP_NAME --global --ip-version=IPV4 --project=$$GKE_PROJECT; \
	fi

create-managed-certificate: check-env ## Create the Google-managed SSL certificate
	@echo "Creating managed certificate..."
	@GKE_PROJECT=$(call get_config,deploy,gke_project); \
	MANAGED_CERT_NAME=$(call get_config,deploy,managed_certificate_name); \
	A2A_HOST=$(call get_config,config,A2A_HOST); \
	if gcloud compute ssl-certificates describe $$MANAGED_CERT_NAME --project=$$GKE_PROJECT >/dev/null 2>&1; then \
		echo "Certificate '$$MANAGED_CERT_NAME' already exists."; \
	else \
		gcloud compute ssl-certificates create $$MANAGED_CERT_NAME --domains $$A2A_HOST --global --project=$$GKE_PROJECT; \
	fi

# --- Build & Deploy ---

build: check-env ## Build and submit the image to Cloud Build
	@echo "Building Docker image..."
	@BUILD_PROJECT=$(call get_config,build,project); \
	REPO_NAME=$(call get_config,build,repository_name); \
	REPO_LOCATION=$(call get_config,build,repository_location); \
	IMAGE_NAME=$(call get_config,build,image_name); \
	$(resolve_image_tag); \
	echo "  Image: $$IMAGE_TAG"; \
	gcloud builds submit . --tag=$$IMAGE_TAG --project=$$BUILD_PROJECT

deploy: check-env ## Deploy the application to GKE using Helm
	@echo "Authenticating with GKE..."
	@GKE_PROJECT=$(call get_config,deploy,gke_project); \
	GKE_REGION=$(call get_config,deploy,gke_region); \
	GKE_CLUSTER=$(call get_config,deploy,gke_cluster); \
	gcloud container clusters get-credentials $$GKE_CLUSTER --region $$GKE_REGION --project $$GKE_PROJECT
	@echo "Deploying Helm chart..."
	@BUILD_PROJECT=$(call get_config,build,project); \
	REPO_NAME=$(call get_config,build,repository_name); \
	REPO_LOCATION=$(call get_config,build,repository_location); \
	IMAGE_NAME=$(call get_config,build,image_name); \
	$(resolve_image_tag); \
	helm upgrade --install $(APP_NAME) ./helm --namespace $(APP_NAMESPACE) --create-namespace -f $(CONFIG_FILE) --set image=$$IMAGE_TAG

undeploy: check-tools ## Uninstall the Helm chart
	@echo "Uninstalling Helm chart..."
	helm uninstall $(APP_NAME) --namespace $(APP_NAMESPACE)

grant-iam-role: check-env ## Grant Vertex AI User role to the K8s Service Account
	@echo "Granting IAM role..."
	@GKE_PROJECT=$(call get_config,deploy,gke_project); \
	GCP_PROJECT_NUMBER=$$(gcloud projects describe $$GKE_PROJECT --format="value(projectNumber)"); \
	echo "  Project Number: $$GCP_PROJECT_NUMBER"; \
	gcloud projects add-iam-policy-binding $$GKE_PROJECT \
	  --member="principal://iam.googleapis.com/projects/$$GCP_PROJECT_NUMBER/locations/global/workloadIdentityPools/$$GKE_PROJECT.svc.id.goog/subject/ns/$(APP_NAMESPACE)/sa/$(APP_NAME)-sa" \
	  --role="roles/aiplatform.user" \
	  --condition=None

test: check-env ## Test access to the agent card
	@echo "Testing agent card access..."
	@A2A_HOST=$(call get_config,config,A2A_HOST); \
	A2A_PROTOCOL=$(call get_config,config,A2A_PROTOCOL); \
	A2A_PORT=$(call get_config,config,A2A_PORT); \
	AGENT_CARD_URL="$$A2A_PROTOCOL://$$A2A_HOST:$$A2A_PORT/.well-known/agent-card.json"; \
	set -e; \
	MAX_ATTEMPTS=10; \
	ATTEMPT=0; \
	until curl -sS --fail $$AGENT_CARD_URL >/dev/null; do \
		ATTEMPT=$$(($$ATTEMPT + 1)); \
		if [ $$ATTEMPT -ge $$MAX_ATTEMPTS ]; then \
			echo "Error: Agent card not reachable after $$MAX_ATTEMPTS attempts."; \
			exit 1; \
		fi; \
		echo "Attempt $$ATTEMPT: Agent card not yet reachable at $$AGENT_CARD_URL. Waiting 10 seconds..."; \
		sleep 10; \
	done; \
	echo "Success: Agent card is reachable at $$AGENT_CARD_URL"