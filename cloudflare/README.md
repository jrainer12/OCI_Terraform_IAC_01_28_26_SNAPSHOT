# Cloudflare + cert-manager + Gateway API (NGINX Gateway Fabric)

This guide explains how to configure Let's Encrypt certificates through Cloudflare and cert-manager **for Gateway API**, including HTTPS termination in **NGINX Gateway Fabric (NGF)**.

## Quick Start

The easiest way to set this up is using the automated GitHub Actions workflow:

1. **Install cert-manager** (one-time setup):
   ```bash
   helm repo add jetstack https://charts.jetstack.io
   helm repo update
   helm install cert-manager jetstack/cert-manager \
     --namespace cert-manager \
     --create-namespace \
     --set installCRDs=true
   ```

2. **Create Cloudflare API token secret**:
   ```bash
   kubectl create secret generic cloudflare-api-token \
     --from-literal=api-token=<YOUR_CLOUDFLARE_TOKEN> \
     -n cert-manager
   ```
   > Token requires: **Zone → DNS → Edit** access.

3. **Apply the ClusterIssuer**:
   ```bash
   kubectl apply -f cloudflare/clusterissuer.yaml
   ```
   > **Note**: Update the email in `clusterissuer.yaml` before applying.

4. **Deploy NGINX Gateway Fabric** (includes Gateway and Certificate):
   - Go to GitHub Actions → **Deploy NGINX Gateway Fabric** → Run workflow → `install`
   - This workflow will:
     - Install Gateway API CRDs
     - Install NGINX Gateway Fabric
     - Apply the Certificate (`k8s/gateway/rainercloud-certificate.yaml`)
     - Apply the shared Gateway (`k8s/gateway/gateway.yaml`)
     - Display the Gateway external IP when ready

---

## Manual Setup (Step-by-Step)

If you prefer to set up manually or need to customize:

### 1. Install cert-manager

Install cert-manager and its CRDs via Helm:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

Verify installation:
```bash
kubectl get pods -n cert-manager
```

### 2. Create Cloudflare API token secret

cert-manager needs a Cloudflare API token to solve DNS-01 challenges.

```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=<YOUR_CLOUDFLARE_TOKEN> \
  -n cert-manager
```

> **Token Requirements**: 
> - **Zone → DNS → Edit** access
> - Create a token at: https://dash.cloudflare.com/profile/api-tokens
> - Use "Edit zone DNS" template or create custom token with DNS:Edit permissions

### 3. Apply the ClusterIssuer

Apply your Let's Encrypt DNS-01 ClusterIssuer:

```bash
kubectl apply -f cloudflare/clusterissuer.yaml
```

**Before applying**, update the email in `clusterissuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
spec:
  acme:
    email: your@email.com  # ← Update this!
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

Verify:
```bash
kubectl get clusterissuer letsencrypt-cloudflare
```

### 4. Create a Certificate for your domain

Unlike Ingress, Gateway API **does not auto-generate Certificates**. You must create one explicitly.

The repository includes a Certificate resource at `k8s/gateway/rainercloud-certificate.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: rainercloud-com
  namespace: nginx-gateway
spec:
  secretName: rainercloud-com-tls
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-cloudflare
  dnsNames:
    - rainercloud.com
```

Apply it:

```bash
kubectl apply -f k8s/gateway/rainercloud-certificate.yaml
```

cert-manager will:

* Create `_acme-challenge` TXT entries via Cloudflare
* Request certificate from Let's Encrypt
* Store it in the `rainercloud-com-tls` secret
* **Automatically renew it** before expiration

Check certificate status:
```bash
kubectl get certificate -n nginx-gateway
kubectl describe certificate rainercloud-com -n nginx-gateway
```

### 5. Configure your Gateway to terminate HTTPS

The shared Gateway is defined in `k8s/gateway/gateway.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public-gateway
  namespace: nginx-gateway
