# Chapter 08: Infrastructure as Code (IaC) with Terraform

> Part 3: Managing Config and Infrastructure · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to provision/manage cloud infrastructure declaratively with Terraform (the book targets Azure via the `azurerm` provider): writing HCL, the init/plan/apply/destroy workflow, modules, remote state backends, workspaces for multi-env, outputs, state surgery (rm/import), console, and dependency graphs.

## Core concepts
- **IaC**: define infrastructure as code. Terraform is *declarative*: you describe the desired end state, not the steps. This is idempotent, unlike imperative scripts which can't reliably manage change, detect drift, or span multiple clouds cleanly.
- **Why declarative wins**: tracks state, detects drift (manual changes show as a delta on next run), enables GitOps (infra config lives beside app code, versioned, PR-reviewed/gated before applying to higher envs).
- **Terraform editions**: open source (CLI only, this chapter), Cloud, and Enterprise (web GUI plus policy-as-code via Sentinel, cost analysis, private modules, GitOps, CI/CD, the `remote` backend).
- **Architecture (two parts)**: **Terraform Core** = the CLI, takes config files + existing state, computes the diff, applies it. **Terraform providers** = plugins that translate HCL into a cloud's REST API calls (e.g., the Azure `azurerm` provider). Decentralized: each cloud ships its own provider.
- **Root module**: the working directory containing `.tf` files, where you run commands. Terraform merges all `.tf` files in the dir as one. Convention: `main.tf` (resources), `vars.tf` (variables), `outputs.tf` (outputs).
- **State file**: tracks what Terraform deployed/manages. Lose it and Terraform forgets and recreates everything. Stored in a **backend** (local by default, remote recommended).
- **Module**: reusable, repeatable, versionable template. Experts author them to enforce enterprise standards. Developers consume them.
- **Workspace**: independent state file under one config, used to run the same config across multiple environments (dev/test/prod) with separate state.
- **Dependencies**: implicit (one resource's output is another's input, preferred, enables parallelism) vs explicit (`depends_on`, avoid unless required, it serializes runs).

## Tools and versions
- **Terraform** v1.5.2 (open source CLI): IaC engine.
- **Azure provider** `azurerm`: book pins `=3.55.0` in config. Init downloads v3.63.0 in one example. Always constrain the version.
- **Azure CLI (`az`)** 2.49.0: authenticate, create the state-storage account, and verify resources.
- **Graphviz** (`dot`): render the Terraform dependency graph to PNG.
- **Backends available** (at time of writing): Azure RM, Consul, cos, gcs, http, Kubernetes, oss, pg, S3, Remote. `Remote` runs plan/apply in the backend and is Cloud/Enterprise-only.
- Clone the exercises: `git clone https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git modern-devops` then `cd modern-devops/ch8`.

## Workflows (how-to)

### Install Terraform (Ubuntu, apt)
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
terraform version   # -> Terraform v1.5.2
```

### Authenticate to Azure with a service principal (preferred over named user)
A service principal lets Terraform act without a named admin account and lets you apply least privilege, ideal for CI/CD.
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash   # install az CLI
az --version                                             # -> azure-cli 2.49.0
az login                                                 # browse to URL, enter code
# note the "id" from the response = subscription ID
export SUBSCRIPTION_ID="<SUBSCRIPTION_ID>"
az account set --subscription="$SUBSCRIPTION_ID"
# create SP with Contributor on the subscription (use finer-grained scope in prod)
az ad sp create-for-rbac --role="Contributor" \
  --scopes="/subscriptions/$SUBSCRIPTION_ID"
# capture appId, password, tenant from the JSON — DO NOT commit these
```

### Define the Azure provider (`main.tf`)
```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "azurerm"
      version = "=3.55.0"
    }
  }
}
provider "azurerm" {
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  features {}
}
```
Source values from variables (reuse + keep secrets out of source control).

### Declare variables (`vars.tf`)
```hcl
variable "subscription_id" {
  type        = string
  description = "The azure subscription id"
}
variable "app_id" {
  type        = string
  description = "The azure service principal appId"
}
variable "password" {
  type        = string
  description = "The azure service principal password"
  sensitive   = true
}
variable "tenant" {
  type        = string
  description = "The azure tenant id"
}
```
- `type`: `string` (default), `number`, `bool`, or complex `list`/`set`/`map`/`object`/`tuple`.
- `sensitive = true` hides the value in CLI output (use for passwords/secrets).
- `default = ...` provides an overridable default (soft guidance, saves users time).

### Supply variable values (precedence high→low)
1. CLI `-var "name=value"` flags (highest precedence)
2. `-var-file` pointing at a `.tfvars` (HCL) or `.tfvars.json` file
3. Auto-loaded files: `terraform.tfvars` or any `*.auto.tfvars` in the workspace
4. Environment variables `TF_VAR_<var-name>`
5. Interactive prompt (if none of the above provide a value)

`terraform.tfvars`:
```hcl
subscription_id = "<SUBSCRIPTION_ID>"
app_id          = "<SERVICE_PRINCIPAL_APP_ID>"
password        = "<SERVICE_PRINCIPAL_PASSWORD>"
tenant          = "<TENANT_ID>"
rg_name         = "terraform-exercise"
rg_location     = "West Europe"
```
`.gitignore`:
```
*.tfvars
.terraform*
```

