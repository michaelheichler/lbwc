---
unit: "Book S Part II, Sections 1-6"
slug: "s15-notes-on-data-structuring-i"
title: "Notes on Data Structuring I: Types, Products, Unions, Arrays"
book: "Structured Programming"
one_liner: "Hoare's theory of data types: abstraction stages in program design, what a type is, enumerations and subranges, Cartesian products, discriminated unions, and arrays as finite mappings, each with its operations and representation trade-offs."
when_to_use: "Load when designing the data model of a program, choosing between records, tagged unions, enums, or arrays, or deciding how abstract types map to concrete memory representations."
topics: [data structuring, types, abstraction, enumeration, subrange, cartesian product, record, discriminated union, tagged union, array, finite mapping, representation, packing, cardinality]
key_terms: [type, cardinality, base type, constituent type, constructor, selector, transfer function, selective updating, enumeration, subrange, cartesian product, discriminated union, tag field, finite mapping, minimal representation, packed representation, indirect representation]
related: [s16-notes-on-data-structuring-ii, s13-notes-on-structured-programming-i, d07-array-variables, s17-hierarchical-program-structures]
---

# Notes on Data Structuring I: Types, Products, Unions, Arrays

Hoare grounds program design in the mathematician's process of abstraction and builds a small algebra of data types (enumerations, products, unions, arrays), each defined by its values, its operations, and its menu of computer representations. **Source:** Structured Programming, Part II "Notes on Data Structuring" (Hoare), Sections 1-6.

## TLDR

- Program design is abstraction in four stages: abstract from the real world, choose a representation, axiomatise the assumptions, then manipulate. Coding comes last, after the design is (almost) certain to be right.
- A type determines the class of values a variable can take, every value belongs to exactly one type, and the type of any expression is deducible from the text alone, without running the program. This is what lets a compiler reject meaningless programs before execution.
- Types have a cardinality (number of values). For structured types built from finite constituents, cardinality follows simple formulas: product of cardinalities for Cartesian products, sum for discriminated unions, range-cardinality raised to domain-cardinality for arrays.
- Define your own unstructured types (enumerations, subranges) instead of encoding choices as bare integers. This documents intent, enables compile-time checking, and frees the representation choice.
- A Cartesian product (record) comprises every combination of its component values. Its operations are construction, selection, selective updating, and (optionally) lexicographic ordering.
- A discriminated union carries a tag saying which alternative a value came from. Accessing it as the wrong alternative is a serious error, and the case-discriminating `with` notation makes that error impossible by text inspection alone.
- An array is a finite mapping from a domain type to a range type, defined by explicit listing rather than computation. Subscripting is selection, `a[d] := r` is selective updating, and abstractly it assigns a new value to the whole array.
- Representation (unpacked, packed, tight packed, minimal, indirect, tree) is a separate, later decision, driven by the relative frequency of the operations the program actually performs.

## When to reach for this

- Designing the core data model of a program: which things are enums, which are records, which are tagged unions, which are maps or arrays.
- Tempted to encode a small set of alternatives as magic integers or booleans, or to reuse one field for two meanings.
- Handling a value that can be one of several shapes (sum type, variant, polymorphic case) and deciding how to keep access safe.
- Choosing a memory or storage layout: packing, bitfields, struct-of-arrays, pointers versus inline values, serialisation between main and backing store.
- Reviewing code where invalid states are representable and runtime checks substitute for type structure.

## Key concepts

### Abstraction, representation, axiomatisation, manipulation

Hoare's model, illustrated by the history of numbers: the concept (the number four) is an abstraction, numerals (IV, 4, binary) are representations, Peano's axioms are the axiomatisation, and addition rules are manipulation. Different representations suit different manipulators: Roman numerals are easy for small sums, binary is best for the machine. The same four stages structure program design. A program succeeds when (1) the axiomatisation correctly describes the relevant real world, (2) it correctly describes the program's behaviour, and (3) the representation makes the running cost acceptable. Keeping the stages separate, and postponing coding to the last step, is the whole point: coding and testing are the most expensive phase, so nothing should be left to go wrong there. In practice the progression loops back (intuition about feasibility guides earlier stages), but the orderly starting point still pays.

### Notation is a design language, not a programming language

