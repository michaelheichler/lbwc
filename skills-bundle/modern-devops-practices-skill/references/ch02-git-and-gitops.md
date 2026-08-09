# Chapter 02: Source Code Management with Git and GitOps

> Part 1: Modern DevOps Fundamentals · Modern DevOps Practices, 2nd Ed. (Gaurav Agarwal, Packt 2024)

## When to use this file
Open this when you need to perform basic Git operations (init, stage, commit, branch, push, pull/rebase, resolve merge conflicts, raise pull requests) the way the book teaches, or when you need to design a GitOps setup: push vs pull deployment models, application vs environment repositories, and branching strategy (Gitflow vs GitHub flow).

## Core concepts
- **Source code management (SCM):** Central, secure store for source code with version history, multi-developer collaboration, branching/merging, change tracking, and peer review. De facto standard tool is Git (alternatives: Subversion, Mercurial, CVS).
- **Source code vs binaries:** Source = human-readable high-level code. Binaries = compiled, runnable artifacts. SCM tracks source.
- **Git is distributed:** Every repository is a full copy of the original. A central copy is the **remote repository** that all developers sync against.
- **Staging area:** Temporary holding area between working tree and a commit. Files move in via `git add`, out via `git restore`/`git rm --cached`.
- **Delta tracking:** Git records only the change (delta) between commits, shown with `+`/`-` signs.
- **Commit ID:** Each commit gets a SHA-1 hash. Amending a commit creates a NEW SHA-1, and the old ID no longer resolves.
- **Merge conflict:** Occurs when you and someone else changed the same lines. Git marks conflicts with `<<<<<<< HEAD`, `=======`, `>>>>>>> <commit>` and requires manual resolution.
- **Branch:** Independent copy of the code base from its branch point. Lets you work without affecting the main/reviewed branch. Branches diverge once committed to independently.
- **Pull request (PR):** Request to merge a **source branch** into a **base branch** (where reviewed code lives, e.g. `master`). Enables peer review, change requests, approval, then merge.
- **GitOps:** A method of implementing DevOps where **Git is the single source of truth**. Everything (infrastructure, configuration, application code, and the tooling itself) is declarative code in Git, and behind-the-scenes tooling continuously enforces the declared desired state. GitOps implements DevOps. DevOps does not require Git, so the reverse is not always true.
- **Idempotent declarative state:** You declare the end state, not the steps. Re-applying converges the system to the same state, so you needn't track current state.

## Tools and versions
- **Git** 2.30.2 (version shown in the book). Distributed VCS / SCM. Install on Ubuntu: `sudo apt install -y git-all`. Windows users install **GitBash** from https://git-scm.com/download/win.
- **GitHub**: web-based SaaS for hosting remote Git repos and collaboration (founded 2008, acquired by Microsoft 2018). Book focuses on GitHub. Other remote hosts: Bitbucket, Gerrit, GitLab.
- **Push-model tools:** Jenkins, CircleCI, Travis CI. Also Terraform (IaC) and Ansible (CaC) are inherently push-based.
- **Pull-model / GitOps operators:** Argo CD, Flux, Jenkins X, Weave Flux (used later in Ch. 11-12).
- **Branching strategies:** Gitflow, GitHub flow.

## Workflows (how-to)

### Install and verify Git
```bash
sudo apt install -y git-all     # Ubuntu
git --version                   # expect: git version 2.30.2
```

### Initialize a local repository
```bash
mkdir first-git-repo && cd first-git-repo/
git init                        # creates hidden .git/ tracking directory
```

### Stage and commit changes
```bash
touch file1
git status                      # shows file1 as Untracked
git add file1                   # stage the file
git status                      # shows file1 under "Changes to be committed"
git commit -m "My first commit"
git status                      # "working tree clean"
```
Edit then commit again:
```bash
echo "This is first line" >> file1
git add file1
git commit -m "My second commit"
```

### View history and diffs
```bash
git log                         # full commit history with SHA-1 IDs, author, date
git diff <first_commit_id> <second_commit_id>   # show changes between two commits
```

### Amend the last commit
Use to fold a forgotten change into the previous commit (keeps one commit per feature).
```bash
echo "This is second line" >> file1
git add file1
git commit --amend              # opens editor to optionally edit message; ESC:wq in Vim
```
Note: amending generates a new SHA-1, the old commit ID is gone.

