# ADK / A2A / GKE Sample Agent

This repository provides a reference implementation for deploying a Google ADK (Agent Development Kit) Agent to Google Kubernetes Engine (GKE).

The sample agent uses the **Gemini 2.5 Flash** model to answer questions about time and weather in specified cities, demonstrating **Agent-to-Agent (A2A)** communication protocols.

## Features
- **ADK Agent**: Built with `google-adk`, utilizing function calling (tools) for weather and time.
- **GKE Autopilot**: Deploys to a fully managed Kubernetes environment.
- **Secure Access**: Configures a Global Static IP and Google-managed SSL Certificate for secure A2A communication.
- **Automated Workflow**: Includes a `Makefile` for streamlined infrastructure setup, building, and deployment.


## Prerequisites

- **[Google Cloud SDK](https://cloud.google.com/sdk/docs/install)** (`gcloud`)
- **[Helm](https://helm.sh/docs/intro/install/)**
- **[uv](https://github.com/astral-sh/uv)** (Python package manager)
- **Make**

## Quick Start

### 1. Configuration

Initialize the configuration file and edit it with your environment details:

```bash
make init-config
```

> **Action Required:** Open `config.yaml` and replace all placeholders (e.g., `your-gcp-project-id`, `your-region`, `your-a2a-host`) with your actual values.

### 2. Infrastructure Setup

Provision the necessary Google Cloud resources. You can run these commands sequentially to set up the environment:

```bash
# Create Artifact Registry for storing images
make create-artifact-registry

# Create GKE Autopilot Cluster
make create-gke-cluster

# Reserve a Global Static IP
make create-static-ip

# Provision a Managed SSL Certificate
make create-managed-certificate
```

### 3. Build & Deploy

Build the container image and deploy the Helm chart:

```bash
# Submit build to Cloud Build
make build

# Deploy to GKE
make deploy
```

> **Note:** The deployment uses the Global Static IP and Managed Certificate created in step 2. SSL certificate provisioning by Google can take 15-60 minutes to become active.

### 4. Post-Deployment: Grant Permissions

**Crucial Step:** After the initial deployment, authorize the Kubernetes Service Account to access Vertex AI:

```bash
make grant-iam-role
```
*This step links the Kubernetes Service Account to the Google Cloud Service Account, allowing the agent to invoke the Gemini model.*

## Verification

1.  **Automated Test**: Run the automated test to check if the agent card is reachable:
    ```bash
    make test
    ```
2.  **Agent Card (Manual)**: Visit your agent's endpoint to manually inspect its capability card:
    ```
    https://<YOUR_A2A_HOST>/.well-known/agent-card.json
    ```
3.  **A2A Inspector**: Validate and test the agent using the [A2A Inspector tool](https://goo.gle/a2a-inspector-app).

## Register the Agent

Once deployed and verified, you can [register your agent with Gemini Enterprise](https://docs.cloud.google.com/gemini/enterprise/docs/register-and-manage-an-a2a-agent#register-agent).

## Local Development

Run the agent locally for rapid testing:

1.  **Authenticate**: Ensure you have credentials for Vertex AI:
    ```bash
    gcloud auth application-default login
    ```
2.  **Run**:
    ```bash
    make run
    ```

Access the local agent card at: `http://localhost:8000/.well-known/agent-card.json`

## Cleanup

To uninstall the Helm chart and remove the application from your cluster:

```bash
make undeploy
```

To completely remove all infrastructure resources created by this project (GKE cluster, Static IP, SSL Certificate, Artifact Registry):

```bash
make destroy
```
