---
unit: "Book S, Part I, Sections 1-11"
slug: "s13-notes-on-structured-programming-i"
title: "Notes on Structured Programming, first half"
book: "Structured Programming"
one_liner: "Why testing cannot establish correctness, which three mental tools (enumeration, induction, abstraction) can, and how stepwise refinement builds a program one decision at a time."
when_to_use: "Load when deciding how to convince yourself a program is correct, when structuring control flow for provability, or when starting a design top-down by refining abstract actions."
topics: [testing limits, correctness proofs, enumeration, mathematical induction, abstraction, loop invariants, structured control flow, stepwise refinement, program families, comparing programs, caching, incremental computation]
key_terms: [enumerative reasoning, Linear Search Theorem, invariance theorem, concatenation, selection, repetition, textual index, dynamic index, stepwise refinement, program family, common ancestor]
related: [s14-notes-on-structured-programming-ii, d03-wp-semantics-of-the-language, d04-termination-and-euclid, d01-executional-abstraction-and-languages, s17-hierarchical-program-structures]
---

# Notes on Structured Programming, first half

Dijkstra's argument that program structure, not testing, is the only route to justified confidence, plus the mental toolkit and the first full stepwise-refinement case study. **Source:** Structured Programming, Part I ("Notes on Structured Programming"), Sections 1-11.

## TLDR

- Differences in scale are differences in kind. Anything a hundred times larger is incomparable to the small case, so techniques that work on toy programs do not automatically scale. Size must be managed explicitly.
- Exhaustive testing is physically impossible (testing one 27-bit multiplier would take over 10,000 years), so "program testing can be used to show the presence of bugs, but never to show their absence."
- Confidence must come from the structure of the mechanism, not from black-box sampling. The programmer's job is to produce a correct program and a convincing demonstration of its correctness, which forces the program to be usefully structured.
- Three mental aids carry all understanding: enumeration (case analysis of straight-line and conditional code), mathematical induction (the only tool that handles loops and recursion), and abstraction (the main technique for limiting how much enumeration is needed).
- Restrict sequencing to concatenation, selection, and repetition (no free jumps), so that progress through the computation maps straightforwardly onto progress through the text and each construct has a known proof pattern.
- Correctness proofs rest on stated properties of the primitives, not on a perfect world. State axiomatically what arithmetic (or any operation) must satisfy, and demand no more.
- Stepwise refinement composes a program in minute steps, deciding as little as possible each time. Early levels stay valid whatever the later decisions, which also makes the program adaptable (a "program family" with a common ancestor).
- Caching a function of the state as a variable (maintaining fun = FUN(arg) invariantly, updating it incrementally) is the standard, provable way to trade storage for speed.

## When to reach for this

- You are tempted to claim code is correct "because the tests pass" and need the sharper standard: what argument, from structure, shows it cannot fail.
- You are writing or reviewing a loop and need the proof pattern: invariant preserved by the body, plus a reason it terminates.
- You are starting a design and want to proceed top-down, postponing data-structure and layout decisions until the structure demands them.
- You must choose between two control-flow shapes (loop inside branch vs branch inside loop, early exit vs full scan) and want to treat that as a real design decision.
- You are adding a cached or derived variable for performance and want to keep it provably in sync.

## Key concepts

### Scale, and our inability to do much

We reason by induction that what we can do once we can do a thousand times, but a factor of a thousand is beyond imagination (a crawling child vs a supersonic jet). Small computations are already beyond unaided checking, and clarity itself has quantitative aspects: a theorem with ten pages of preconditions is useless because the conditions must be verified at every use. The programmer has a small head and must respect that limit rather than ignore it, because ignoring it is punished by failure.

### Testing versus structure

For a multiplier of two 27-bit integers there are 2^54 cases. At tens of microseconds each, trying them all takes more than 10,000 years. So the device will perform practically none of its possible multiplications in its lifetime, yet we require them all to be correct, precisely because we reason about "the product" abstracted from specific operands and do not know in advance which cases will occur. Sampling a negligible fraction can miss whole classes of critical cases. The only way out is to stop treating the mechanism as a black box and take its structure into account. The same holds for programs. Also, if each of N components is correct with probability p, the whole is correct with probability about p^N, so for large N the component confidence must be nearly 1. Corollary, quoted exactly: "Program testing can be used to show the presence of bugs, but never to show their absence!"

Correctness is not the only goal. Programming is "the art of organising complexity", and optimization is affordable only while the program stays manageable.

### The three mental aids

**Enumeration** verifies a property by following an enumerated sequence of statements, splitting on conditionals. Example: assuming 0 <= r < dd, the body `dd := dd/2; if dd <= r then r := r - dd` preserves 0 <= r < dd, proved by two cases on the guard. Enumeration is fine but does not go far, because we are slow-witted. Use it only in small doses.

