---
unit: "Book S Part III"
slug: "s17-hierarchical-program-structures"
title: "Hierarchical Program Structures"
book: "Structured Programming"
one_liner: "Dahl and Hoare show how SIMULA-style classes, objects, coroutines, subclassing, and prefix hierarchies let a program be decomposed into layered concepts that mirror the problem domain."
when_to_use: "Load when designing class or module hierarchies, choosing between objects and plain procedures, building generators/iterators or cooperating producer-consumer components, or layering a domain library on top of a lower-level one."
topics: [classes, objects, encapsulation, coroutines, semicoroutines, generators, inheritance, subclassing, list structures, binary search trees, discrete event simulation, concept hierarchies, program decomposition, abstraction layers]
key_terms: [class, object, attribute, object generator, reference variable, qualification, remote identification, detach, call, resume, coroutine, semicoroutine, concatenation, prefix class, subclass, prefix sequence, sequencing set, mental platform]
related: [s13-notes-on-structured-programming-i, s14-notes-on-structured-programming-ii, s15-notes-on-data-structuring-i, s16-notes-on-data-structuring-ii]
---

# Hierarchical Program Structures

How to decompose a program into a hierarchy of concepts, each realized as a class of objects, and how coroutines and class prefixing (inheritance) extend that idea to cooperating processes and layered libraries. **Source:** Structured Programming, Part III (Dahl and Hoare).

## TLDR

- A useful concept is a class of specialized instances. Model each concept as one self-contained piece of program (a class), so components can be written and revised independently and the project's inevitable iteration gets cheaper.
- ALGOL blocks already unify data plus operations, but stack discipline kills a block instance the moment it returns, so only algorithms can be modelled. Letting an instance outlive its call (at the cost of garbage collection) is what turns blocks into objects and makes data-with-operations a first-class concept.
- A class is a procedure whose activation records survive the call. `new C(...)` returns a reference to the object, attributes are its local variables and procedures, and `X.A` (remote identification) accesses them. Qualified references let almost all type checking happen at compile time, leaving only the nil-reference check for run time.
- Coroutines are peers, not master and subordinate. `resume(X)` transfers control symmetrically between objects, `detach` returns control to the generator or original caller, and `call(X)` re-attaches a detached object. A semicoroutine (detach/call) is a resumable subordinate, which is exactly a generator.
- Attributes referencing the same class give recursive data structures (trees, two-way lists) whose operations are recursive procedures matching the structure's shape.
- Concatenation (class prefixing, that is, inheritance) merges a prefix class's attributes and actions into a subclass. A prefix-class reference may point at any subclass object but reaches only prefix attributes. Assignments narrowing the qualification need a run-time check.
- A prefix sequence C1, C2, ..., Cn is a tower of conceptual levels. Each layer is a "mental platform" or application language (TWLIST for lists, MINISIM for simulation on top of it), and its value is proportional to its ruggedness, how well it tolerates or forestalls misuse.
- Invariants stated over a platform's data structures (for example, all TWLIST lists are circular with exactly one head) are what entitle clients to ignore the details below the platform.

## When to reach for this

- Deciding whether some functionality should be a stateless function or a class with state and methods, or whether one procedure with many parameters is hiding a missing object.
- Designing an iterator, generator, or lazy producer (permutations, tree traversal, token streams) that must suspend mid-computation and resume where it left off.
- Structuring a pipeline of components (parser passes, producer/consumer stages) where neither side is naturally the subroutine of the other.
- Layering a domain-specific library on top of a general one and asking what invariants the lower layer must guarantee so the upper layer can forget about it.
- Choosing where to put a supertype reference versus a subtype reference, and what downcasting will cost you.

## Key concepts

### Concepts, classes, and decomposition

System construction is iterative because the right concepts only become clear at later stages. The defense is decomposition: each concept covers a limited aspect of the system and corresponds to one program component that can be programmed and revised with few implications for the rest. Since any useful concept has generality, it is a class of specialized instances, and the natural program form for it is a class declaration describing the whole family with one text.

### From blocks to objects

The ALGOL 60 block already has the required properties: duality (it has data and performs actions), decomposability, a sharp distinction between text and dynamic instance (a block is the class of its potential activations), and status as a language element. The one fatal restriction is nested lifetimes: an instance dies when it returns, so the caller can never hold and interrogate it as an existing thing. That is why plain procedural languages overemphasize the operational side and can model only algorithms. SIMULA 67 lets an instance outlive its call, accepts garbage collection as the price, and gains the ability to express the relationship between data and the operations on it.

