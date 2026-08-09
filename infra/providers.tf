terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Remote state in Azure Storage. Left as a partial config on purpose —
  # values are supplied at `terraform init` time via -backend-config flags
  # (CI: .github/workflows/infra.yml, local: see backend.hcl.example).
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  # Uses the standard Azure CLI / Service Principal / Managed Identity auth chain.
  # Set ARM_SUBSCRIPTION_ID / ARM_TENANT_ID / ARM_CLIENT_ID / ARM_CLIENT_SECRET
  # as environment variables, or `az login`, before running `terraform apply`.
  # In CI, ARM_USE_OIDC=true + ARM_CLIENT_ID/ARM_TENANT_ID/ARM_SUBSCRIPTION_ID
  # authenticate via GitHub's OIDC token — no stored Azure credentials.
}
