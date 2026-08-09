# Chapter 10: Immutable Infrastructure with Packer

> Part 3: Managing Config and Infrastructure · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to bake VM images with HashiCorp Packer (using an Ansible provisioner) and then deploy them with Terraform: specifically the book's pattern of building Apache/MySQL Azure managed images and standing up a scalable LAMP stack (VM scale set behind a load balancer + a single DB VM). Also the reference for "immutable vs mutable infrastructure" trade-offs.

## Core concepts
- **Immutable infrastructure**: never modify running servers in place. To change anything, build a brand-new image with the new config and replace the running instances. Like releasing a new book edition instead of editing the old one.
- **Mutable infrastructure**: update servers in place (e.g., Ansible/Puppet/Chef/SaltStack on live VMs). Risks configuration drift, partial updates, hard rollbacks, production-direct risk.
- **Why immutable wins for scaling**: images are pre-baked and pre-tested, so new VMs start fast (no slow post-boot provisioning): ideal for cloud horizontal autoscaling and bursty traffic. Enables versioning, easy rollback, blue-green/canary/A-B.
- **Packer model**: define a template (HCL) specifying a *source* base image + where to build, and a *provisioner* (e.g., Ansible) to customize. Packer spins up a temporary build/staging VM from the base image, runs the provisioner over SSH, powers off, generalizes, snapshots to a disk image, saves it to an image repo, then tears down the temp resources. Same idea as building a container image, applied to VMs.
- **The full pipeline**: Packer (+ Ansible) bakes the image → Terraform provisions infrastructure from the image. For a config change: build a new image, then `terraform apply` to roll VMs (old down, new up). Combines IaC + config-as-code + immutable infra.
- **VM scale set**: Azure autoscaling group of VMs that scales out/in horizontally with traffic, analogous to Kubernetes scaling for containers.

## Tools and versions
- **Packer 1.9.2**: bakes immutable VM/machine images from a base image + provisioner. Plugin architecture supports VMware, VirtualBox, Amazon EC2, Azure ARM, GCP Compute, Docker, etc. Config in HCL (preferred, JSON is deprecated).
- **Packer plugins**: `github.com/hashicorp/ansible` v1.1.0 (Ansible provisioner), `github.com/hashicorp/azure` v1.4.5 (azure-arm builder).
- **Ansible**: provisioner that runs the playbooks/roles on the build VM (reuses Apache/MySQL roles from Ch.9).
- **Terraform** (azurerm provider): provisions the LAMP stack from the baked images.
- **Azure CLI (`az`)** + an **Azure service principal** (Contributor role): auth for Packer and Terraform.
- Target: Azure, region East US, base image Canonical UbuntuServer 18.04-LTS.

## Workflows (how-to)

### 1. Install Packer (Ubuntu via apt)
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo \
  gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y packer
packer --version   # -> 1.9.2
```
(Other platforms: https://developer.hashicorp.com/packer/downloads)

### 2. Project layout (ch10)
```
├── ansible
│   ├── dbserver-playbook.yaml
│   ├── roles/{apache,common,mysql}
│   └── webserver-playbook.yaml
├── packer
│   ├── dbserver.pkr.hcl
│   ├── plugins.pkr.hcl
│   ├── variables.pkr.hcl
│   ├── variables.pkrvars.hcl
│   └── webserver.pkr.hcl
└── terraform
    ├── main.tf
    ├── outputs.tf
    ├── terraform.tfvars
    └── vars.tf
```
Repo: github.com/PacktPublishing/Modern-DevOps-Practices-2e (clone, then `cd modern-devops/ch10`).

### 3. Write Ansible playbooks for Packer
Both playbooks set `hosts: default` because Packer generates the inventory dynamically against the build VM: do NOT define an inventory.
```yaml
# webserver-playbook.yaml
---
- hosts: default
  become: true
  roles:
    - common
    - apache
```
```yaml
# dbserver-playbook.yaml
---
- hosts: default
  become: true
  roles:
    - common
    - mysql