### Classes, references, and remote access

A class is declared like a procedure. Calling it with `new C(actuals)` creates an object and returns a reference. Local variables, local procedures, and formal parameters are the object's attributes. References are typed by qualification (`ref (C) X`), carry the neutral value `none`, and use dedicated operators for reference assignment and reference equality precisely to keep object identity distinct from object contents. `X.A` reads or invokes attribute A of the object X refers to, and is legal wherever an ordinary identifier is, except as a declaration. Qualification makes both assignment validity and attribute validity compile-time checkable, so the only remaining run-time error is a `none` dereference.

The histogram example makes the case against the procedural alternative: a free procedure `tabulate(X, n, T, N, y)` with five parameters artificially separates the operation from its data, and the awkwardness of its signature is direct evidence of a missed concept. As a class, histogram binds partitions, counts, total, and the tabulate and frequency operations into one instantiable unit, and a program can hold several histograms at once. The Gauss integration class shows objects doing expensive setup once in the class body (computing weights for n points) and then serving cheap repeated queries, making ALGOL's `own` variables superfluous.

### Coroutines and semicoroutines

Some pairs of programs are peers, and forcing one to be the other's subroutine is arbitrary (two game-playing programs pitted against each other, the two passes of a compiler fused into one run). A coroutine is a self-contained program whose input/output statements are replaced by transfers to the coroutines that produce or consume its data. The control operations are:

- `detach`: exit from the object back to its generator or original caller, leaving a resumption mark just after the detach.
- `call(X)`: re-attach detached object X as a subordinate, which must eventually detach again or terminate.
- `resume(X)`: symmetric transfer between peers, equivalent to a detach plus a call of X, bypassing the master and handing X the obligation to detach to the original caller eventually.

An object using only detach against a master's call is a semicoroutine: still subordinate, but resumable, which is the essence of a generator. A terminated object (one that ran off its end) can no longer be activated but survives as data whose attributes remain remotely accessible.

Worked examples: Conway's text transformation problem runs three coroutine passes (disassembler, squasher, assembler) connected by resume, each written as a clean infinite loop as if it owned the control flow. The permuter class is a semicoroutine generator whose recursive `permute(k)` procedure issues a detach deep inside the recursion, so the entire recursion state is frozen between calls, and each `call(P)` resumes it exactly where it stopped. The reasoning that derives permute is itself a small invariant argument: assume `permute(k-1)` leaves the array unchanged, show the kernel rotates elements right, and add a compensating left rotation.

### List structures and the recursive-class pattern

Attributes that reference the class being declared give recursive data structures. A binary search tree class holds `left`, `right`, `val`, plus `insert` and `find` procedures whose recursive bodies match the recursive data definition, using `this` to return a reference to the current node. A scanner class (a semicoroutine wrapping a recursive traversal with a detach at each node) yields the values in ascending order, and N scanners drive an N-way merge of a forest. The syntax analyser scales the pattern up: a backtracking top-down parser where each phrase object is simultaneously a node of the syntax tree under inspection and the frozen stack of its own recursive match activations, so calling a phrase again backtracks it to the next alternative parse.

### Concatenation: subclassing

`A class B ...` declares B with A as prefix. The effect is textual merging: parameters, declarations, and statements of A followed by those of B. A truck, bus, and car can share a vehicle prefix holding common attributes. A reference qualified by the prefix class may point to any subclass object but reaches only prefix attributes, while a subclass-qualified reference reaches everything but points only at subclass objects. Widening assignments are compile-time safe, narrowing ones may fail at run time. `inspect r when C do ...` tests subclass membership. Prefixing a block instead of a class imports the prefix class's inner declarations as a library for that block.

### Concept hierarchies and mental platforms

A programming project must bridge the conceptual distance between problem-oriented concepts and the machine-oriented base language. Bottom-up, one builds abstract concepts up from the language. Top-down, one writes the solution in terms of concepts not yet implemented. Either way the system is layers, each a conceptual level, expressible as a prefix sequence (class C1, then C1 class C2, and so on, with the program itself as a prefixed block on top). A well-formed level is an application language, and its usefulness tracks its ruggedness.

