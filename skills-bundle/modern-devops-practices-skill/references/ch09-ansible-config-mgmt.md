# Chapter 09: Configuration Management with Ansible

> Part 3: Managing Config and Infrastructure · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to configure existing servers idempotently with Ansible: writing inventories, playbooks, tasks/modules, handlers, variables, Jinja2 templates, or refactoring playbooks into reusable roles. This is the book's hands-on LAMP-stack (Apache + MySQL on Azure VMs) walkthrough.

## Core concepts
- **Configuration Management (CM) / Configuration as Code (CaC)**: declaratively define a server's desired state as code in version control instead of running manual/imperative setup scripts. Solves: not repeatable, not idempotent, manual toil, imperative-only scripts.
- **Idempotency**: re-applying config only changes the delta. A step already matching desired state is reported `ok`/`SUCCESS` (no change). A step that altered state is `CHANGED`.
- **Agentless**: Ansible needs no agent on managed nodes. It connects over **SSH** (or WinRM for Windows) and runs commands sequentially per node, in parallel across nodes.
- **Control node vs managed nodes**: one control node has Ansible installed. It manages N managed (inventory) nodes that accept SSH from the control node. Requires passwordless SSH.
- **Inventory**: file grouping managed nodes by **role/function** (e.g. `webservers`, `dbservers`). Default location `/etc/ansible/hosts`.
- **Tasks**: the basic unit, one module invocation. Statuses: `SUCCESS` (ok, no action), `CHANGED` (config altered), `FAILURE` (error).
- **Modules**: reusable units of work (`apt`, `service`, `copy`, `file`, `mysql_user`, `lineinfile`, etc.). Full list: docs.ansible.com/ansible/latest/collections/index_module.html
- **Playbook**: ordered, declarative YAML list of **plays**, each play maps a group of **hosts** (by role) to a list of **tasks** (+ optional handlers, vars). Provides GitOps/CaC.
- **Handlers**: tasks triggered via `notify` only when the notifying task is `CHANGED` (e.g. restart a service after its config file changes).
- **Roles**: standardized directory layout (`tasks/`, `handlers/`, `templates/`, `vars/`, `defaults/`, `files/`, `library/`, `meta/`) for reusable, shareable config. Loaded automatically by convention.
- **Jinja2 templating**: `{{ var }}` substitution inside playbooks and `.j2` template files for runtime/per-environment values.
- **Book repo**: github.com/PacktPublishing/Modern-DevOps-Practices-2e, chapter dir `ch9/`.

## Tools and versions
- **Ansible 2.9.27**: installed on the control node from the official PPA (`ppa:ansible/ansible`). Open source, Python-based, owned by Red Hat.
- **Python 3.x**: required on nodes, the book forces `python3` via inventory var (python2 deprecated on Ubuntu).
- **Terraform**: used to provision the 3 Azure VMs (control node, web, db) and bootstrap passwordless SSH via `custom_data` init scripts. See Ch.8.
- **Azure**: VMs in an `ansible-exercise` resource group, needs an Azure subscription.
- Supporting utilities: `sshpass`, `ssh-keygen`, `ssh-keyscan`, `ssh-copy-id` for SSH bootstrap.
- Alternatives mentioned (not used): Puppet, Chef, SaltStack. Ansible chosen for simplicity.

## Workflows (how-to)

### 1. Provision the lab infra (Terraform → 3 Azure VMs)
```bash
cd ~/modern-devops/ch9/setup-ansible-terraform
vim terraform.tfvars            # fill in Azure attributes + admin_password
terraform init
terraform plan -out ansible.tfplan
terraform apply ansible.tfplan
terraform output                # re-fetch public IPs of control node + web if missed
```
Creates `ansible-control-node`, `web`, `db` VMs. The VMs' `custom_data` runs init shell scripts that set up passwordless SSH (see Reference snippets) automatically at boot.

### 2. Verify passwordless SSH, then install Ansible on the control node
```bash
ssh ssh_admin@<control-node-public-ip>   # log in with terraform.tfvars creds
sudo su - ansible                        # switch to the ansible user
ssh web                                  # should land on web with no password
ssh db                                   # same for db; exit back to control node
```
Install Ansible from the PPA:
```bash
sudo apt update
sudo apt install software-properties-common -y
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
ansible --version          # ansible 2.9.27
```

### 3. Set up inventory + config in the repo (decentralized / GitOps)
```bash
sudo chown -R ansible:ansible /etc/ansible   # let the ansible user own default dir
sudo su - ansible
git clone https://github.com/PacktPublishing/Modern-DevOps-Practices-2e.git modern-devops
cd ~/modern-devops/ch9/ansible-exercise
```
Keep `hosts` and `ansible.cfg` in the repo so Git is the single source of truth.