### Set up SSH auth with GitHub (recommended over HTTPS)
HTTPS requires keying a token every time. SSH is more secure and convenient.
```bash
ssh-keygen -t rsa               # press Enter through prompts
# copy contents of ~/.ssh/id_rsa.pub
```
Then paste the public key at https://github.com/settings/ssh/new → "Add SSH Key".

### Create remote repo and connect local to it
1. Create at https://github.com/new with Repository Name `first-git-repo`, defaults, "Create Repository".
2. Add the remote and push:
```bash
git remote add origin git@github.com:<your-github-username>/first-git-repo.git
git push -u origin master       # -u sets master to track origin/master
```

### Pull, rebase, and resolve a merge conflict
When a push is rejected (`! [rejected] ... (fetch first)`) because the remote has newer commits:
```bash
git pull --rebase               # apply your changes on top of latest remote commit
```
If a conflict appears (`CONFLICT (content): Merge conflict in file1`), the file contains markers:
```
This is first line
This is second line
<<<<<<< HEAD
This is third line
=======
This is fourth line
>>>>>>> e411e91 (Added fourth line)
```
`HEAD` = remote changes, the labeled commit = your local changes. Edit the file to the desired final content (remove markers), then:
```bash
git add file1
git rebase --continue           # other options: git rebase --skip / git rebase --abort
git status                      # "Your branch is ahead of 'origin/master' by 1 commit"
git push
```

### Create, switch, and push branches
```bash
git branch feature/feature1     # create branch from current branch
git branch                      # list; * marks current branch
git checkout feature/feature1   # switch to the branch
echo "This is feature 1" >> file1
git add file1
git commit -m "Feature 1"
git push -u origin feature/feature1   # push new branch and set tracking
```
Branches are isolated: a commit on `feature/feature1` will not appear in `git log` on `master` until merged.

### Raise and merge a pull request (GitHub UI)
1. Repo → **Pull requests** → **New pull request**.
2. Set **base** = `master`, **compare** = `feature/feature1`.
3. **Create pull request**, keep defaults, **Create pull request** again.
4. Assign a reviewer. After approval, **Merge pull request** → **Confirm merge**.
5. Locally: `git checkout master` then `git pull` to sync the merged changes.

## Decision guidance and best practices

### GitOps deployment models
- **Push model:** Tooling pushes Git changes to the environment. Unaware of existing/drifted state (needs separate monitoring), and must store environment credentials in the tools. Implemented with Jenkins, CircleCI, Travis CI. Inevitable for Terraform cloud provisioning and Ansible config management (both push-based).
- **Pull model (operator/agent-based):** An operator inside the environment continuously compares live state against the environment repo and applies/reverts to match. Reacts to environment drift as well as repo changes, alerts ops (email/ticketing/Slack) when it can't self-heal. No credentials in tools, they live in the environment (e.g., Kubernetes RBAC + service accounts). **Recommended.**
- **Hybrid model:** Most orgs combine both: prefer pull, fall back to push only where pull isn't possible.

**Best practice:** Prefer the pull model. Use push only when pull is impossible. In a push model, schedule polling (e.g., a `cron` job) to re-run the push periodically and catch configuration drift.

### Repository structure (two repos minimum)
- **Application repository:** Holds application code, builds (e.g., containers) originate here. Usually independent of environments, focus on semantic versions via a branching strategy.
- **Environment repository:** Holds environment-specific IaC (Terraform), CaC (Ansible playbooks), or Kubernetes manifests. Acts as the single source of truth for environments, config added here applies directly. Use an **environment-per-branch** strategy with PR-based **gating** (e.g., dev branch → PR → staging branch → production). 10 environments ≈ 10 branches.
- **Best practice:** Keep application and environment repos separate. This cleanly separates CI (application repo) from CD (environment repo). They can be combined, but separation is preferred.

### Branching strategy: Gitflow vs GitHub flow
- **Gitflow:** Many branch types (master, hotfixes, release, develop, feature), rigid, complex. Choose for **large teams, vast monolithic repos, multiple parallel releases**. Do NOT use Gitflow for the environment repository.
- **GitHub flow:** Single `master` (always deployable) + many short-lived feature branches that merge back. Tag/version on master, deploy, test, promote upward. Choose for **fast-paced orgs releasing several times a week, no parallel releases, microservices** with small quick changes.

