---
name: discipline-of-programming-dijkstra
description: Apply Dijkstra's program-derivation discipline from A Discipline of Programming and Structured Programming (Dahl, Dijkstra, Hoare). Use this skill whenever the task is to design, implement, review, or debug an algorithm or a loop and correctness matters, including deriving code from a postcondition, choosing a loop invariant, proving termination with a variant function, reasoning with weakest preconditions or guarded commands, stepwise refinement, choosing a data structure by its abstract type, or judging whether a program is correct by construction rather than by testing.
---

# A Discipline of Programming (Dijkstra)

## Purpose

Use this skill to design programs the Dijkstra way: state the postcondition
first, derive the program from it, and let the proof and the code grow
together. The bundled references are paraphrased briefs of two books.

- A Discipline of Programming (Dijkstra, 1976): weakest preconditions,
  guarded commands, invariants, variants, and 16 worked derivations.
- Structured Programming (Dahl, Dijkstra, Hoare, 1972): why testing cannot
  show the absence of bugs, stepwise refinement, data structuring by abstract
  type, and hierarchical program structure.

## Source boundary

Use the references as method guidance for design, derivation, review, and
implementation decisions. Do not reproduce book prose or full derivations.
When notation helps, write only the minimal generic form the task needs.
Prefer the user's language and codebase idiom over book notation. Dijkstra's
mini-language is a reasoning tool, not a coding target.

## Workflow

1. Classify the task: semantics question, loop or algorithm to derive, an
   existing loop to verify, a data-structure choice, or a program structure
   question.
2. Load the one to three most relevant references from the routing table.
3. Write the postcondition R before any code. If R is vague, make the user's
   acceptance criterion precise first.
4. Derive, do not guess: choose an invariant P by weakening R, choose guards
   so that P and (not guards) implies R, choose a variant function to prove
   termination, then translate to the target language.
5. In review, run the same checks backward: find the invariant the loop
   maintains, the variant that bounds it, and the reason every guard case is
   covered. A loop with no nameable invariant is a finding.

## Routing table

Method core (load these for most tasks):

- Predicate transformers, weakest preconditions, states and predicates: `references/d02-states-and-semantic-characterization.md`
- wp rules for skip, abort, assignment, composition, if-fi, do-od, guarded commands, the two loop theorems: `references/d03-wp-semantics-of-the-language.md`
- Termination, variant (bound) functions, Euclid's gcd as invariant-driven design: `references/d04-termination-and-euclid.md`
- Deriving programs from postconditions, choosing invariants by weakening the postcondition: `references/d05-formal-treatment-of-small-examples.md`
- Testing versus proving, program size and our limited heads, abstraction, stepwise refinement: `references/s13-notes-on-structured-programming-i.md`
- Refinement worked end to end (eight queens), program families, layering: `references/s14-notes-on-structured-programming-ii.md`

Concepts and language design:

- Executional abstraction, role of programming languages: `references/d01-executional-abstraction-and-languages.md`
- Nondeterminacy and why it stays bounded, scope and initialization of variables: `references/d06-nondeterminacy-and-scope.md`
- Arrays as functions, array assignment semantics: `references/d07-array-variables.md`
- Manuals, implementations, and Dijkstra's own retrospect on the discipline: `references/d12-strong-components-manuals-retrospect.md`

Worked derivations (load the one matching the problem shape):

- Linear search, next permutation, Dutch national flag, sequential file update, merging: `references/d08-search-permutation-flag-file-merging.md`
- Hamming numbers, pattern matching, sum of two squares: `references/d09-hamming-pattern-matching-two-squares.md`
- Smallest prime factor, most isolated villages, shortest spanning tree: `references/d10-prime-factor-villages-spanning-tree.md`
- Union-find (Rem's algorithm), 3D convex hull: `references/d11-rem-equivalence-convex-hull.md`
- Strong components in a directed graph: `references/d12-strong-components-manuals-retrospect.md`

Data and program structure (Hoare, Dahl):

- Types, cartesian products, discriminated unions, arrays: `references/s15-notes-on-data-structuring-i.md`
- Powersets, sequences, recursive data structures, sparse representation: `references/s16-notes-on-data-structuring-ii.md`
- Classes, objects, coroutines, hierarchical decomposition: `references/s17-hierarchical-program-structures.md`

## Review heuristics

- Every loop names its invariant and its variant. No variant, no termination claim.
- The postcondition comes before the code. Code without a stated R is a guess.
- Case analysis is complete by construction: the disjunction of the guards must be provable, not assumed.
- Prefer the derivation that makes the proof short over the code that looks clever.
- Testing demonstrates presence of bugs, never absence. A passing test is evidence, not proof.
- Separate mathematical correctness concerns from efficiency concerns, in that order.

## Output style

State assumptions and the postcondition first. Show the invariant and variant
as short annotations next to the loop, not as an essay. Translate guarded
commands to the user's language idiomatically. When a derivation is the
deliverable, show the key steps, not every algebraic line.
