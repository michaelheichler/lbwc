# Source attribution and boundaries

## Source

This skill distills the principles taught in:

> **Clean Code: Principles and Patterns, Python Edition**
> Petri Silen, 2024 (Leanpub).

All copyright in the book remains with the author and publisher. This repository
is an independent, derivative *study aid* (a set of paraphrased, agent-facing
references plus original/adapted example code) created for private use.

## What this repository contains (and does not)

- **References (`skills/.../references/`)** are **paraphrased guidance written
  fresh** for this project. They do **not** reproduce the book's prose. They
  restate principles in our own words, with our own Python examples, so an AI
  coding agent can apply them. Treat them as notes, not as the book.
- **Example code (`skills/.../examples/`)** is **original or substantially
  rewritten** Python that demonstrates each principle: modernized to Python
  3.12+, fully type-hinted, and linted clean. Where the book ships companion
  source, our examples are adaptations (re-commented and improved), not verbatim
  copies.
- We do **not** redistribute the book, its text, its figures, or its original
  source-code listings.

## If you are the rights holder

If you are the author or publisher and would like any portion changed or removed,
open an issue or contact the repository owner and we will comply promptly.

## Companion tooling

The enforcement layer (`scripts/clean_check.py`, `mcp-server/`) is original work
released under this repository's licence. It orchestrates third-party tools
(`ruff`, `mypy`) and a set of custom AST rules to apply the principles above.
