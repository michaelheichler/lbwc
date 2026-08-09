---
unit: "Book S, Part I, Sections 11-17 (second half)"
slug: "s14-notes-on-structured-programming-ii"
title: "Notes on Structured Programming II: Refinement Worked Out"
book: "Structured Programming"
one_liner: "Dijkstra works stepwise refinement end to end: layered virtual machines, programs as necklaces of exchangeable pearls, loop-structure choice, and the eight-queens derivation of backtracking and recursion."
when_to_use: "Load when decomposing a program top-down, choosing module boundaries and data representations, structuring nested loops, building a family of program variants, or deriving a backtracking search."
topics: [stepwise refinement, layered abstraction, virtual machines, program families, pearls, module boundaries, data representation, derived variables, caching, backtracking, eight queens, recursion, loop structure, interfaces]
key_terms: [pearl, necklace, virtual machine, program family, range of validity, derived variable, set B technique, operational abstraction, cut, refinement]
related: [s13-notes-on-structured-programming-i, s15-notes-on-data-structuring-i, s17-hierarchical-program-structures, d01-executional-abstraction-and-languages]
---

# Notes on Structured Programming II: Refinement Worked Out

The second half of Dijkstra's "Notes on Structured Programming": the layered-machine program model, two fully worked refinements (the line-printer plotter and eight queens), and the pearls-and-necklaces argument for program families. **Source:** Structured Programming, Part I, Sections 11-17.

## TLDR

- A program is best conceived as layers: each layer is a complete program for a virtual machine, and the layer below implements that machine. Correctness of a layer is established against the machine's manual, not its implementation.
- Each layer ("pearl") embodies exactly one design decision. A program is a "necklace" of pearls, and modification means replacing pearls, not editing a flat text.
- A program family comes first, the single program second. Make more pearls than one necklace needs and string variants from selections. This is how a thousand versions stay affordable.
- Order design decisions so that representation commitments come as late as possible. Fixing the data representation early forces every later decision to be expressed in representation terms and thickens the coupling.
- Variables that cache a function of other variables (derived, redundant variables) are legitimate and often essential for performance, but they are optimizing refinements of a more abstract program and should be recognized as such.
- Loop structure should mirror problem structure: pick the grain of the loop body deliberately, prefer a loop nest whose levels correspond to natural units, and treat "if B do S" where S falsifies B as a proven-once "while B do S".
- The eight-queens development derives backtracking (generate a superset, filter it) and the recursive procedure (eight identical nested loops collapsed into one text) from first principles, with the board representation chosen last.

## When to reach for this

- You are splitting a feature into modules and must decide which decision each module owns and in what order to commit to interfaces and representations.
- You need several variants of one program (feature flags, storage backends, output formats) and want them to share structure instead of forking.
- You are writing a search or enumeration (backtracking, combinatorial generation) and want a principled derivation instead of pattern-matching a template.
- You are adding a cache, counter, or precomputed table and want to keep it clearly separated from the abstract algorithm it accelerates.
- A loop or loop nest feels tortured (awkward stop criterion, redundant tests) and you suspect the grain of the iteration is wrong.

## Key concepts

### Derived variables: trading storage for speed

A variable `fun` maintained so that `fun = FUN(arg)` holds saves recomputation. Three versions of one program: A recomputes FUN(arg) on demand, B updates `fun` at every assignment to `arg`, C adds a boolean `fun_up_to_date` and recomputes lazily. All three are output-equivalent. The deeper reason for such variables is that computing how FUN changes under a small change of `arg` is often far cheaper than computing FUN from scratch, especially when `arg` has a known history (for example, it only increases). Dijkstra insists these variables be recognized as redundant, as an optimizing refinement of a more abstract program, even when the optimization is what makes the program feasible at all. The abstraction is not daydreaming: it is what keeps the correctness argument small, and the optimizing refinement is rarely unique.

### The program as a hierarchy of virtual machines

View the main program as executed by a dedicated machine with exactly the right instructions and variables. That machine does not exist, so the next task, structurally identical to the first, is to program its simulation on a lower machine, and so on down to hardware. Each layer is understood by itself given the manual of the machine below it. Why this model: it matches how stepwise composition already works, it lets many modifications be phrased as swapping one virtual machine for a compatible one, it says precisely which state is interpretable when execution is stopped between instructions of some level (all lower machines passive, all higher machines mid-instruction), it helps bound the damage of a detected malfunction, and it counters the duplication risk of divide-and-rule because all programs of one layer share the same primitives.

### The plotter example: refinement with data structuring

Task: use a line printer (PRSYM, NLCR, no backspace) as a plotter for 1000 points (fx(i), fy(i)) on a 100 x 50 grid. Print order is dictated by the device, not by i, so the image must be stored first. The necklace, top to bottom, one decision per pearl:

1. COMPFIRST: `draw: {build; print}` over a variable `image`. Store first, then print.
2. CLEARFIRST: `build: {clear; setmarks}`. Treat mark-setting as updating an already-defined blank image.
3. ISCANNER: `setmarks` loops i from 0 to 999 calling `add mark(i, image)`.
4. COMPPOS: `add mark` computes x, y from fx, fy and calls `mark pos(x, y, image)`.
5. LINER: the first representation commitment. An image is an array of 50 lines, and `print`, `clear`, `mark pos` are translated into per-line operations. The image is now "explained away" and only the type `line` remains open.
6. LONGREP or SHORTREP: a line as a full 100-slot symbol array, or a symbol array plus a fill counter `f` so that clearing a line is just `f := 0` and trailing blanks are never printed. Two interchangeable bottom pearls for the same job.

Audiences objected that correctness could not be claimed before the representation existed (could `print` have side effects on `image`?). The answer: a primitive has to do what its manual states and nothing else, and such concerns are dealt with when, and not before, a representation is chosen. That so much program text is independent of the representation is the strength of the method.

A later note on SHORTREP's `linemark`: `if B do S` is used two ways, either S leaves B true, or S is guaranteed to falsify B. In the second case it is `while B do S` in disguise, plus a separate proof that the body runs at most once. Rewriting `linemark` as a while loop that pads with spaces until `x < f` holds, then marks, replaced a fiddly conditional with code whose precondition is established by its own first line. Dijkstra calls his original version lousy coding.

### Pearls, necklaces, and program families

Each pearl is a machine plus the refinements (algorithms and data structures) it introduces, embodying one independent design decision. Program modification becomes pearl replacement, a far safer operation than editing a linear symbol string, where every change must be understood in the universe of all syntactically possible programs. To keep, say, a thousand versions of a large program affordable, the only feasible route is combinatorial: make more pearls than one necklace needs (say 250 for a 200-pearl necklace) and string each variant from a selection. The top half of a necklace is a complete program for the machine that the bottom half implements, so its correctness is established regardless of the bottom half. The "cut" between two pearls is a machine manual, and this manual is the interface, which is more helpful than treating a data representation as the interface between operations.

Every concept has a range of validity along the necklace (here, `image` lives from COMPFIRST down to LINER, where it is explained away). Reordering decisions is possible but yields different pearls. Dijkstra tried the conventional advice "fix the interface between build and print first" by moving LINER up, and got a much messier program, because CLEARFIRST, ISCANNER, and COMPPOS were then forced to speak in terms of lines rather than the abstract image. Moral: the more pearls that are independent of a representation, the more adaptable and the more understandable the program. Adaptability and clarity go hand in hand, and elegance has quantitative substance (the thickness of the "logical rope" of overlapping concept ranges).

### Grouping and sequencing: choosing loop structure

Two examination examples show that where you put the loop boundaries is a design decision. In Wirth's problem (generate, in alphabetical order, ternary sequences with no equal adjacent subsequences), the flat one-loop program that tests each trial sequence has a tortuous stop criterion and redundant length tests. The better program nests "while no good do increase" inside a loop per solution, and is best understood as a refinement of an abstract loop over solutions only (`repeat transform sequence to next solution; print` until length 100). In Weizenbaum's problem (smallest number decomposable as a sum of two nth powers in two ways), stepping s through all integers is hopeless because almost none are decomposable. Deciding the iteration order too early was the error: iterate from decomposable value to next decomposable value, maintaining a collection of candidate pairs. Programming as "the judicious postponement of decisions and commitments."

The classroom account in Section 16 (copy words, reversing every odd-numbered one, normalizing separators) shows the same choices live: pick the grain of the repeatable statement (a whole word, not a character), introduce a state variable (`forward`) before detailing, then force an exact specification of which input characters are consumed and which output characters are produced per iteration. The clean grouping required reading the first character in the prelude, so every iteration handles "rest of word plus lookahead". The interface between the reading and printing halves (array `c`, count `l`) had to be stated explicitly before either half could be refined.

### Eight queens: deriving backtracking and recursion

The general method when you cannot generate solution set A directly: find a set B such that (1) A is a subset of B, (2) membership of A is cheap to decide for an element of B, and (3) B is easy to generate. Generate B, filter for A. Choose B as small as possible, make rejection cheap, and if B is itself hard to generate, apply the trick again with a set C containing B. Naively dropping one of the defining conditions of A gives sets that are ludicrously huge, so listing obvious properties of solutions is the cheap, disciplined move (Dijkstra warns against hunting for clever non-obvious properties before knowing they will be useful).

The key obvious property: removing any queen from a legal configuration leaves a legal configuration. Played backwards, every solution is built from the empty board by adding one queen at a time through legal configurations. Asking "in what order are solutions generated?" (a question Dijkstra says is usually illuminating, since it supplies the proof of "all solutions, each once") leads to representing a solution as x[0..7] with x[i] the column of the queen in row i, generated in alphabetical order. That fixes B: all legal configurations with one queen in each of the first N rows. The membership test for A is N = 8.

A single loop with "generate next element of B" is unattractive (no exhaustion test, awkward operator). Grouping the sequence dictionary-style, by position of queen 0, then queen 1, and so on, gives eight nested loops that are almost identical. Making the outermost test "square free" (harmlessly true) and replacing the innermost body with "if board full then print else generate deeper" makes all eight loops textually identical except for a private counter h, so they collapse into one recursive procedure `generate` with local h. Recursion is required here as a sequencing device: unlike a subroutine, a recursive procedure cannot be understood by separating "what it does" from "how it works" across two semantic levels, it must be conceived on a single level, and this is a distinct mental skill.