**Mathematical induction** is the only pattern of reasoning that copes with loops and recursion. The worked example proves the Linear Search Theorem (below) by induction on the number of iterations, then proves termination at exactly the first index satisfying the property. Dijkstra's morals: an "obviously correct" loop is an unconscious appeal to a theorem the programmer once convinced himself of, naming such theorems lets us appeal to them consciously, and the sheer length of the honest proof is an urgent advice to keep structures simple and avoid clever constructions "like the plague".

**Abstraction** is what remains of computations when specific values are removed. A variable is an abstraction from its current value, and repetition is what forces the variable concept. Naming an operation by what it does while disregarding how it works is the same move as using a theorem without rereading its proof. Abstraction is the main technique for reducing the demands made on enumerative reasoning.

### Proofs versus implementations

A proof assuming perfect arithmetic is valid only for perfect arithmetic. The fix is not to abandon proof but to state, axiomatically, the properties the operations must satisfy (for the remainder example, exact integer arithmetic on [0, 2a]). The programmer should demand as little as possible, the implementation should supply as much as reasonable. Cautionary tale: an ALGOL 60 implementation made floating `=` true for nearly-equal values, which destroyed transitivity (a = b and b = c no longer gave a = c) and made the operation useless. You can only use a tool by virtue of stated properties.

### Understanding programs: structured control flow

A program is a static, timeless text, but it only makes sense via the dynamic computations it evokes. The goal is to shorten the conceptual gap between text spread out in space and computation evolving in time. Three decompositions suffice: concatenation (S1; S2; ...; Sn), selection (if-then-else, case), and repetition (while-do, repeat-until). Each flowchart has a single entry and single exit, so from outside it reads as one action whose net effect alone matters. Concatenation and selection are understood by enumeration, repetition by induction, so for every construct we know the appropriate proof pattern.

Progress of a computation needs coordinates independent of the program's variables (values cannot serve, since an infinite loop revisits the same state at different points of progress). With only the three constructs, progress is fully described by a textual index plus a stack of dynamic indices for nested repetitions (and a stack of textual indices once procedures enter). With free jumps this variable-independent coordinate system is lost. That is the argument against goto: restrict sequencing so that progress through the computation maps onto progress through the text.

Invariants and variable meanings ("number of lines printed on the current page") are valid only at specific points of progress, which is why this coordinate system matters.

### Comparing programs

Two programs are usefully comparable only when their paired computations parse into time-successions of actions that map onto each other. A loop inside a branch versus a branch inside a loop can be output-equivalent yet incomparable, so the choice between them is a real design decision. The array-equality example makes it sharper: the full-scan version and the early-exit version both maintain equal = EQUAL(j), but they are not refinements of one common abstract loop, because an "abstract program" that leaves its own sequencing undefined is misleading. Abstract over how a step works, not over which steps occur.

### Stepwise composition (the prime-table example)

Task: print a table of the first 1000 primes. The method: compose in minute steps, deciding as little as possible each time. Description 0 is one action. Description 1 splits it into "fill table p" then "print table p", committing to almost nothing (not even what "prime" means, nor the layout). Each aspect of the problem lands in its own refinement, divide and rule.

The data structure for table p can be postponed (refine the actions against assumed operations, choose the structure to fit) or decided now (then the two actions refine independently). Both are tricky, because structure and computations must be well-matched. The efficient programmer takes the easiest decision first, the one needing minimum investigation for maximum hope of no regret. An interface is a presupposed generalization: "print table p" is conceived as printing any thousand integers, a class of actions, not one action.

The refinement of "fill table p" proceeds level by level (fill in order of increasing index, advance j to the next prime, test only odd candidates, test only prime divisors up to the first prime whose square exceeds j). Two lessons stand out. First, improving a decision at a lower level (odd candidates only) forced revision of the level above, an oscillation between levels that is really a cheap experiment to find where the interface sits best. Second, Knuth caught Dijkstra silently using a deep theorem (p(n+1) < p(n)^2 guarantees the needed prime is already in the table): every appeal to domain knowledge in a refinement must be made explicit. Introducing the derived variables ord, square, and mult, each only at the level where it means something, turns the program into nearly a Sieve of Eratosthenes. The encouraging result: much coding done early stays valid regardless of how the still-open decisions go.

### Program families

A program is best regarded not as an isolated object but as a member of a family of related programs (alternatives for the same task, or programs for similar tasks). Large programs will be modified, and editing text is the wrong model. Two versions should be children of a common ancestor, the partly refined abstract program embodying what they share, so they share correctness proofs and code, and the affected region is already isolated. "The decision to be changed" and "the decision still left open" are the same thing seen from different moments. Anticipating feasible generalizations guides structure, and the two demands (provability and adaptability) go hand in hand.

### Trading storage for speed