```
Note: Packer ignores any `remote_user` in tasks and uses the user from the Ansible provisioner config. Required playbook change for Packer = set `hosts` to `default`.

### 4. Azure prerequisites (service principal + resource group)
```bash
az login
export SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
az account set --subscription="${SUBSCRIPTION_ID}"
# Create SP with Contributor access -> returns appId, password, tenant
az ad sp create-for-rbac --role="Contributor" \
  --scopes="/subscriptions/${SUBSCRIPTION_ID}"
# Resource group to store the built images
az group create -n packer-rg -l eastus
```
Put the SP values into `packer/variables.pkrvars.hcl` (never commit secrets):
```hcl
client_id       = "<VALUE_OF_APP_ID>"
client_secret   = "<VALUE_OF_PASSWORD>"
tenant_id       = "<VALUE_OF_TENANT>"
subscription_id = "<SUBSCRIPTION_ID>"
```

### 5. Define Packer config (HCL)
See Reference snippets for `variables.pkr.hcl`, `plugins.pkr.hcl`, `webserver.pkr.hcl`, `dbserver.pkr.hcl`.

### 6. Build images (Packer workflow = init then build)
```bash
cd ~/modern-devops/ch10/packer
packer init .                                    # installs ansible + azure plugins
packer build -var-file="variables.pkrvars.hcl" . # builds webserver + dbserver in parallel
```
What `build` does per source: creates a temp resource group + staging VM from the base image → deploys template, gets VM IP → SSH in → runs Ansible (`ansible-playbook -e packer_build_name=... -e packer_builder_type=azure-arm ...`) → powers off → generalizes → captures image into `packer-rg` (`apache-webserver`, `mysql-dbserver`) → deletes the temp deployment + resource group. Final artifacts are Azure managed VM images.

### 7. Provision the LAMP stack with Terraform
```bash
cd ~/modern-devops/ch10/terraform
# fill terraform.tfvars first
terraform init
terraform apply
# -> Apply complete! Resources: 13 added...
# Outputs: web_ip_addr = "40.115.61.69"
```
Browse to `web_ip_addr`. Success shows "Database Connected successfully". Resources created: `lamp-rg`, vnet `lampvnet` (10.0.0.0/16), subnet `lampsub` (10.0.2.0/24), LB `web-lb` + static public IP, backend pool, HTTP probe on port 80, LB rule 80→80, VM scale set `webscaleset` (capacity 2, from `apache-webserver` image), DB VM `db` (from `mysql-dbserver` image) with NIC `db-nic` and NSG `db-nsg` (allow 22, 3306).

## Reference snippets

### variables.pkr.hcl
```hcl
variable "client_id"       { type = string }
variable "client_secret"   { type = string }
variable "subscription_id" { type = string }
variable "tenant_id"       { type = string }
```

### plugins.pkr.hcl
```hcl
packer {
  required_plugins {
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "=1.1.0"
    }
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "=1.4.5"
    }
  }
}
```

### webserver.pkr.hcl
```hcl
source "azure-arm" "webserver" {
  client_id                         = var.client_id
  client_secret                     = var.client_secret
  image_offer                       = "UbuntuServer"
  image_publisher                   = "Canonical"
  image_sku                         = "18.04-LTS"
  location                          = "East US"
  managed_image_name                = "apache-webserver"
  managed_image_resource_group_name = "packer-rg"
  os_type                           = "Linux"
  subscription_id                   = var.subscription_id
  tenant_id                         = var.tenant_id
  vm_size                           = "Standard_DS2_v2"
}

