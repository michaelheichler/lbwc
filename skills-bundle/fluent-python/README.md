# Fluent Python Universal Skill

> Universal Claude Code and Codex skill for applying practical Python design guidance distilled from *Fluent Python*, 2nd Edition.

This private repository contains two installable variants of the same skill:

- `claude-code/fluent-python/` for Claude Code
- `codex/fluent-python/` for Codex

## Installing / Getting Started

Install for Claude Code:

```shell
mkdir -p ~/.claude/skills
cp -a claude-code/fluent-python ~/.claude/skills/
```

Install for Codex:

```shell
mkdir -p ~/.codex/skills
cp -a codex/fluent-python ~/.codex/skills/
```

Test in Claude Code:

```shell
claude -p '/fluent-python Review this Python API design for protocol, dataclass, iterator, or async pitfalls.'
```

## Features

- Routes Python questions to chapter-separated guidance.
- Covers data model methods, collections, text/bytes, dataclasses, object references, functions, decorators, protocols, inheritance, type hints, operators, iterators, context managers, concurrency, async, descriptors, and metaprogramming.
- Keeps detailed chapter notes in `references/` so the agent loads only the relevant material.
- Includes a Codex variant with `agents/openai.yaml` metadata and a Claude Code variant without Codex-only metadata.

## Repository Layout

```text
claude-code/
  fluent-python/
    SKILL.md
    references/
codex/
  fluent-python/
    SKILL.md
    agents/
    references/
README.md
```

The repository README stays at the repo root. Do not add `README.md` inside either installed skill folder.

## Configuration

No runtime configuration is required. The skill uses Markdown instructions and bundled references only.

## Links

- Claude Code install target: `~/.claude/skills/fluent-python`
- Codex install target: `~/.codex/skills/fluent-python`

## Licensing

Private repository. No license is granted unless a LICENSE file is added. The underlying book remains copyrighted by its rights holders. This repository contains paraphrased skill guidance, not original book text.
