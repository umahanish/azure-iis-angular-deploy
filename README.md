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
| `.github/workflows/` | `infra.yml` — Terraform plan/apply/destroy for the VM; `deploy-angular-iis.yml` — builds the Angular app and ships it to the VM on push to `main` |

## 1. Provision the VM (Terraform)

Either run it locally, or let `.github/workflows/infra.yml` do it (recommended
once OIDC is set up — see below): PRs touching `infra/**` get an automatic
`plan`, merges to `main` run `plan` then a manually-approved `apply`.

```bash
cd infra
az login
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your existing storage account / VNet / subnet names
cp backend.hcl.example backend.hcl
# edit backend.hcl to point at your existing storage account (for remote state)
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

See [`infra/README.md`](infra/README.md) for full details, including the
health check `terraform apply` runs automatically and the CI pipeline.

## 2. Set up the GitHub Actions pipelines

See [`deploy/README-deploy.md`](deploy/README-deploy.md) for the one-time
OIDC app registration and role assignments. Full secrets/variables/environment
setup for **both** workflows (`infra.yml` and `deploy-angular-iis.yml`) is
below.

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

Both workflows share one Azure AD app registration (OIDC, no stored Azure
passwords) and one existing storage account (release uploads **and**
Terraform state, in separate containers).

**Secrets** (Settings → Secrets and variables → Actions → *Secrets*):

| Name | Used by | Value |
|---|---|---|
| `AZURE_CLIENT_ID` | both | App registration's client/application ID (OIDC) |
| `AZURE_TENANT_ID` | both | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | both | Azure subscription ID |
| `VM_ADMIN_PASSWORD` | `infra.yml` | Windows admin password for the VM (`TF_VAR_admin_password`) — meet Azure's complexity requirements |

**Variables** (same page → *Variables*):

| Name | Used by | Value |
|---|---|---|
| `AZURE_RESOURCE_GROUP` | both | Resource group containing the VM (default `rg-iis-demo` if unset) |
| `AZURE_VM_NAME` | `deploy-angular-iis.yml` | The VM's name |
| `AZURE_STORAGE_ACCOUNT` | both | Existing storage account (releases + Terraform state) |
| `TF_BACKEND_RESOURCE_GROUP` | `infra.yml` | Resource group that contains `AZURE_STORAGE_ACCOUNT` |
| `EXISTING_VNET_NAME` | `infra.yml` | Existing VNet the VM's NIC attaches to |
| `EXISTING_VNET_RG` | `infra.yml` | Resource group containing that VNet |
| `EXISTING_SUBNET_NAME` | `infra.yml` | Existing subnet within that VNet |
| `TF_BACKEND_CONTAINER` | `infra.yml` | *(optional)* state container name, default `tfstate` |
| `TF_BACKEND_KEY` | `infra.yml` | *(optional)* state file name, default `iis-demo.tfstate` |
| `AZURE_LOCATION`, `AZURE_PREFIX`, `AZURE_VM_SIZE`, `AZURE_ADMIN_USERNAME`, `ALLOWED_RDP_SOURCE` | `infra.yml` | *(optional)* override the defaults in `infra/variables.tf` |

### Federated credentials (OIDC)

Each distinct GitHub job "shape" produces a different OIDC subject claim —
`environment:` on a job overrides the ref-based subject entirely. Create one
federated credential per subject on the **same** app registration:

| Workflow / job | Subject |
|---|---|
| `deploy-angular-iis.yml` → `deploy` (`environment: production`) | `repo:<org>/<repo>:environment:production` |
| `infra.yml` → `plan` on pull requests | `repo:<org>/<repo>:pull_request` |
| `infra.yml` → `plan` on push to `main` | `repo:<org>/<repo>:ref:refs/heads/main` |
| `infra.yml` → `apply` / `destroy` (`environment: infra-production`) | `repo:<org>/<repo>:environment:infra-production` |

```bash
az ad app federated-credential create --id <appId> --parameters '{
  "name": "gh-actions-infra-pr", "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/<repo>:pull_request", "audiences": ["api://AzureADTokenExchange"] }'

az ad app federated-credential create --id <appId> --parameters '{
  "name": "gh-actions-infra-main", "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/<repo>:ref:refs/heads/main", "audiences": ["api://AzureADTokenExchange"] }'

az ad app federated-credential create --id <appId> --parameters '{
  "name": "gh-actions-infra-apply", "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/<repo>:environment:infra-production", "audiences": ["api://AzureADTokenExchange"] }'
```

### Role assignments

In addition to the roles in [`deploy/README-deploy.md`](deploy/README-deploy.md)
(`Virtual Machine Contributor` on the VM's resource group, `Storage Blob Data
Contributor` on the storage account), `infra.yml` also needs:

| Scope | Role | Why |
|---|---|---|
| Subscription | `Contributor` | creates the new resource group + VM/NIC/NSG/public IP (the RG doesn't exist yet, so scoping narrower isn't possible until after the first apply) |

### GitHub Environment (manual approval gate)

`infra.yml`'s `apply`/`destroy` jobs target the `infra-production`
Environment. Create it under **Settings → Environments → New environment**,
name it `infra-production`, and add yourself (or a reviewer) as a **required
reviewer** — otherwise the environment exists but nothing blocks `apply` from
running immediately after `plan`.
