# Deploying the Angular App to IIS via GitHub Actions

`.github/workflows/deploy-angular-iis.yml` builds the Angular app and ships
it to the IIS VM with **no inbound access to the VM required** — it uses
`az vm run-command`, which runs through the Azure control plane.

## How it works

1. **build job** (`ubuntu-latest`, working directory `angular-app/`): `npm ci`
   → `ng build --configuration production` → drops in `../deploy/web.config`
   (SPA routing rules) → zips the output → uploads it as a workflow artifact.
2. **deploy job**:
   - Logs into Azure via OIDC (`azure/login`, no stored secrets/passwords).
   - Uploads `release.zip` to a `releases` container in your existing
     storage account, using Azure AD auth only (no account keys).
   - Generates a short-lived (30 min), read-only **user-delegation SAS**
     URL for that blob.
   - Calls `az vm run-command invoke` to run `deploy/Deploy-Angular.ps1`
     **on the VM**, which downloads the zip, backs up the current site,
     `robocopy /MIR`s the new files into `C:\inetpub\wwwroot`, and recycles
     the app pool. It rolls back from the backup automatically if anything
     in the deploy step throws.
   - Curls the VM's public IP afterward and fails the job if it's not
     HTTP 200.

## One-time setup

### 1. Angular build output path
Edit `ANGULAR_DIST_PATH` in the workflow to match your project:
- Angular 17+ (esbuild/application builder): `dist/<project-name>/browser`
- Older builders: `dist/<project-name>`

Check `angular.json` → `projects.<name>.architect.build.options.outputPath`
if you're not sure.

### 2. Azure AD app registration for OIDC login
```bash
az ad app create --display-name "gh-actions-iis-deploy"
# note the appId (client-id) and create a federated credential trusting
# your repo/branch:
az ad app federated-credential create \
  --id <appId> \
  --parameters '{
    "name": "gh-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<org>/<repo>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
az ad sp create --id <appId>
```

### 3. Role assignments for that service principal
| Scope | Role | Why |
|---|---|---|
| VM's resource group | `Virtual Machine Contributor` (or a custom role with just `Microsoft.Compute/virtualMachines/runCommand/action`) | lets `az vm run-command` execute the deploy script |
| Storage account | `Storage Blob Data Contributor` | upload the release zip + generate the user-delegation SAS |

```bash
az role assignment create --assignee <appId> --role "Virtual Machine Contributor" \
  --scope "/subscriptions/<sub>/resourceGroups/<vm-rg>"

az role assignment create --assignee <appId> --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<sub>/resourceGroups/<storage-rg>/providers/Microsoft.Storage/storageAccounts/<storage-account>"
```

### 4. GitHub repo configuration
**Secrets** (Settings → Secrets and variables → Actions → Secrets):
| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | the app registration's client/application ID |
| `AZURE_TENANT_ID` | your Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | your subscription ID |

**Variables** (same page → Variables):
| Name | Value |
|---|---|
| `AZURE_RESOURCE_GROUP` | resource group containing the VM (e.g. `rg-iis-demo`) |
| `AZURE_VM_NAME` | the VM name (e.g. `iisdemo-vm`) |
| `AZURE_STORAGE_ACCOUNT` | your existing storage account name |

### 5. Re-run (or update) the VM extension once
The URL Rewrite module install was added to `IIS.ps1`. If the VM was
already provisioned before this change, re-apply the Custom Script
Extension (`terraform apply` again — it re-runs on script content change)
or install the module manually so Angular routing works:
```powershell
Invoke-WebRequest -Uri "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi" -OutFile C:\rewrite.msi
Start-Process msiexec.exe -ArgumentList "/i C:\rewrite.msi /qn /norestart" -Wait
```

## Triggering a deploy
Push to `main`, or run it manually from the **Actions** tab
(`workflow_dispatch`).

## Notes
- Deployments are idempotent and safe to re-run — each run creates its own
  timestamped backup under `C:\iis-backups` on the VM before overwriting
  `C:\inetpub\wwwroot`.
- If you'd rather deploy on every PR/tag instead of every push to `main`,
  adjust the `on:` trigger.
- If you don't want to set up OIDC, you can swap `azure/login`'s `with:`
  block for a classic `creds: ${{ secrets.AZURE_CREDENTIALS }}` service
  principal JSON secret instead — say so and I'll switch it.