TWLIST is the model platform: classes linkage, link, and list jointly represent circular two-way lists with head, and operations `out`, `precede`, `into`, `first`, `last`, `empty`. Two invariants hold throughout any client block that never assigns suc or pred directly: every linkage object is either unlinked with both pointers `none`, or satisfies `x.suc.pred == x.pred.suc == x`, and every circular list contains exactly one head. Each operation preserves them, and misuse either fails to compile or dies immediately on a `none` dereference. That guarantee is what lets clients program in terms of ordered sets and ignore pointer surgery.

MINISIM, prefixed by TWLIST, adds discrete event simulation: a `process` class (subclass of link) with local `time`, a sequencing set SQS ordered by decreasing reactivation time whose last member is the active process, and operations `hold(T)`, `wait(Q)`, `activate(X)`, `simulate(start, finish)`. Processes are semicoroutines scheduled in pseudo-parallel, and simulated time is decoupled from computing time (time only moves when all processes are passive). Applications on top: the Lee shortest-path algorithm as pulses propagating through a road network under simulated time, and a job shop model whose machine group request/release pair is noted as the analogue of semaphore P and V. A Machine Group subclass overrides request to tabulate waiting times into a histogram, composing three levels of the hierarchy.

## Applying it in modern code

- The histogram test still works: a function whose parameter list keeps hauling the same cluster of data around is a missing class. Bind the data and its operations into one type.
- Semicoroutine generators are today's yield-based generators and iterators (Python generators, JS function*, Rust iterators). The permuter and tree scanner patterns map directly: suspend inside recursion, resume on next().
- Coroutine pipelines are async producer/consumer stages, channels, or streams. When neither side is naturally the caller, do not force a master/subordinate split, connect peers.
- Prefix classes are inheritance, and the qualification rules are exactly static typing of up and downcasts: upcasts free, downcasts checked (instanceof, pattern matching on the dynamic type, SIMULA's `inspect ... when`).
- Compile-time qualification checking with only a nil check left at run time is the argument for typed references over untyped pointers, and for making illegal states unrepresentable.
- Build platforms with stated invariants. A module like TWLIST earns the right to be ignored only if its exported operations provably preserve its invariants regardless of client behavior. Document the invariant, keep the representation private, and make misuse fail fast.
- Layer domain libraries as explicit levels (core structures, then scheduling or domain engine, then application), and judge each level by its ruggedness, not just its features.
- The one-object-per-class smell is real: when a class will only ever have one instance (the three parser passes), the full class/instance machinery is ceremonial overhead. The modern answer is a module, closure, or singleton object.

## Pitfalls

- Modelling only algorithms: exposing operations as free procedures with long parameter lists instead of objects that own their state. Signature complexity is the symptom.
- Forcing a subroutine hierarchy on peer components. The arbitrary choice of which pass calls which turns both into contorted state machines.
- Breaking a platform's invariants by reaching past its interface (assigning suc/pred directly). Every guarantee of the layer above evaporates.
- Relying on downcasts (narrowing reference assignments) as routine control flow: each one is a latent run-time error the compiler cannot rule out.
- Ignoring the storage consequence: objects that outlive their calls require garbage collection or an ownership discipline. Assuming stack lifetimes for escaping instances is a use-after-free.
- Bypassing a scheduling layer's own control operations (raw call/resume on MINISIM processes instead of hold/wait/activate) silently corrupts the timing mechanism. When a platform wraps a primitive, use the wrapper.

## Cross-refs

- [[s13-notes-on-structured-programming-i]] for Dijkstra's case for structuring programs so correctness can be reasoned about at all, which this chapter extends from control flow to concept hierarchies.
- [[s14-notes-on-structured-programming-ii]] for stepwise refinement and layered program composition, the top-down counterpart to bottom-up prefix sequences.
- [[s15-notes-on-data-structuring-i]] for Hoare's foundations of data types that classes and references build on.
- [[s16-notes-on-data-structuring-ii]] for recursive and sparse data structures, which the tree, list, and reference machinery here implements concretely.

## Gaps

The unit begins at page 177, mid-chapter, so sections 1 through 2.2 (the opening discussion of concept modelling before the matrix multiplication example) are only partially present, and two coroutine control-flow diagrams and the Fig. 1 syntax tree survive only as OCR fragments.