The notations here are for defining, designing, and documenting programs, not for automatic compilation. Some operations (like sequence concatenation) are grotesquely inefficient on large data, and it is the programmer's job to eliminate them while moving from abstract to concrete program, a transformation no compiler can do. Making them compilable would tempt programmers to skip that obligation, and would train them to avoid expressive operations even in abstract designs. The abstract program is a framework, the concrete program a refinement of it, and the coding language should be close enough to the machine that cost is predictable from the source text.

### What a type is

Common to mathematics (typed variables in proofs), logic (Russell's theory of types blocking the set-of-all-sets paradox), and programming: a type constrains what a symbol can mean, and violations are detectable by scanning the text, with no knowledge of runtime values. Salient properties: a type determines the class of values of a variable or expression, every value belongs to exactly one type, the type of any constant, variable, or expression is deducible from form or context, each operator has fixed operand and result types (an overloaded symbol like `+` is resolved at compile time), the properties of a type's values and operations are fixed by axioms, and type information serves double duty: preventing meaningless constructions and determining representation. Cardinality can be finite or denumerably infinite, never more, because every value must be constructible in finitely many operations and storable in finite space. Arbitrary reals and functions on infinite domains can be represented only by program structures, not by stored data.

### Operations common to all types

Assignment (conceptually a complete copy) and test of equality (conceptually a complete scan of both values). Transfer functions map between types: constructors build a structured value from components, selectors extract components, and the type name conventionally serves as the constructor's name. Large structures are updated by selective updating (assigning to a selected component), and abstractly this changes the value of the whole variable. Some types are meaningfully ordered, many are not, and declaring a type unordered preserves freedom in later representation and sequencing choices.

### Enumerations and subranges

Where an integer stands for a choice among named alternatives rather than a quantity, declare an enumeration: `type suit = (club, diamond, heart, spade)`, optionally `ordered`. Subranges like `type year = 1900..1969` restrict an existing type. Operations: equality, assignment, case discrimination over the values (each value covered exactly once, `else` for the rest), order tests plus `succ`, `pred`, `T.min`, `T.max` for ordered types, and a `for` loop whose counting variable is local to the loop, immutable inside it, and scans an unordered type in an order deliberately left open. Standard representation maps values in order onto integers 0 to n-1, case discrimination compiles to an indexed switch-jump.

### Cartesian products

`type date = (day: day of month; m: month; y: year)` comprises every combination of component values, including combinations that never occur in reality (date (31, Feb, 1931) is a legal value). The type mechanism is deliberately weaker than full set comprehension, so the programmer documents the meaningful-value invariant and keeps manipulation within it. Cardinality is the product of component cardinalities (4 suits x 13 ranks = 52 cardfaces). Operations: construction (`date (7, March, 1908)`), dot selection (`n.imagpart`), selective updating of a component, lexicographic ordering when declared ordered (earlier components more significant), and the `with sv do S` construction that opens a structure so components are named directly, clarifying the code and enabling the address to be held in a register.

### Discriminated unions

`type pokercard = (normal: (s: suit; r: rank), wild: (joker1, joker2))`. A union's values are wholly distinct from the constituent types' values, and every value carries a tag recording which alternative it came from, even when two alternatives are the same type. Cardinality is the sum of constituent cardinalities. Common components can be factored out in front of the alternatives (every car has make and regnumber, only local cars have an owner). Converting a value back to an alternative it did not come from is a serious error, catchable at runtime only by checking the tag. The discriminating `with sv do {alt1: S1, ..., altn: Sn}` executes the limb matching the tag, and inside each limb the alternative's selectors are guaranteed safe by text inspection alone. Hoare's verdict on the common practice of omitting the tag and "knowing" the interpretation: errors then surface as bitpattern-dependent, unpredictable results, so tagged, checkable discrimination should be the standard, bypassed only in exceptional circumstances.

### Arrays as finite mappings

An array is a mapping `M: D -> R`, written `array D of R`, specified by explicitly listing M(x) for each x in the finite domain rather than by a computation rule. The domain need not be integers: `array month of 28..31`, `array spot of character` where spot is a product of row and column. A multidimensional array can equally be an array of rows, the better abstraction when rows are processed separately. Cardinality is cardinality(R) raised to cardinality(D). Operations: the constant-array constructor, the update `T(x, d: r)` (same as x except at d), subscripting as selection, `a[d] := r` as selective updating, optional lexicographic ordering for character arrays, the `for i: D take E` expression building an array from a formula, and elementwise lifting of range-type operations (A + B), expensive on large arrays and to be eliminated in the concrete program.

### Representation menu and how to choose

Standard direct representations give each variable space for any value of its type. The options, for all the types above: unpacked (each component a whole word, fastest selection and update), loose packed (components on natural machine boundaries such as characters), tight packed (bitpatterns juxtaposed), minimal (values as integers 0 to N-1, dense but costly to access, useful mainly for index domains), and indirect (variable holds a pointer, necessary for infinite-cardinality types, profitable for shared values, but shared copies must never be selectively updated, and pointers bring storage allocation and backing-store problems). Unions add a tag field (a word unpacked, a few bits packed) and pad shorter alternatives to a fixed size. Multidimensional arrays choose between contiguous layout with a computed (minimal-representation) subscript and the tree (codeword/descriptor) representation, an array of row addresses, better with slow multiplication, variable-length rows, shared rows, rows swapped to backing store, or fragmented free storage. The rule throughout: pick by the relative frequency of the operations, unpacked when selection and update dominate, packed when copying, comparison, and store transfers dominate or space is scarce.

## Applying it in modern code

- The four-stage progression is domain modelling: get the domain assumptions and the abstract algorithm right before committing to schemas, layouts, and code, because representation errors found in production are the costliest to fix.
- Enumerations and subranges are enum types and refined/newtype wrappers. Give each set of markers its own type instead of int or string, and let the compiler enforce exhaustive case coverage (Hoare's each-value-exactly-once rule is your switch-exhaustiveness lint).
- Cartesian products are structs, records, dataclasses. Cardinality thinking is the "make illegal states unrepresentable" heuristic: compare the type's cardinality with the number of meaningful states, and document the invariant that covers the gap.
- Discriminated unions are sum types, sealed class hierarchies, Rust enums, tagged variants. Hoare's discriminating `with` is pattern matching, and his warning against untagged unions applies directly to type-punned C unions, stringly-typed JSON, and "kind" fields checked by convention.
- Arrays as finite mappings cover both arrays and dictionaries or lookup tables: any map with a finite key type. `T(x, d: r)` is the functional update of persistent data structures, and `a[d] := r` its in-place optimisation.
- The representation menu survives as struct packing, bitfields, bitsets, interning and shared immutable values, and array-of-pointers versus contiguous layouts. Choose by measured operation mix, and never selectively update a shared representation.
- Keep the abstract program as the framework: write it first with expensive-but-clear operations, then refine data representation while preserving the algorithm, as two separately checkable steps.

## Pitfalls

- Coding first and modelling later: representation decisions made when the data and processing are least understood are the classic serious errors, discovered just before or after going live, when they are hardest to rectify.
- Bare integers standing for choices: no compile-time protection, no documented interpretation, and accidental arithmetic on markers goes undetected.
- Untagged unions or convention-checked variants: misinterpretation produces bitpattern-dependent results that are meaningless at the abstraction level the programmer is working at, and no check can catch it.
- Forgetting that the product type contains invalid combinations (date (31, Feb, ...)): the type does not enforce the full real-world invariant, the programmer must, and should state it in the declaration's documentation.
- Selectively updating a shared (pointer-represented) value, silently changing every variable that points at it.
- Treating the design notation as an implementation: shipping the abstract program's expensive operations (whole-array arithmetic, naive set updates) unrefined on large data.

## Cross-refs

- [[s16-notes-on-data-structuring-ii]] continues the theory with powersets, sequences, sparse and recursive structures. This unit's overlap pages already show the powerset type (colour, liftcall, hand), its bitpattern representation, and the two-stage Eratosthenes sieve refinement, covered fully there.
- [[s13-notes-on-structured-programming-i]] gives Dijkstra's companion argument for stepwise refinement of programs, of which Hoare's abstract-to-concrete data refinement is the data-side twin.
- [[s17-hierarchical-program-structures]] builds class-based abstraction on top of these type-definition ideas.
- [[d07-array-variables]] treats arrays as functions in Dijkstra's formal semantics, the proof-oriented counterpart of the array-as-mapping view here.