### 4. Validate inventory + connectivity
```bash
ansible-inventory --list -y        # show parsed groups/hosts
ansible --list-hosts all           # all hosts
ansible --list-hosts webservers    # hosts in one group
ansible all -m ping                # connectivity check -> "ping": "pong"
```

### 5. Run ad-hoc tasks (module + args against an inventory target)
```bash
ansible -m shell -a "uname" all    # run a module (-m) with args (-a) on a target
ansible -m setup webservers        # gather Ansible facts (metadata) for a group
```
Format: `ansible <options> <inventory>`. `-m` = module, `-a` = module args, trailing arg = target (host/group/`all`/wildcard).
Best practice: prefer purpose-built modules (e.g. `apt`) over `command`/`shell`.

### 6. Write, syntax-check, and run a playbook
```bash
ansible-playbook ping.yaml --syntax-check   # validate before applying
ansible-playbook ping.yaml                  # apply
```
Execution phases per play: **Gathering Facts** → **Run tasks** → **Play recap** (`ok`/`changed`/`unreachable`/`failed`/`skipped`/`rescued`/`ignored` counts).

### 7. Build the LAMP stack (ch9/lamp-stack): playbook-of-playbooks
Logical order matters: update → install → configure. Combine with `import_playbook`:
```yaml
# playbook.yaml
---
- import_playbook: apt-update.yaml
- import_playbook: install-webserver.yaml
- import_playbook: install-dbserver.yaml
- import_playbook: setup-webservers.yaml
- import_playbook: setup-dbservers.yaml
```
```bash
ansible-playbook playbook.yaml
curl web      # -> "Database Connected successfully"
```

### 8. Source dynamic values
- **Facts** (gathered metadata): use `ansible_hostname`, `ansible_all_ipv4_addresses`, etc., directly in playbooks. Inspect with `ansible -m setup <group>`.
- **register**: capture a task's result into a variable for later tasks.
```yaml
- hosts: webservers
  tasks:
    - name: Get free space
      command: free -m
      register: free_space
      ignore_errors: true
    - name: Print the free space from the previous task
      debug:
        msg: "{{ free_space }}"
```

### 9. Refactor into roles (ch9/lamp-stack-roles)
Create three loosely-coupled roles: `common`, `apache`, `mysql`. Convert `index.php`→`index.php.j2` and `client.my.cnf`→`client.my.cnf.j2`. Each role's `tasks/main.yaml` includes its sub-task files:
```yaml
# roles/apache/tasks/main.yaml
---
- include: install-apache.yaml
- include: setup-apache.yaml
```
Run, and override role vars at the CLI with `--extra-vars`:
```bash
ansible-playbook playbook.yaml
ansible-playbook playbook.yaml --extra-vars "mysql_user=foo mysql_password=bar@123"
```

## Reference snippets

### Inventory file (`hosts`)
```ini
[webservers]
web ansible_host=web
[dbservers]
db ansible_host=db
[all:vars]
ansible_python_interpreter=/usr/bin/python3
```
Use **aliases** (`web ansible_host=...`) not raw IPs. Group by function. For non-standard SSH ports, set them here.

### `ansible.cfg` (local, in repo dir)
```ini
[defaults]
inventory = ./hosts
host_key_checking = False
```
Config resolution order (first wins, NOT merged): `ANSIBLE_CONFIG` env var → `./ansible.cfg` → `~/ansible.cfg` → `/etc/ansible/ansible.cfg`.

### Managed-node SSH bootstrap (`managed-nodes-user-data.sh`)
```sh
#!/bin/sh
sudo useradd -m ansible
echo 'ansible ALL=(ALL) NOPASSWD:ALL' | sudo tee -a /etc/sudoers
sudo su - ansible << EOF
ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
printf "${admin_password}\n${admin_password}" | sudo passwd ansible
EOF
```

### Control-node SSH bootstrap (`control-node-user-data.sh`)
```sh
#!/bin/sh
sudo useradd -m ansible
echo 'ansible ALL=(ALL) NOPASSWD:ALL' | sudo tee -a /etc/sudoers
sudo su - ansible << EOF
ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
sleep 120
ssh-keyscan -H web >> ~/.ssh/known_hosts
ssh-keyscan -H db >> ~/.ssh/known_hosts
sudo apt update -y && sudo apt install -y sshpass
echo "${admin_password}" | sshpass ssh-copy-id ansible@web
echo "${admin_password}" | sshpass ssh-copy-id ansible@db
EOF
```

### Minimal ping playbook
```yaml
---
  - hosts: all
    tasks:
      - name: Ping all servers
        action: ping
```

### apt update (run as root on multiple groups)
```yaml
---
- hosts: webservers:dbservers
  become: true
  tasks:
    - name: Update apt packages
      apt: update_cache=yes cache_valid_time=3600
```

