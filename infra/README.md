# Azure IIS VM via Terraform — existing Storage Account + VNet/Subnet

Deploys:

- New resource group (for the VM, NIC, public IP, NSG)
- **Existing** storage account (`data` source) — a private container +
  `IIS.ps1` blob are created/uploaded inside it
- **Existing** VNet + subnet (`data` sources) — the VM's NIC is attached here
- New NSG allowing inbound **HTTP (80)**, and optionally RDP (3389)
- New **Standard, static Public IP**
- Windows Server 2022 VM
- `CustomScriptExtension` that downloads `IIS.ps1` from the storage account
  (authenticated via the storage account key, only in `protected_settings`)
  and runs it to install/configure IIS
- A `null_resource` that **curls the public IP after deployment** and writes
  the result to `iis_health_check.txt`, surfaced as the `iis_health_check`
  Terraform output — so `terraform apply` tells you whether the site is
  actually up.

## Files

| File | Purpose |
|---|---|
| `providers.tf` | Terraform + provider version pins (azurerm, local) + remote state backend |
| `variables.tf` | Input variables, including existing-resource references |
| `main.tf` | All resources + data sources + health check |
| `outputs.tf` | Public IP / site URL / blob URL / health-check outputs |
| `IIS.ps1` | Script uploaded to blob storage and run on the VM |
| `terraform.tfvars.example` | Sample values — copy to `terraform.tfvars` and fill in your real resource names |
| `backend.hcl.example` | Sample remote-state backend config — copy to `backend.hcl` |

## Remote state

State is stored in Azure Storage (`backend "azurerm" {}` in `providers.tf`),
reusing the same existing storage account referenced in `terraform.tfvars` —
just a different container (`tfstate` by default). The backend block is left
empty on purpose; values are supplied at `terraform init` time so the same
config works both locally and in CI with different auth.

## Usage (local)

```bash
az login
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars:
#  - set existing_storage_account_name / existing_storage_account_rg
#  - set existing_vnet_name / existing_vnet_rg / existing_subnet_name
#  - set a strong admin_password
#  - restrict allowed_rdp_source (or set to "" to skip that rule)

cp backend.hcl.example backend.hcl
# edit backend.hcl to point at your existing storage account

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## Usage (CI)

`.github/workflows/infra.yml` runs `fmt` + `validate` + `plan` on every PR
touching `infra/**` (plan is posted as a PR comment and in the job summary),
then `plan` + `apply` on push to `main` — the `apply` job is gated behind the
`infra-production` GitHub Environment, so it waits for manual approval before
touching real resources. `workflow_dispatch` also supports a manual `destroy`
run. See the root [`README.md`](../README.md) for the full list of required
secrets/variables and the one-time OIDC + environment setup.

`terraform apply` will pause during the health check while it polls the
site every `health_check_interval_seconds` (default 15s) up to
`health_check_retries` times (default 20, ~5 minutes total) — long enough
for the VM to boot and the extension to install IIS. When it finishes,
check the `iis_health_check` output:

```
iis_health_check = "OK: http://20.1.2.3 responded HTTP 200 (attempt 6/20)"
```

or, if something went wrong:

```
iis_health_check = "FAILED: http://20.1.2.3 did not return HTTP 200 after 20 attempts (last status: 000)"
```

You can also just open `vm_site_url` in a browser at any time.

**Note:** the health check runs `curl` on the machine executing
`terraform apply` (Linux/macOS/WSL). If you're applying from native
Windows PowerShell without `curl`/bash available, either run this through
WSL, or tell me and I'll swap the `local-exec` block for a PowerShell
equivalent (`Invoke-WebRequest`) instead.

## Notes / things to double-check

- **Region match**: `location` (for the new RG/VM/NIC/NSG/public IP) should
  match — or at least be compatible with — the region of your existing VNet.
- **Permissions**: the identity running Terraform needs `Reader` on the
  existing VNet's resource group, and `Contributor` (plus ability to list
  storage keys) on the existing storage account's resource group.
- **Subnet NSG**: if your existing subnet already has an NSG associated at
  the subnet level, having a second NSG on the NIC is fine — Azure applies
  the union of both, so make sure the subnet-level NSG isn't blocking port 80.
- **Storage account key vs SAS/Managed Identity**: this uses the storage
  account key (fetched via the `data` source) for simplicity. For tighter
  security, swap to a short-lived SAS token or a User Assigned Managed
  Identity with `Storage Blob Data Reader` instead.
- `admin_password` is marked `sensitive` but still passed as a plain
  variable — source it from Key Vault or `TF_VAR_admin_password` rather
  than committing it to `terraform.tfvars`.