To avoid recomputing FUN(arg), introduce a variable fun and maintain the invariant fun = FUN(arg) at every assignment to arg (or add a boolean "fun up to date" for lazy recomputation). The technique matters most when the delta is cheap to compute even though FUN from scratch is expensive, as with ord in the prime program, which only ever increases because j only increases. Such redundant variables should be clearly recognized as such, as optimizing refinements of a more abstract program, even when the optimization is essential for realistic performance. (This section continues into the next unit.)

## The formal apparatus

- Linear Search Theorem. For the sequence d(0) = D, d(i) = f(d(i-1)), the program `d := D; while not prop(d) do d := f(d)` terminates with d = d(k), where k is the smallest index with prop(d(k)), provided such k exists. After the nth iteration, d = d(n) and not prop(d(i)) for all i < n.
- Invariance theorem for loops. In `while B do S`, if truth of (P and B) before S implies truth of P after S, and P holds on entry, then P holds on exit (and B is false there). This usually spares an explicit induction.
- Semantics of repetition: `while B do S` is equivalent to `if B then begin S; while B do S end`, so not B is the necessary and sufficient termination condition.
- Component reliability: with N components each correct with probability p, whole-program correctness is about p^N.
- Cached-function invariant: maintain fun = FUN(arg) by pairing every `arg := ...` with an update of fun, incrementally when possible.

## Derivation playbook

The remainder example (Section 5) is the template for proving an existing loop pair:

1. State what the primitives must satisfy (exact integer arithmetic on the needed range).
2. First loop `while dd <= r do dd := 2*dd`: apply the Linear Search Theorem to the sequence dd(i) = d * 2^i to get termination with 0 <= r < dd and dd = 0 mod d.
3. Second loop `while dd != d do begin dd := dd/2; if dd <= r then r := r - dd end`: show the body preserves 0 <= r < dd (enumeration) and a = r mod d (r is only ever reduced by dd, a multiple of d). Linear Search on dd(i) = dd(i-1)/2 gives termination with dd = d.
4. Conjoin invariants with the exit condition: 0 <= r < d and a = r mod d, so r is the remainder. Extending with q and the invariant a = q*dd + r yields the quotient.
5. Exercise in the same style: fast exponentiation via the invariant x > 0 and y >= 0 and A^B = z * x^y.

The prime-table example is the template for building a program: refine one named action at a time, decide data representation only when forced, introduce each derived variable (ord, square, mult) at the lowest level where it has meaning, and accept oscillation between adjacent levels as cheap interface exploration.

## Applying it in modern code

- Treat tests as bug detectors, not correctness certificates. For each nontrivial loop, write down the invariant and the termination argument in a comment or assertion, that is the correctness demonstration.
- Keep the p^N argument in mind: in a system of many modules, per-module confidence must be near certainty, which argues for small, provable units over broad integration testing.
- The structured-control argument is why early returns, break, and exceptions deserve the same scrutiny goto got: they are fine exactly when the single-entry single-exit reading (net effect from outside) survives.
- When choosing between full-scan and early-exit loops (any(), find(), short-circuit folds), recognize them as incomparable programs with different proofs, and pick deliberately.
- Practice refinement in code review: does each function read as a description at one level, expressed in named actions whose net effect is stated, with detail pushed down?
- Cached fields, memoization, and materialized views are the fun = FUN(arg) pattern. Pair every mutation of the source with the update, or an explicit dirty flag, and assert the invariant.
- Design interfaces as classes of actions: name the generalization you are presupposing ("print any 1000 integers"), not just the single call site in front of you.
- Structure for the family: keep decisions likely to change isolated in the lowest refinement level that needs them, so a variant shares the ancestor's code and proof.

## Pitfalls

- Trusting a test suite as evidence of absence of bugs. Sampling misses whole classes of critical inputs by construction.
- Proving correctness against idealized primitives (perfect arithmetic, transitive float equality, exact time) without stating the properties actually relied on.
- Abstracting over sequencing: writing one "abstract loop" and pretending two differently sequenced programs are its refinements. Only net effects of whole single-entry single-exit blocks may be abstracted.
- Assigning a meaning to a variable without noting where in the progress of the computation it is valid, invariants are momentarily false mid-update.
- Deciding data representation too early (subcomputations become awkward) or clinging to a postponed decision too long (assumed operations turn out prohibitively clumsy). Expect and budget for oscillation between levels.
- Making a program "general" on ill-considered grounds, generalization should guide structure, not bloat the product into inefficiency.

## Cross-refs

- [[s14-notes-on-structured-programming-ii]] continues Part I: the storage-for-speed section concludes there, followed by layered program construction.
- [[d03-wp-semantics-of-the-language]] replaces these informal proof patterns with the predicate-transformer calculus.
- [[d04-termination-and-euclid]] formalizes the termination arguments sketched here via variant functions.
- [[d01-executional-abstraction-and-languages]] develops the algorithm-as-abstraction-from-computations theme from the wp book's side.
- [[s17-hierarchical-program-structures]] builds the refinement-levels idea into full hierarchical structuring with classes.
