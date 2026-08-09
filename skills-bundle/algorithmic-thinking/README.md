# Algorithmic Thinking Skill

Private Claude Code and Codex skill for algorithmic problem solving, competitive programming, and data structure selection using guidance derived from *Algorithmic Thinking* by Daniel Zingaro.

## What It Covers

This skill helps an agent recognize and explain algorithmic patterns across:

- Hash tables
- Trees and recursion
- Memoization and dynamic programming
- Graphs and breadth first search
- Dijkstra shortest paths
- Binary search on the answer
- Heaps and segment trees
- Union find
- Randomized algorithms
- Time and space complexity tradeoffs

## Repository Layout

```text
SKILL.md
references/
  appendix-a-algorithm-runtime.md
  appendix-b-extras.md
  appendix-c-problem-credits.md
  ch00-introduction.md
  ch01-hash-tables.md
  ch02-trees-and-recursion.md
  ch03-memoization-and-dp.md
  ch04-advanced-memoization-and-dp.md
  ch05-graphs-and-bfs.md
  ch06-shortest-paths-weighted-graphs.md
  ch07-binary-search.md
  ch08-heaps-and-segment-trees.md
  ch09-union-find.md
  ch10-randomization.md
  code-examples.md
install.sh
README.md
```

## Install

Show available installer targets:

```shell
./install.sh --help
```

Install to Claude Code:

```shell
./install.sh claude
```

Install to Codex:

```shell
./install.sh codex
```

Install to the shared agent skill folder:

```shell
./install.sh agents
```

Install to Claude Code and Codex, then build the Codex package:

```shell
./install.sh --all
```

Build a Codex package without installing:

```shell
./install.sh package
```

The package is written to `dist/algorithmic-thinking.skill`.

## Manual Install

Claude Code:

```shell
mkdir -p ~/.claude/skills/algorithmic-thinking
cp SKILL.md ~/.claude/skills/algorithmic-thinking/
cp -a references ~/.claude/skills/algorithmic-thinking/
```

Codex:

```shell
mkdir -p ~/.codex/skills/algorithmic-thinking
cp SKILL.md ~/.codex/skills/algorithmic-thinking/
cp -a references ~/.codex/skills/algorithmic-thinking/
```

Shared agent skill folder:

```shell
mkdir -p ~/.agents/skills/algorithmic-thinking
cp SKILL.md ~/.agents/skills/algorithmic-thinking/
cp -a references ~/.agents/skills/algorithmic-thinking/
```

## Validate

Use the local skill validator:

```shell
python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py .
```

## Example Use

```text
Use $algorithmic-thinking to identify the right approach for this graph problem and explain the complexity tradeoffs.
```

## Licensing

Private repository. No license is granted unless a `LICENSE` file is added. The underlying book remains copyrighted by its rights holders. This repository contains skill guidance and notes, not a grant of rights to the book.