### Install Apache + start/enable service
```yaml
---
- hosts: webservers
  become: true
  tasks:
    - name: Install packages
      apt:
        name:
        - apache2
        - php
        - libapache2-mod-php
        - php-mysql
        update_cache: yes
        cache_valid_time: 3600
        state: present
    - name: Start and Enable Apache service
      service: name=apache2 state=started enabled=yes
```

### Install MySQL
```yaml
---
- hosts: dbservers
  become: true
  tasks:
  - name: Install packages
    apt:
      name:
      - python-pymysql
      - mysql-server
      update_cache: yes
      cache_valid_time: 3600
      state: present
  - name: Start and enable MySQL service
    service:
      name: mysql
      state: started
      enabled: true
```

### Configure Apache (file delete, copy, handler-on-change)
```yaml
---
- hosts: webservers
  become: true
  tasks:
  - name: Delete index.html file
    file:
      path: /var/www/html/index.html
      state: absent
  - name: Upload application file
    copy:
      src: index.php
      dest: /var/www/html
      mode: 0755
    notify:
      - Restart Apache
  handlers:
  - name: Restart Apache
    service: name=apache2 state=restarted
```

### Configure MySQL (root creds, user, hardening, bind address)
```yaml
---
- hosts: dbservers
  become: true
  vars:
    mysql_root_password: "Password@1"
  tasks:
  - name: Set the root password
    copy:
      src: client.my.cnf
      dest: "/root/.my.cnf"
      mode: 0600
    notify:
      - Restart MySQL
  - name: Create a test user
    mysql_user:
      name: testuser
      password: "Password@1"
      login_user: root
      login_password: "{{ mysql_root_password }}"
      state: present
      priv: '*.*:ALL,GRANT'
      host: '%'
  - name: Remove all anonymous user accounts
    mysql_user:
      name: ''
      host_all: yes
      state: absent
      login_user: root
      login_password: "{{ mysql_root_password }}"
    notify:
    - Restart MySQL
  - name: Remove the MySQL test database
    mysql_db:
      name: test
      state: absent
      login_user: root
      login_password: "{{ mysql_root_password }}"
    notify:
    - Restart MySQL
  - name: Change bind address
    lineinfile:
      path:  /etc/mysql/mysql.conf.d/mysqld.cnf
      regexp: ^bind-address
      line: 'bind-address            = 0.0.0.0'
    notify:
    - Restart MySQL
  handlers:
  - name: Restart MySQL
    service: name=mysql state=restarted
```

### MySQL client creds template (`client.my.cnf.j2`)
```ini
[client]
user=root
password={{ mysql_root_password }}
```

### App page as Jinja2 template (`index.php.j2`)
```php
<?php
mysqli_connect('db', '{{ mysql_user }}', '{{ mysql_password }}')
or die('Could not connect the database : Username or password incorrect');
echo 'Database Connected successfully';
?>
```

### Role directory structure (convention)
```
<playbook>.yaml
roles/
    <role>/
        tasks/        # main.yaml (+ included task files)
        handlers/     # main.yaml
        library/      # custom Python modules
        files/        # static files to copy
        templates/    # Jinja2 .j2 templates
        vars/         # main.yaml: vars unlikely to change
        defaults/     # main.yaml: overridable default vars
        meta/         # role metadata + dependencies
```

### Role-based playbook
```yaml
---
- hosts: webservers
  become: true
  roles:
    - common
    - apache
- hosts: dbservers
  become: true
  roles:
    - common
    - mysql
```

### Variable types
```yaml
# simple
mysql_root_password: bar          # ref as "{{ mysql_root_password }}"
# list
region:
  - europe-west1
  - europe-west2                  # ref as "{{ region[0] }}"
# dictionary
foo:
  bar: one
  baz: two                        # ref as {{ foo.bar }} (dot) or {{ foo['bar'] }} (bracket)
```

## Decision guidance and best practices
- **Prefer specific modules over `command`/`shell`** for idempotency (use `apt` module, not `command: apt install`). "If your playbook starts to look like code, you're doing something fundamentally wrong."
- **Use aliases** in inventory, not raw IPs/hostnames, survives address/hostname changes.
- **Group inventory by function** (role) so the same config applies to many like machines.
- **Keep `ansible.cfg` + inventory in each app's Git repo**: decentralized, GitOps, Git as single source of truth.
- **Roles should model a service, not the full stack**: use `apache` and `mysql` roles, NOT a single `lamp` role.
- **Name roles precisely** (`apache`, `mysql`) not generically (`webserver`, `dbserver`): enterprises mix technologies.
- **Keep roles loosely coupled**: `apache` must not depend on `mysql` so each can be reused independently.
- **`vars/` vs `defaults/`**: put values that won't change in `vars/`. Put values likely to change (overridable) in `defaults/`. Prefer `defaults/`.
- **Minimize variables and default them** so minimal custom config is needed, override via `--extra-vars` when necessary.
- **Bracket notation `foo['bar']` over dot `foo.bar`** for dict vars, dot keys can collide with Python dict methods/attributes.
- **Update packages/repos first** (`apt update_cache=yes`) at the start of every config to avoid install issues.
- **Always `--syntax-check`** a playbook before applying.
- **Inventory mgmt**: separate inventory per environment, group by function, use aliases.

