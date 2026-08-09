# Azure IIS VM + Angular Deployment

Provisions a Windows IIS VM on Azure with Terraform, then builds and deploys
an Angular app to it via GitHub Actions — no inbound access to the VM
required for deploys (uses `az vm run-command` over the Azure control plane).

## Folder structure

| Folder | Purpose |
|---|---|
| `infra/` | Terraform: resource group, NIC, public IP, NSG, Windows VM, and a `CustomScriptExtension` that installs IIS (`IIS.ps1`) |
| `angular-app/` | The Angular 18 application source |
| `deploy/` | Deployment-time assets: `Deploy-Angular.ps1` (runs on the VM to install a release) and `web.config` (IIS SPA routing rules) |
| `.github/workflows/` | `deploy-angular-iis.yml` — builds the Angular app and ships it to the VM on push to `main` |

## 1. Provision the VM (Terraform)

```bash
cd infra
az login
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your existing storage account / VNet / subnet names
terraform init
terraform plan
terraform apply
```

See [`infra/README.md`](infra/README.md) for full details, including the
health check `terraform apply` runs automatically.

## 2. Set up the GitHub Actions deploy pipeline

See [`deploy/README-deploy.md`](deploy/README-deploy.md) for the one-time
OIDC app registration, role assignments, and required GitHub secrets/variables
(also summarized below).

## 3. Develop the Angular app

```bash
cd angular-app
npm install
npm start        # local dev server
npm run build -- --configuration production
```

Pushing to `main` (with changes under `angular-app/**` or `deploy/**`)
triggers the deploy workflow automatically, or run it manually from the
**Actions** tab.

## Required GitHub configuration

**Secrets** (Settings → Secrets and variables → Actions → *Secrets*):

| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | App registration's client/application ID (OIDC) |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |

**Variables** (same page → *Variables*):

| Name | Value |
|---|---|
| `AZURE_RESOURCE_GROUP` | Resource group containing the VM |
| `AZURE_VM_NAME` | The VM's name |
| `AZURE_STORAGE_ACCOUNT` | Existing storage account used for release uploads |

No Azure passwords or service principal secrets are stored — the workflow
authenticates via OIDC federated credentials.