build {
  sources = ["source.azure-arm.webserver"]
  provisioner "ansible" {
    playbook_file = "../ansible/webserver-playbook.yaml"
  }
}
```

### dbserver.pkr.hcl
Identical to webserver except the image name and playbook:
```hcl
source "azure-arm" "dbserver" {
  # ...same auth/base-image attributes...
  managed_image_name = "mysql-dbserver"
  # ...
}
build {
  sources = ["source.azure-arm.dbserver"]
  provisioner "ansible" {
    playbook_file = "../ansible/dbserver-playbook.yaml"
  }
}
```

### Terraform main.tf (key blocks)
```hcl
terraform {
  required_providers {
    azurerm = { source = "azurerm" }
  }
}
provider "azurerm" {
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

# Reference the Packer-baked images
data "azurerm_image" "websig" {
  name                = "apache-webserver"
  resource_group_name = "packer-rg"
}
data "azurerm_image" "dbsig" {
  name                = "mysql-dbserver"
  resource_group_name = "packer-rg"
}

resource "azurerm_resource_group" "main" {
  name     = var.rg_name
  location = var.location
}
resource "azurerm_virtual_network" "main" {
  name                = "lampvnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
}
resource "azurerm_subnet" "main" {
  name                 = "lampsub"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "main" {
  name                = "webip"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  domain_name_label   = azurerm_resource_group.main.name
}
resource "azurerm_lb" "main" {
  name                = "web-lb"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.main.id
  }
}
resource "azurerm_lb_backend_address_pool" "bpepool" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "BackEndAddressPool"
}
resource "azurerm_lb_probe" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "http-running-probe"
  port            = 80
}
resource "azurerm_lb_rule" "lbnatrule" {
  resource_group_name            = azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bpepool.id]
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.main.id
}