Representation is decided last. Logically x and n suffice, but testing whether a square is free would be painful, so derived boolean arrays are added exactly per the derived-variable technique: `col[0..7]`, `up[-7..7]` indexed by `n-h` (constant along upward diagonals), `down[0..14]` indexed by `n+h`. "Square free" becomes `col[h] and up[n-h] and down[n+h]`, and placing or removing a queen updates three booleans. A per-square cover counter (up to 28 updates per move) was considered and rejected as overkill. The whole analysis was carried out before the representation was chosen, and that isolation is the crucial point.

## Derivation playbook

For a top-down refinement (plotter pattern):

1. State the whole job as one abstract statement sequence over abstract variables, and write the manual for the machine it assumes.
2. Refine next whichever primitive can be detailed without committing the others. Defer any primitive whose refinement would force a representation choice.
3. Give each level exactly one design decision, and note which concepts it introduces and which it explains away.
4. Commit to data representations only when no representation-free refinement remains, and structure the data stepwise too.
5. Keep alternative refinements of the same primitive (LONGREP/SHORTREP) as siblings, not overwrites: they are the seeds of the program family.

For an enumeration or search (eight-queens pattern):

1. Define solution set A. Find a superset B that is easy to generate, keeps A's cheap-to-check structure, and is as small as you can make it. Recurse to a set C if B is still hard.
2. List obvious properties of solutions and look for an extension property (every solution reachable by growing partial solutions that stay in B).
3. Choose the output order (for example lexicographic). It fixes the generation order and carries the proof of "all solutions, each exactly once".
4. Express the generation as nested loops per decision level, make the levels textually identical, and collapse them into one recursive procedure with a depth counter and a private loop variable.
5. Only then pick the representation, and add derived variables (per-column, per-diagonal freedom flags) so the feasibility test is O(1) and each move updates them incrementally.

## Applying it in modern code

- Layered machines are today's module boundaries: write each layer against an interface (the "manual") and test it with a fake of the layer below. If a layer's correctness argument mentions another layer's internals, the cut is misplaced.
- Program family thinking is dependency injection and strategy objects done for a reason: keep two implementations of the bottom pearl (in-memory vs persistent store, verbose vs compact encoder) behind one interface, chosen at composition time.
- Track each concept's range of validity: the number of modules that know a representation measures your coupling. Push representation knowledge as low as it will go, and resist "define the schema first" when the upper layers can still be written against an abstract value.
- Mark derived state explicitly: name caches and counters as such, document the invariant they maintain (`fun == FUN(arg)` whenever `fun_up_to_date`), and centralize their updates next to the mutations they mirror. Assert the invariant in tests.
- When an `if` guard is falsified by its own body, consider writing the loop instead: `while remaining: pad()` states its own postcondition, whereas the `if` version needs an external proof that once suffices.
- For backtracking, implement the superset-and-filter derivation directly: a recursive `extend(partial)` that iterates candidates, tests feasibility via incrementally maintained sets (used columns, used diagonals), recurses, and undoes. Choose the iteration order deliberately so output order is specified, not accidental.
- Choose loop grain by the natural unit of the problem (word, record, solution), not the unit of the I/O primitive. If the stop criterion is tortuous, the grain is probably wrong.

## Pitfalls

- Deciding the data representation (or "the interface between the two halves") too early: every later component must then be explained in representation terms, the coupling thickens, and the program gets measurably messier.
- Letting derived state pass as primary state: when the cached value and its source can drift, no invariant documents which is authoritative, and the abstract algorithm disappears into its own optimization.
- Demanding representation-level guarantees (no side effects, totality, uniqueness of representation) before a representation exists: legitimate concerns raised at the wrong moment stall the design. A primitive does what its manual says.
- Building the search over a superset B chosen by naively dropping one condition: B explodes and the filter drowns. B must preserve the incremental, extension-friendly structure of A.
- Ignoring the question of output order in an enumerator: without a chosen order, no clean proof shows that every solution appears exactly once, and stop criteria become tortuous.
- Flat one-loop program structure where the problem has natural nesting: redundant tests, off-by-one buffers for a trial element that is never used, and stop conditions that need "knowing the algorithm" to justify.

## Cross-refs

- [[s13-notes-on-structured-programming-i]] for the first half: correctness concerns, enumeration/induction/abstraction, and the prime-table example that this unit's derived-variable and refinement arguments build on.
- [[s15-notes-on-data-structuring-i]] for Hoare's systematic treatment of the data-structuring side that this unit opens (the type "image" and "line" decisions), beginning right where this unit ends.
- [[s17-hierarchical-program-structures]] for the language-level embodiment of layered machines and pearls as classes and hierarchies.
- [[d01-executional-abstraction-and-languages]] for the later, sharpened form of the machine-and-abstraction model this unit sketches.