## Pitfalls and gotchas
- Forgetting `become: true` means tasks needing root (apt, service, file writes) fail.
- Handlers run ONLY on `CHANGED`: a task that's already in desired state won't trigger the restart. Never rely on a handler firing every run.
- Config files are NOT merged across locations. The first `ansible.cfg` found wins entirely.
- `/etc/ansible` is root-owned by default: `chown` it to the `ansible` user or keep config in your repo.
- Quote Jinja expressions in YAML (`"{{ var }}"`). Unquoted leading `{{` breaks YAML parsing.
- Variable names can't be Python keywords and can't start with a digit (may start with `_`).
- The init scripts `sleep 120` before SSH key exchange, Azure may take a while. If IPs are missing after apply, use `terraform output`.
- `host_key_checking = False` in `ansible.cfg` (or pre-seeded `known_hosts`) is needed or SSH prompts block runs.

## Command / API cheat-sheet
- `ansible --version`: show installed Ansible version.
- `ansible all -m ping`: test SSH connectivity to all nodes.
- `ansible <target> -m <module> -a "<args>"`: run an ad-hoc task.
- `ansible -m setup <group>`: gather/print Ansible facts (metadata).
- `ansible-inventory --list -y`: show parsed inventory as YAML.
- `ansible --list-hosts <group|all>`: list hosts in a group.
- `ansible-playbook <file> --syntax-check`: validate playbook syntax.
- `ansible-playbook <file>`: apply a playbook.
- `ansible-playbook <file> --extra-vars "k=v k2=v2"`: override variables at runtime.
- Key modules: `apt` (packages), `service` (start/enable/restart), `copy` (push files), `file` (manage files/state=absent), `template` (render `.j2`), `lineinfile` (regex line edit), `mysql_user`, `mysql_db`, `command`/`shell` (avoid), `debug` (print), `ping`, `setup` (facts).
- Play keywords: `hosts`, `become`, `vars`, `tasks`, `handlers`, `roles`, `notify`, `register`, `ignore_errors`, `import_playbook`, `include`.

## Where this is covered (topic index)
- **What is CM / CaC, why declarative** → Core concepts, "Introduction to configuration management".
- **Ansible architecture, control vs managed node, agentless/SSH** → Core concepts, Tools.
- **Provision lab VMs with Terraform on Azure** → Workflow 1.
- **Passwordless SSH bootstrap (ssh-keygen, ssh-copy-id, sshpass)** → Workflow 2, SSH bootstrap snippets.
- **Install Ansible (PPA, apt-add-repository)** → Workflow 2.
- **Inventory file / hosts / groups / aliases / ansible_host** → Workflow 3-4, Inventory snippet.
- **ansible.cfg, config precedence, ANSIBLE_CONFIG** → Workflow 3, ansible.cfg snippet.
- **ansible-inventory, list-hosts, ping connectivity** → Workflow 4, cheat-sheet.
- **Tasks vs modules, `-m`/`-a`, SUCCESS/CHANGED/FAILURE** → Workflow 5, Core concepts.
- **Playbook structure (plays, hosts, tasks), syntax-check, play recap** → Workflows 6, Core concepts.
- **LAMP stack build, import_playbook, playbook-of-playbooks** → Workflow 7.
- **Handlers and notify (restart on change)** → Configure Apache/MySQL snippets, Core concepts.
- **become / sudo / root execution** → snippets, Pitfalls.
- **Variables: simple/list/dictionary, dot vs bracket** → Workflow 8, Variable types snippet.
- **Ansible facts / setup module / ansible_hostname** → Workflow 8.
- **register / capturing task output / debug** → Workflow 8, register snippet.
- **Jinja2 templates / `.j2` files / `{{ }}`** → Workflow 9, index.php.j2, client.my.cnf.j2.
- **Roles: directory layout, vars vs defaults, include, --extra-vars** → Workflow 9, role snippets, best practices.
- **Best practices (module choice, role naming, loose coupling, GitOps)** → Decision guidance.
- **MySQL hardening (anonymous users, test db, bind-address, lineinfile)** → Configure MySQL snippet.
