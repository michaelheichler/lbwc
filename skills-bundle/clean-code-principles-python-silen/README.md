# clean-code-principles-python-silen

A Claude Code **skill** + **MCP server** that makes the AI write Python the way Petri
Silen's *Clean Code: Principles and Patterns, Python Edition* (2024) prescribes, and
then **checks its own code** (ruff + mypy + custom rules) so it ships defect-free.

It pairs with the `fluent-python` skill: this is the *design & principles* layer,
and fluent-python is the *language-idiom* layer.

## What you get

- **Skill** (12 Python-centric chapter references + 62 runnable, lint-clean examples that
  Claude consults while writing or reviewing Python).
- **MCP server** (tools Claude can call: `check_python` (lint + type-check + book rules),
  plus `search_principles`, `get_principle`, `list_principles`, `list_examples`,
  `get_example`).

## Requirements

- [**Claude Code**](https://docs.claude.com/en/docs/claude-code) (the `claude` CLI)
- [**uv**](https://docs.astral.sh/uv/) on your `PATH` (runs the server, fetches ruff/mypy)
- **git** and **Python ≥ 3.10**

## Install

Run these in a terminal. The skill is symlinked, so future `git pull`s update it live.

```bash
# 1. Clone
git clone https://github.com/michaelheichler/clean-code-principles-python-silen.git
cd clean-code-principles-python-silen

# 2. Install the skill
mkdir -p ~/.claude/skills
ln -sfn "$(pwd)/skills/clean-code-principles-python-silen" \
        ~/.claude/skills/clean-code-principles-python-silen

# 3. Register the MCP server (user scope = available in every project)
claude mcp add clean-code --scope user \
  -e CLEAN_CODE_SKILL_DIR="$(pwd)/skills/clean-code-principles-python-silen" \
  -- uv run --project "$(pwd)/mcp-server" clean-code-mcp

# 4. Restart Claude Code (so it picks up the new skill + server)
```

## Check it works

```bash
# MCP server connected?  → should print "Status: ✓ Connected"
claude mcp get clean-code

# Checker runs?  → should report problems in the bundled bad example
python3 skills/clean-code-principles-python-silen/scripts/clean_check.py \
        evals/fixtures/messy_order_service.py --no-mypy
```

The first `uv run` downloads the server's dependencies (one-time, ~30s).

## Use it

- In a new Claude Code chat, just work on Python ("review this", "write a service…").
  The skill triggers on its own and Claude runs `check_python` before handing code back.
- Standalone, on any file of your own:

  ```bash
  python3 skills/clean-code-principles-python-silen/scripts/clean_check.py your_file.py
  ```

## Update / uninstall

```bash
git pull                                              # update (symlink stays live)

claude mcp remove clean-code -s user                 # remove the server
rm ~/.claude/skills/clean-code-principles-python-silen   # remove the skill (symlink only)
```

## More

- `mcp-server/README.md` (server tools and Claude Desktop setup)
- `skills/clean-code-principles-python-silen/SKILL.md` (what Claude reads)
- `evals/benchmark.md` (with-skill vs baseline results)
- `NOTICE.md` (source & boundaries, paraphrased study aid, not the book)