### Core workflow: init → fmt → validate → plan → apply → destroy
```bash
terraform init        # init backend + workspace, download providers, write .terraform.lock.hcl
terraform fmt         # format .tf files to canonical style; lists changed files
terraform validate    # syntax/config check -> "Success! The configuration is valid."
terraform plan        # speculative diff; no changes made
terraform plan -out rg.tfplan      # SAVE the plan to a file (recommended)
terraform apply "rg.tfplan"        # apply a saved plan (no re-plan, no prompt)
terraform apply                    # plan + prompt for "yes"
terraform apply -auto-approve      # apply without prompt
terraform plan -destroy            # speculative destroy plan (review before destroying)
terraform destroy                  # prompts "yes"; destroys ALL managed infra
terraform destroy --auto-approve   # destroy without prompt
```
- Commit `.terraform.lock.hcl` to version control so the same provider versions are selected.
- Partial apply auto-taints failed resources (recreated next run). Manually mark for recreation: `terraform taint <resource>`.

### Create a resource (Azure resource group)
`main.tf`:
```hcl
resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.rg_location
}
```
Verify with `az group list`.

### Modularize a resource
Directory layout:
```
.
├── main.tf
├── modules
│   └── resource_group
│       ├── main.tf
│       └── vars.tf
├── terraform.tfvars
└── vars.tf
```
`modules/resource_group/main.tf`:
```hcl
resource "azurerm_resource_group" "rg" {
  name     = var.name
  location = var.location
}
```
Root `main.tf` calls the module (after `terraform`/`provider` blocks):
```hcl
module "rg" {
  source   = "./modules/resource_group"
  name     = var.rg_name
  location = var.rg_location
}
```
Re-run `terraform init` whenever you add a module. The resource is now addressed `module.rg.azurerm_resource_group.rg`.