spec:
  gatewayClassName: nginx
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
        - kind: Secret
          name: rainercloud-com-tls
      allowedRoutes:
        namespaces:
          from: All
```

Apply it:

```bash
kubectl apply -f k8s/gateway/gateway.yaml
```

The Gateway will:
* Listen on port 80 (HTTP) and 443 (HTTPS)
* Terminate TLS using the certificate from step 4
* Allow routes from all namespaces

Get the Gateway external IP:
```bash
kubectl get gateway public-gateway -n nginx-gateway
```

### 6. Create HTTPRoutes for your services

Your application Helm charts only need to define HTTPRoutes (not the Gateway or Certificate).

Example `values.yaml`:

```yaml
gateway:
  enabled: true
  parentRefs:
    - name: public-gateway
      namespace: nginx-gateway
      sectionName: https  # Use 'https' for TLS, 'http' for non-TLS
  hostnames:
    - rainercloud.com
  pathPrefix: "/backend/luma-syncer"
  backendPort: 5000
```

This generates an HTTPRoute that:

* Attaches to the shared Gateway
* Matches host `rainercloud.com`
* Routes `/backend/luma-syncer` to your app
* Uses HTTPS termination configured above

---

## Automated Deployment

The repository includes a GitHub Actions workflow (`deploy-nginx-gateway-fabric.yaml`) that automates steps 4-5:

1. **Prerequisites** (must be done manually first):
   - cert-manager installed
   - Cloudflare API token secret created
   - ClusterIssuer applied

2. **Run the workflow**:
   - Go to GitHub Actions → **Deploy NGINX Gateway Fabric**
   - Click **Run workflow** → Select `install`
   - The workflow will:
     - Install Gateway API CRDs (if not present)
     - Install/upgrade NGINX Gateway Fabric
     - Apply the Certificate
     - Apply the shared Gateway
     - Wait for and display the Gateway external IP

3. **Uninstall**:
   - Run the same workflow with `uninstall` action

---

## Troubleshooting

### Certificate not issuing

Check certificate status:
```bash
kubectl describe certificate rainercloud-com -n nginx-gateway
kubectl get certificaterequest -n nginx-gateway
kubectl get challenge -A
```

Common issues:
- **Cloudflare token invalid**: Verify secret exists and token has correct permissions
- **DNS not resolving**: Ensure domain DNS is managed by Cloudflare
- **Rate limiting**: Let's Encrypt has rate limits; wait if exceeded

### Gateway not getting external IP

Check Gateway status:
```bash
kubectl describe gateway public-gateway -n nginx-gateway
kubectl get svc -n nginx-gateway
```

Ensure NGINX Gateway Fabric is running:
```bash
kubectl get pods -n nginx-gateway
```

### Certificate not renewing

cert-manager automatically renews certificates. Check:
```bash
kubectl get certificate -n nginx-gateway -o yaml
```

Look for renewal timestamps in the status.

---

## Summary

| Component             | Description                                     | File/Resource                    |
| --------------------- | ----------------------------------------------- | -------------------------------- |
| cert-manager install  | Provides certificate automation                 | Helm chart                       |
| Cloudflare API secret | Allows DNS-01 verification                      | `kubectl create secret`          |
| ClusterIssuer         | Defines how cert-manager talks to Let's Encrypt | `cloudflare/clusterissuer.yaml`  |
| Certificate           | Explicitly defines domain + secret             | `k8s/gateway/rainercloud-certificate.yaml` |
| Gateway               | Provides HTTP/HTTPS listeners                   | `k8s/gateway/gateway.yaml`       |
| HTTPRoutes            | Routes traffic to services                      | Defined in application charts    |

**Key Points**:
- cert-manager handles automatic certificate renewal
- Gateway API requires explicit Certificate resources (unlike Ingress)
- The shared Gateway can be used by multiple HTTPRoutes across namespaces
- All resources are deployed via GitHub Actions workflow for consistency