resource "azurerm_virtual_machine_scale_set" "main" {
  name                = "webscaleset"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  upgrade_policy_mode = "Manual"
  sku { name = "Standard_DS1_v2"  tier = "Standard"  capacity = 2 }
  storage_profile_image_reference { id = data.azurerm_image.websig.id }
  storage_profile_os_disk {
    name = ""  caching = "ReadWrite"  create_option = "FromImage"  managed_disk_type = "Standard_LRS"
  }
  storage_profile_data_disk { lun = 0  caching = "ReadWrite"  create_option = "Empty"  disk_size_gb = 10 }
  os_profile {
    computer_name_prefix = "web"
    admin_username       = var.admin_username
    admin_password       = var.admin_password
  }
  os_profile_linux_config { disable_password_authentication = false }
  network_profile {
    name = "webnp"  primary = true
    ip_configuration {
      name      = "IPConfiguration"
      subnet_id = azurerm_subnet.main.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
      primary   = true
    }
  }
}
```
DB side (NSG opens 22 + 3306, NIC + association, VM from `dbsig` image):
```hcl
resource "azurerm_network_security_group" "db_nsg" {
  name                = "db-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  security_rule {
    name = "SSH"  priority = 1001  direction = "Inbound"  access = "Allow"
    protocol = "Tcp"  source_port_range = "*"  destination_port_range = "22"
    source_address_prefix = "*"  destination_address_prefix = "*"
  }
  security_rule {
    name = "SQL"  priority = 1002  direction = "Inbound"  access = "Allow"
    protocol = "Tcp"  source_port_range = "*"  destination_port_range = "3306"
    source_address_prefix = "*"  destination_address_prefix = "*"
  }
}
resource "azurerm_network_interface" "db" {
  name                = "db-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  ip_configuration {
    name                          = "db-ipconfiguration"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "azurerm_network_interface_security_group_association" "db" {
  network_interface_id      = azurerm_network_interface.db.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}
resource "azurerm_virtual_machine" "db" {
  name                          = "db"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.main.name
  network_interface_ids         = [azurerm_network_interface.db.id]
  vm_size                       = var.vm_size
  delete_os_disk_on_termination = true
  storage_image_reference { id = data.azurerm_image.dbsig.id }
  storage_os_disk {
    name = "db-osdisk"  caching = "ReadWrite"  create_option = "FromImage"  managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "db"
    admin_username = var.admin_username
    admin_password = var.admin_password
  }
  os_profile_linux_config { disable_password_authentication = false }
}
```

## Decision guidance and best practices
- **Use immutable infra when** you need reproducible, reliable deployments, want to eliminate config drift, and benefit from fast horizontal scaling, easy rollback, and versioned releases: strong fit for microservices, container orchestration, and rapid-scaling/rollback scenarios.
- **Stick with mutable infra (Ansible on live servers) when** you need fast in-place upgrades/security patches, simpler management, or process/red-tape constraints block image rebuilds. It's a valid fallback. DevOps is culture, not just tooling.
- **Version your managed image names** (e.g., `apache-webserver-0.0.1`, not `apache-webserver`) so multiple versions coexist and you can roll out/roll back. Build a new image per new version.
- **Source secrets externally**: var files, env vars, or HashiCorp Vault. Never commit `client_secret` etc. with code. (`variables.pkrvars.hcl` holds them, not the tracked HCL.)
- **Multi-cloud**: one set of Packer files can build the same config across clouds. Add multiple `sources` to the `build` block (same or different types).
- **Multiple provisioners** in a `build` block execute in order of occurrence in the HCL file (sequentially), not in parallel. (Separate *builds/sources* run in parallel.)
- VM scale sets give you horizontal autoscaling with traffic AND auto-heal of faulty VMs.

## Pitfalls and gotchas
- **Cannot rebuild over an existing managed image** with the same name: Packer refuses to avoid accidental overwrite. Either version the image name (preferred) or use `packer build -force`.
- Forgetting to set playbook `hosts: default` breaks Packer's dynamic inventory.
- Ansible provisioner limitations under Packer: you cannot pass Jinja2 macros as-is to playbooks, and you cannot define `remote_user` in playbooks (Packer overrides it with the provisioner's user). Roles, variables, and Jinja2 *templates* still work.
- JSON Packer templates are deprecated: use HCL.
- Don't define an Ansible inventory/host file or a stray `ansible.cfg` when handing playbooks to Packer. Packer manages SSH key + inventory itself (`-i /tmp/packer-provisioner-ansible...`).
- Building/storing images adds storage + network overhead, and hotfixes/urgent updates are slower than mutable in-place changes.

## Command / API cheat-sheet
- `packer --version`: check Packer version.
- `packer init .`: download/install required plugins (ansible, azure).
- `packer build -var-file="variables.pkrvars.hcl" .`: build all images in the dir.
- `packer build -force ...`: overwrite an existing managed image.
- `az login` / `az account set --subscription=...`: Azure auth + select subscription.
- `az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/$ID"`: create service principal.
- `az group create -n packer-rg -l eastus`: create image resource group.
- `terraform init` / `terraform apply`: provision the LAMP stack.
- HCL blocks: `packer{ required_plugins }`, `variable`, `source "azure-arm" "<name>"`, `build { sources, provisioner "ansible" }`.
- Terraform objects: `azurerm_image` (data), `azurerm_virtual_machine_scale_set`, `azurerm_lb` / `azurerm_lb_backend_address_pool` / `azurerm_lb_probe` / `azurerm_lb_rule`, `azurerm_network_security_group`, `azurerm_virtual_machine`.

## Where this is covered (topic index)
- Immutable vs mutable infrastructure, config drift, pros/cons → Core concepts, Decision guidance.
- What Packer is / build process / multi-platform plugins → Core concepts, Tools and versions.
- Installing Packer (apt) → Workflow 1.
- Packer + Ansible playbook requirements (`hosts: default`, dynamic inventory) → Workflow 3, Pitfalls.
- Azure service principal / `az ad sp create-for-rbac` / packer-rg → Workflow 4.
- Packer HCL config (variables, plugins, source, build, azure-arm) → Workflows 5, Reference snippets.
- `packer init` / `packer build` / `-var-file` / `-force` / image versioning → Workflow 6, Cheat-sheet, Pitfalls.
- LAMP stack on Azure (VM scale set, load balancer, probe, NSG, DB VM) → Workflow 7, Reference Terraform snippets.
- Using baked images in Terraform (`azurerm_image` data source) → Reference main.tf.
- VM scale set autoscaling / auto-heal → Core concepts, Decision guidance.
- Ansible provisioner limitations (Jinja2 macros, remote_user) → Pitfalls.
- Multi-cloud / multiple sources & provisioners → Decision guidance.
- Secrets handling (Vault, var files) → Decision guidance, Workflow 4.