### Set up a remote state backend (Azure Storage)
You can't use Terraform to build its own backend (chicken-and-egg), so create the storage with `az` in a separate, Terraform-unmanaged resource group:
```bash
RESOURCE_GROUP=tfstate
STORAGE_ACCOUNT_NAME=tfstate$RANDOM
CONTAINER_NAME=tfstate
az group create --name $RESOURCE_GROUP --location westeurope
az storage account create --resource-group $RESOURCE_GROUP \
  --name $STORAGE_ACCOUNT_NAME --sku Standard_LRS --encryption-services BLOB
ACCOUNT_KEY=$(az storage account keys list \
  --resource-group tfstate --account-name $STORAGE_ACCOUNT_NAME \
  --query '[0].value' -o tsv)
az storage container create --name $CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT_NAME --account-key $ACCOUNT_KEY
echo $STORAGE_ACCOUNT_NAME   # e.g. tfstate28099
```
`backend.tf`:
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate"
    storage_account_name = "tfstate28099"
    container_name       = "tfstate"
    key                  = "example.tfstate"   # name = project name, e.g. foo.tfstate
  }
}
```
`terraform init` detects the backend change and offers to migrate existing state. plan/apply now show `Acquiring state lock...` / `Releasing state lock...` (state locking via the remote backend).

### Workspaces (multi-environment with one config)
Use `terraform.workspace` to differentiate resource names per env. Single config, separate state per workspace.
```hcl
resource "azurerm_resource_group" "main" {
  name     = "${var.rg_prefix}-${terraform.workspace}"
  location = var.rg_location
}
# + azurerm_virtual_network, azurerm_subnet, azurerm_network_interface, azurerm_virtual_machine
```
```bash
terraform init
terraform workspace new dev          # create + switch
terraform plan -out dev.tfplan       # empty state -> creates terraform-ws-dev
terraform apply "dev.tfplan"
terraform workspace new test
terraform plan -out test.tfplan
terraform apply test.tfplan
terraform workspace select dev       # switch back
terraform destroy --auto-approve     # destroys current workspace's resources
```
- Local backend state layout: `terraform.tfstate.d/<workspace>/terraform.tfstate`.
- Azure Blob backend: state files suffixed `env:dev` / `env:test`.

### Outputs (`outputs.tf`)
```hcl
output "vm_ip_addr" {
  value = azurerm_network_interface.main.private_ip_address
}
```
```bash
terraform apply --auto-approve   # prints Outputs: vm_ip_addr = "10.0.2.4"
terraform output                 # re-print outputs from state anytime
```
Outputs are stored in state and exported to consuming modules.

### State management (surgery)
```bash
terraform show                                  # full current state incl. outputs
terraform state list                            # list managed resources
terraform state rm azurerm_virtual_machine.main # remove from state ONLY (cloud resource untouched)
terraform import <resource> <resource_id>       # adopt an existing cloud resource (brownfield)
```
Import example (adopt a manually-created VM):
```bash
terraform import azurerm_virtual_machine.main \
"/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/terraform-ws-dev/providers/Microsoft.Compute/virtualMachines/httpd"
terraform state list | grep azurerm_virtual_machine
```

### Console (interactive inspection / expression eval)
```bash
terraform console
> azurerm_virtual_machine.main.resource_group_name
"terraform-ws-dev"
> azurerm_virtual_machine.main.id
> exit
```

### Dependency graph
```bash
terraform graph > vm.dot
sudo apt install graphviz -y
cat vm.dot | dot -T png -o vm.png
```

## Decision guidance and best practices
- **Constrain provider versions**: providers release independently of the CLI. An unpinned version that works locally may break elsewhere or in CI/CD.
- **Never store secrets in source control**: use a `tfvars` file kept in a secret manager (e.g., HashiCorp Vault). Mark sensitive variables `sensitive = true`.
- **Always set `description`** on variables and **use `default`s** where sensible, both promote reuse and give users guidance.
- **Run `fmt` and `validate` before every plan**: catches issues early.
- **Save plans with `-out`** and apply the saved file: avoids surprises from background drift between plan and apply, essential when the plan is PR-reviewed.
- **Never store state in source control**: it's plaintext (leaks secrets) and gives no locking (causes conflicts). Add `terraform.tfstate` to `.gitignore`.
- **Prefer remote backends with state locking**: enables team collaboration, encryption at rest, backup/redundancy. Azure Storage gives all three.
- **Name the state `key` after the project** (`foo.tfstate`) so multiple projects share one storage account without conflict.
- **Use modules** to encapsulate and standardize infra across the org.
- **Use workspaces** for dev/staging/prod from one config: prevents accidental config drift between envs.
- **Least privilege** for service principals: grant only what's needed. Add more later if required.
- **Avoid explicit `depends_on`** unless necessary: it disables parallelism and slows runs.
- **`terraform destroy`**: fine for dev/temporary infra. Never use in production, instead remove resources from config and `terraform apply`.

## Pitfalls and gotchas
- Imperative scripts aren't idempotent: editing mid-script and rerunning can wreck infrastructure. They also can't detect manual drift.
- Losing the state file makes Terraform treat all managed resources as new (duplicate creation).
- `terraform state rm` only forgets the resource, it does NOT delete the real cloud resource. Conversely the real resource is now unmanaged/orphaned.
- Forgetting to re-run `terraform init` after adding a module → the module won't be initialized.
- Not saving the plan means `apply` re-plans and re-prompts. Background changes may make `apply` do something unexpected.
- `terraform destroy` has no undo and destroys ALL managed infra: run `terraform plan -destroy` first.
- Don't commit `*.tfvars` or `.terraform*`. Do commit `.terraform.lock.hcl`.

## Command / API cheat-sheet
- `terraform version`: show installed version.
- `terraform init`: init backend/workspace, download providers, write lock file.
- `terraform fmt`: canonical formatting of `.tf` files.
- `terraform validate`: syntax/config validation.
- `terraform plan`: speculative diff, `-out <file>` to save, `-destroy` for a destroy plan.
- `terraform apply [plan]`: apply, `-auto-approve` skips prompt.
- `terraform destroy`: destroy all managed infra, `--auto-approve` skips prompt.
- `terraform taint <resource>`: mark resource for recreation next apply.
- `terraform output [name]`: print output values from state.
- `terraform show`: dump full current state.
- `terraform state list`: list managed resources.
- `terraform state rm <resource>`: remove resource from state (not from cloud).
- `terraform import <resource> <id>`: adopt existing cloud resource into state.
- `terraform console`: interactive expression/state evaluation.
- `terraform graph`: emit DOT dependency graph.
- `terraform workspace new|select <name>`: create/switch workspaces.
- HCL blocks: `terraform {}`, `provider {}`, `resource {}`, `module {}`, `variable {}`, `output {}`, `backend {}`.

## Where this is covered (topic index)
- IaC concept / declarative vs imperative → Core concepts, Introduction.
- Install Terraform (Ubuntu/apt) → Install Terraform workflow.
- Azure auth, `az login`, service principal, `az ad sp create-for-rbac`, least privilege → Authenticate to Azure.
- Provider config, `required_providers`, version pin → Define the Azure provider.
- Variables, `sensitive`, `type`, `default`, `description` → Declare variables.
- `.tfvars` / `TF_VAR_` / `-var` / precedence → Supply variable values.
- init/plan/apply/destroy, `fmt`, `validate`, `-out`, `-auto-approve`, taint → Core workflow.
- Resource group / `azurerm_resource_group` → Create a resource.
- Modules, `module {}`, `source`, reuse → Modularize a resource.
- State, backends, remote state, Azure Storage, state locking, `.gitignore` → Set up a remote state backend, Managing state (Core concepts).
- Workspaces, multi-env, `terraform.workspace`, env:dev/env:test → Workspaces.
- Outputs / return values → Outputs.
- `terraform show` / `state list` / `state rm` / `import` (brownfield) → State management.
- `terraform console` → Console.
- `depends_on`, implicit vs explicit dependencies, `terraform graph`, Graphviz → Dependency graph, Core concepts.
- Cleanup / cost avoidance → destroy commands in Core workflow + best practices.