### Why GitOps (benefits)
- Deploy better software faster: just commit, tooling deploys.
- Faster recovery: roll back with `git revert`, no extra tooling to learn.
- Better credential management: give tooling access to Git + artifact repo only, restrict env access.
- Self-documenting deployments: commit history records who deployed what, when.
- Shared ownership/knowledge: Git is the single place of truth.

### GitOps principles
1. Describe the entire system **declaratively**.
2. **Version** desired state in Git (commit = deploy, revert = rollback).
3. Use **tooling to automatically apply** approved changes (branch-per-env + PR gating).
4. Use **self-healing agents** to alert on and correct divergence (e.g., recreate a manually deleted container).

## Pitfalls and gotchas
- **Push rejected (`fetch first`):** Remote has commits you don't. Run `git pull --rebase` before pushing again. Do not force-push.
- **Amend changes the commit ID:** After `git commit --amend`, the old SHA-1 no longer resolves, references/links to it break.
- **Editing files directly in the GitHub web UI** is not recommended (book uses it only to simulate a concurrent edit): it causes the divergence/merge-conflict situations above.
- **Push model is blind to drift:** It only reacts to repo changes, so you must add monitoring and ideally cron-based polling.
- **Push model stores credentials in tools**: a larger attack surface than the pull model.
- **Don't use Gitflow for environment repos**: environment repos want environment-per-branch, not Gitflow's release/hotfix structure.

## Command / API cheat-sheet
- `git init`: initialize a local repository.
- `git status`: show working tree / staging state.
- `git add <file>`: stage a change.
- `git restore` / `git rm --cached <file>`: unstage.
- `git commit -m "msg"`: record staged changes.
- `git commit --amend`: fold staged changes into the last commit (new SHA-1).
- `git log`: show commit history.
- `git diff <id1> <id2>`: show changes between commits.
- `git remote add origin <git@...>`: link local repo to a remote.
- `git push -u origin <branch>`: push and set upstream tracking.
- `git push`: push to tracked upstream.
- `git pull --rebase`: fetch and replay local commits on top of remote.
- `git rebase --continue | --skip | --abort`: control an in-progress rebase.
- `git branch <name>`: create a branch. `git branch` lists (current marked `*`).
- `git checkout <branch>`: switch branches.
- `git clone`: copy a remote repo locally (summary command list).
- `git revert`: roll back a commit (GitOps rollback mechanism).
- `ssh-keygen -t rsa`: generate SSH key pair for GitHub auth.

## Where this is covered (topic index)
- SCM definition / source vs binaries / why SCM → "Core concepts". Install Git → "Install and verify Git".
- git init / first repo → "Initialize a local repository".
- staging / git add / git restore → "Stage and commit changes".
- commit / commit message → "Stage and commit changes".
- git log / git diff / commit history / SHA-1 → "View history and diffs".
- amend / fix last commit → "Amend the last commit".
- remote repository / GitHub / Bitbucket / Gerrit / GitLab → "Tools and versions" + "Create remote repo and connect".
- SSH key / HTTPS token / authentication → "Set up SSH auth with GitHub".
- git remote add origin / connect local to remote → "Create remote repo and connect".
- git push / rejected push → "Create remote repo" + "Pull, rebase, and resolve a merge conflict".
- git pull / rebase / merge conflict / conflict markers → "Pull, rebase, and resolve a merge conflict".
- branch / checkout / feature branch / diverge → "Create, switch, and push branches".
- pull request / PR / code review / base vs source branch / merge → "Raise and merge a pull request".
- GitOps definition / single source of truth / declarative → "Core concepts".
- why GitOps / benefits / git revert rollback / self-documenting → "Why GitOps (benefits)".
- GitOps principles / self-healing / idempotent → "GitOps principles".
- push model / pull model / hybrid / operator / agent / cron polling → "GitOps deployment models".
- Jenkins / CircleCI / Travis CI / Terraform / Ansible (push) → "GitOps deployment models".
- Argo CD / Flux / Jenkins X / Weave Flux (pull operators) → "Tools and versions".
- application repository / environment repository / CI vs CD separation / gating → "Repository structure".
- Gitflow vs GitHub flow / branching strategy / monolith vs microservices → "Branching strategy".
- Git vs GitOps differences → "Core concepts" (GitOps implements DevOps, reverse not always true).
