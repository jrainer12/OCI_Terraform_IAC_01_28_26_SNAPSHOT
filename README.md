# OCI Terraform Infrastructure as Code

Terraform configuration for deploying a free managed Kubernetes cluster (OKE) on Oracle Cloud Infrastructure using Always Free tier resources, with automated CI/CD pipelines for cluster management, ingress deployment, and Cloudflare IP updates.

## Overview

This repository contains Terraform code and GitHub Actions workflows to provision and manage:
- Oracle Kubernetes Engine (OKE) cluster
- Complete networking setup (VCN, subnets, route tables, security lists)
- Node pool with ARM-based (A1.Flex) worker nodes
- NGINX Gateway Fabric (Gateway API) deployment
- Automated Cloudflare IP range updates
- cert-manager integration with Let's Encrypt via Cloudflare DNS-01

## Resources

- **Guide**: Based on [Create Free Managed Kubernetes Cluster in Oracle Cloud with Terraform](https://blog.digitalnostril.com/post/create-free-managed-kubernetes-cluster-in-oracle-cloud/)

## Prerequisites

- Oracle Cloud account with Always Free tier
- OCI API credentials (tenancy OCID, user OCID, API key, fingerprint)
- GitHub repository with secrets configured (for CI/CD)
- Cloudflare account (for DNS-01 certificate validation)

## Setup

1. **Configure `terraform.tfvars`**:
   ```hcl
   region = "us-ashburn-1"
   region_identifier = "IAD"
   kubernetes_version = "v1.34.1"
   image_id = "ocid1.image.oc1.us-ashburn-1.aaaaaaa..."  # Get from OCI Console
   ```

2. **Create Object Storage Bucket** (for Terraform state):
   - Go to OCI Console → Object Storage → Buckets
   - Click **Create Bucket**
   - Name: `terraform-state`
   - Storage Tier: **Standard**
   - Click **Create**

3. **Create S3-Compatible Access Keys** (for Terraform state backend):
   - Go to OCI Console → Identity → Users → Your User
   - Click **Customer Secret Keys** (or **Access Keys**)
   - Click **Generate Secret Key**
   - **Save both the Access Key ID and Secret Access Key** (you won't see the secret again!)
   - These are different from your OCI API keys - they're specifically for S3-compatible access

4. **Set GitHub Secrets** (for CI/CD):
   - `TF_VAR_COMPARTMENT_OCID`
   - `OCI_TENANCY_OCID`
   - `OCI_USER_OCID`
   - `OCI_FINGERPRINT`
   - `OCI_REGION`
   - `OCI_PRIVATE_KEY_BASE64` (base64-encoded API private key)
   - `OCI_OBJECT_STORAGE_NAMESPACE` (your Object Storage namespace - get it from OCI Console → Object Storage → Buckets, or run `oci os ns get --query "data" --raw-output`)
   - `OCI_S3_ACCESS_KEY_ID` (S3-compatible access key ID from step 3)
   - `OCI_S3_SECRET_ACCESS_KEY` (S3-compatible secret access key from step 3)

5. **Run Terraform** (or use GitHub Actions):
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

## GitHub Actions Workflows

This repository includes multiple GitHub Actions workflows for automated infrastructure management:

### 1. Deploy OCI Free OKE (`oci-free-aks.yaml`)

**Main pipeline for cluster provisioning and management.**

- **Triggers**: Manual workflow dispatch
- **Actions**: `apply` or `destroy`
- **Features**:
  - Provisions OKE cluster and node pools
  - Handles retries for capacity issues (up to 3 attempts)
  - Option to skip node pool creation when at capacity
  - Waits for nodes to be ready
  - Generates and uploads kubeconfig artifact
  - Uses Terraform 1.5.7 (pinned to avoid AWS chunked encoding issues with OCI S3-compat API)

**Usage**: 
- Go to Actions → Deploy-OCI-Free-OKE → Run workflow
- Select `apply` to create or `destroy` to tear down
- Optionally check "Skip node pool" if experiencing capacity issues

### 2. Update Cloudflare IPs (`update-cloudflare-ips.yaml`)

**Automated daily update of Cloudflare IPv4 CIDR ranges.**

- **Triggers**: 
  - Scheduled: Daily at 7am UTC
  - Manual: Workflow dispatch
- **Features**:
  - Fetches latest Cloudflare IPv4 ranges from `https://www.cloudflare.com/ips-v4`
  - Updates `network.tf` with new CIDR ranges using Python script
  - Only commits and applies if changes are detected
  - Automatically runs Terraform apply (skipping node pool) to update security rules

**Usage**: Runs automatically daily, or trigger manually from Actions tab.

### 3. Deploy NGINX Gateway Fabric (`deploy-nginx-gateway-fabric.yaml`)

**Deploys NGINX Gateway Fabric (Gateway API implementation) with TLS termination.**

- **Triggers**: Manual workflow dispatch
- **Actions**: `install` or `uninstall`
- **Options**:
  - `service_mode`: Choose how to expose the Gateway:
    - **LoadBalancer** (default): Uses OCI Network Load Balancer (~$0.50/day)
    - **CloudflareTunnel**: Uses Cloudflare Tunnel (free, more reliable!)
- **Features**:
  - Installs Gateway API CRDs (standard channel v1.4.0)
  - Installs NGINX Gateway Fabric via Helm
  - Applies shared Gateway resource with HTTP/HTTPS listeners
  - Applies TLS Certificate for rainercloud.com (LoadBalancer mode)
  - Deploys cloudflared for Cloudflare Tunnel (CloudflareTunnel mode)
  - Uses reusable GitHub Actions from `jrainer12/Reusable_GitHub_Actions`

**Prerequisites**: 
- Cluster must be deployed first (via `oci-free-aks.yaml`)
- **LoadBalancer mode**: cert-manager must be installed (see `cloudflare/README.md`)
- **CloudflareTunnel mode**: `CLOUDFLARE_TUNNEL_TOKEN` secret must be set (see below)

**Usage**: 
- Go to Actions → Deploy NGINX Gateway Fabric → Run workflow
- Select `install` to deploy or `uninstall` to remove
- Choose service mode based on cost/preference

#### Cloudflare Tunnel Setup (recommended for cost savings)

Cloudflare Tunnel eliminates the need for an OCI Load Balancer, saving ~$15/month.

**Step 1: Create a Cloudflare Tunnel**

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com) → Zero Trust → Networks → Tunnels
2. Click **Create a tunnel** → Select **Cloudflared**
3. Name it (e.g., `nginx-gateway-tunnel`)
4. **Copy the tunnel token** (you'll need this for the GitHub secret)

**Step 2: Configure the tunnel's Public Hostname**

In the tunnel configuration, add a public hostname:
- **Domain**: `rainercloud.com`
- **Path**: (leave empty)
- **Service**: `http://public-gateway-nginx.nginx-gateway.svc.cluster.local:80`

**Step 3: Add GitHub Secret**

Add the tunnel token as a GitHub secret:
- Secret name: `CLOUDFLARE_TUNNEL_TOKEN`
- Value: The token you copied in Step 1

**Step 4: Update DNS (automatic or manual)**

Cloudflare can automatically create the DNS record, or you can do it manually:
- **Type**: CNAME
- **Name**: `rainercloud.com` (or `@`)
- **Target**: `<tunnel-id>.cfargotunnel.com`
- **Proxy**: Enabled (orange cloud)

**Step 5: Run the pipeline**

Select `CloudflareTunnel` as the service mode and run the workflow!

### 4. Gateway API Deploy (`gateway-api-deploy.yaml`)

**Manages Gateway API CRDs independently.**

- **Triggers**: Manual workflow dispatch
- **Actions**: `install` or `uninstall`
- **Channels**: `standard` or `experimental`
- **Features**:
  - Installs/uninstalls Gateway API CRDs (v1.4.0)
  - Supports both standard and experimental channels
  - Verifies installation by listing CRDs and GatewayClasses

**Usage**: 
- Go to Actions → Manage Gateway API CRDs → Run workflow
- Select action and channel

### 5. Deploy Prometheus (`deploy-prometheus.yaml`)

**Deploys Prometheus monitoring stack with optional Grafana dashboard.**

- **Triggers**: Manual workflow dispatch
- **Actions**: `install` or `uninstall`
- **Options**:
  - `include_grafana`: Include Grafana dashboard (default: true)
- **Features**:
  - Installs kube-prometheus-stack via Helm (Prometheus Community charts)
  - Includes Prometheus, Alertmanager, and Node Exporter
  - Optional Grafana dashboard with persistence
  - Configures 30-day retention and 20Gi storage for Prometheus
  - Waits for all components to be ready
  - Displays access instructions including port-forward commands and Grafana credentials

**Prerequisites**: 
- Cluster must be deployed first (via `oci-free-aks.yaml`)

**Usage**: 
- Go to Actions → Deploy Prometheus → Run workflow
- Select `install` to deploy or `uninstall` to remove
- Optionally uncheck "Include Grafana" if you only want Prometheus

**Access**:
- Prometheus UI: `kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090`
- Grafana UI: `kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80`
  - Default username: `admin`
  - Password: Check secret `kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d`

#### Loki logging (optional)

If you enable `include_loki`, the pipeline installs:
- Loki (single-binary)
- Grafana Alloy (DaemonSet) for log collection

**Grafana datasource setup (Loki)**:
- **URL**: `http://loki:3100`
- **If you see `401 Unauthorized`**: add an HTTP header `X-Scope-OrgID: 1` (some Loki configs enable multi-tenancy).

**Query tips**:
- If you don’t see anything at first, set your time range to **Last 15 minutes**.
- Start with labels that definitely exist: `{namespace="rainercloud"}` or `{namespace="nginx-gateway"}`.

Quick validation from the Grafana pod:
```bash
kubectl exec -n monitoring deploy/prometheus-grafana -c grafana -- sh -lc 'wget -qO- http://loki:3100/ready'
kubectl exec -n monitoring deploy/prometheus-grafana -c grafana -- sh -lc 'wget -S -O- http://loki:3100/loki/api/v1/labels'
```

### 6. Deploy Nginx Ingress (`deploy-nginx.yaml`) - **Deprecated**

**Legacy ingress-nginx deployment (deprecated in favor of NGINX Gateway Fabric).**

- **Status**: Deprecated - use `deploy-nginx-gateway-fabric.yaml` instead
- **Features**: 
  - Installs ingress-nginx with Network Load Balancer
  - Configures snippet annotations support
  - Re-applies Terraform for security rules

## Scripts

### `scripts/update_cloudflare_ips.py`

Python script that updates Cloudflare IPv4 CIDR ranges in `network.tf`.

**How it works**:
1. Reads IPv4 ranges from `cf_ipv4.txt`
2. Finds `cloudflare_ipv4_cidrs` local variable in `network.tf`
3. Replaces the CIDR list with updated values
4. Only writes if changes are detected

**Usage**: 
- Called automatically by `update-cloudflare-ips.yaml` workflow
- Can be run manually: `python3 scripts/update_cloudflare_ips.py`

## Kubernetes Resources

### Gateway API Resources

- **`k8s/gateway/gateway.yaml`**: Shared Gateway resource with HTTP/HTTPS listeners
- **`k8s/gateway/rainercloud-certificate.yaml`**: Certificate resource for rainercloud.com domain

### cert-manager Resources

- **`cloudflare/clusterissuer.yaml`**: ClusterIssuer for Let's Encrypt with Cloudflare DNS-01 solver

### Service Accounts

- **`SA_Accounts/rainercloud/rainercloud-github-deployer.yaml`**: ServiceAccount and RBAC for GitHub Actions deployments in the `rainercloud` namespace

See `cloudflare/README.md` for detailed cert-manager setup instructions.

## Always Free Tier Limits

- **1 OKE cluster** per tenancy
- **4 ARM (A1.Flex) instances** - 1 OCPU / 6 GB RAM each
- **Total**: 4 OCPUs, 24 GB RAM

## Known Issues

### Out of Host Capacity

ARM instances on Always Free tier can experience capacity issues. The main workflow includes automatic retry logic. If you encounter this:

1. **Use skip_node_pool option** - Deploy cluster first, add nodes later
2. **Wait and retry** - Capacity often frees up within hours
3. **Try off-peak hours** - Better availability
4. **Temporarily reduce nodes** - Start with 1-2 nodes, scale up later

### Terraform State

The configuration supports OCI Object Storage as a remote backend (using the free 10 GiB tier). This provides:
- **State persistence** across CI/CD runs
- **Team collaboration** with shared state
- **Automatic backups** in OCI's durable storage

If you prefer local state, you can change the backend in `main.tf`.

## Scaling

To scale the node pool after creation:
- Edit `kubernetes.tf` and change `size = 4` to your desired count
- Run `terraform apply` or use the `oci-free-aks.yaml` workflow
- Or use OCI Console: Cluster → Node Pools → pool1 → Edit

## Project Structure

```
.
├── .github/workflows/
│   ├── oci-free-aks.yaml              # Main cluster deployment workflow
│   ├── update-cloudflare-ips.yaml     # Automated Cloudflare IP updates
│   ├── deploy-nginx-gateway-fabric.yaml  # NGINX Gateway Fabric deployment
│   ├── gateway-api-deploy.yaml        # Gateway API CRD management
│   ├── deploy-prometheus.yaml         # Prometheus monitoring stack deployment
│   └── deploy-nginx.yaml               # Legacy ingress-nginx (deprecated)
├── cloudflare/
│   ├── clusterissuer.yaml             # cert-manager ClusterIssuer
│   └── README.md                      # cert-manager setup guide
├── k8s/
│   └── gateway/
│       ├── gateway.yaml               # Shared Gateway resource
│       └── rainercloud-certificate.yaml  # TLS Certificate
├── SA_Accounts/
│   └── rainercloud/
│       └── rainercloud-github-deployer.yaml  # ServiceAccount for deployments
├── scripts/
│   └── update_cloudflare_ips.py       # Cloudflare IP update script
├── availability-domains.tf             # Availability domain data source
├── kubernetes.tf                      # OKE cluster and node pool
├── main.tf                            # Terraform backend configuration
├── network.tf                         # VCN, subnets, route tables, security lists
├── providers.tf                       # OCI provider configuration
├── terraform.tfvars                   # Variable values (not committed)
├── variables.tf                       # Variable definitions
├── versions.tf                        # Provider version constraints
└── cf_ipv4.txt                        # Cloudflare IPv4 ranges (auto-updated)
```

