---
unit: "Book S Part II, sections 8-12 (plus the tail of section 7)"
slug: "s16-notes-on-data-structuring-ii"
title: "Notes on Data Structuring, second half: sequences, recursion, sparsity, representation"
book: "Structured Programming"
one_liner: "Hoare's treatment of advanced (unbounded) data types, sequences, recursive types, sparse sets and mappings, how to pick a concrete representation from the operation mix, and axiom schemas that pin down each type constructor."
when_to_use: "Load when choosing between list, stack, queue, hash map, or tree representations, when designing recursive data types or serialization formats, or when a large sparse mapping needs an efficient concrete layout."
topics: [sequences, stacks, queues, deques, buffering, recursive data structures, trees, serialization, sparse arrays, hash tables, indexed sequential, representation choice, abstraction levels, axiomatization, timetabling]
key_terms: [sequence, concatenation, selective updating, contiguous representation, chained representation, blocked representation, cyclic buffer, double-buffering, recursive data structure, tree representation, bitstream representation, sparse powerset, sparse array, partial mapping, key and entry, tabular representation, hashing, indexed sequential, locally dense, grid representation, axiom schema]
related: [s15-notes-on-data-structuring-i, s13-notes-on-structured-programming-i, s17-hierarchical-program-structures, d07-array-variables]
---

# Notes on Data Structuring, second half: sequences, recursion, sparsity, representation

How to define unbounded data types abstractly and choose their machine representation from the operations actually performed. **Source:** Structured Programming (Dahl, Dijkstra, Hoare), Part II "Notes on Data Structuring" by C. A. R. Hoare, sections 8-12.

## TLDR

- Elementary types (products, unions, arrays, powersets over small bases) have finite cardinality and fixed storage. Advanced types (sequences, recursive types, sparse mappings) have unbounded cardinality, so they need dynamic allocation, pointers, and selective updating. Prefer elementary types whenever the problem allows.
- A sequence is one abstraction behind strings, files, streams, stacks, queues, and deques. The right representation is decided entirely by which update operations occur: read-only front (input), append-only (output), append plus remove-last (stack), append plus remove-first (queue), both ends (deque).
- Concatenation copies both operands and is expensive. Replace it with selective updating (append one item) wherever possible.
- Representations form a ladder: contiguous (fixed or bounded length), chained (links, free chain, optional garbage collection), blocked (chained blocks of 10-100 items, the practical default, near-mandatory for backing store), and paged (let virtual memory turn contiguous back into the easy answer).
- Data structuring mirrors program structuring: product ~ compound statement, union ~ case, array/powerset ~ bounded for loop, sequence ~ while loop, recursive type ~ recursive procedure. A recursive type mentions itself in its own definition, and recursion at only one end of a definition can be replaced by a sequence.
- Recursive values are trees, never cycles. Sharing of substructure is a space optimization only and must be invisible, so it is forbidden as soon as anyone selectively updates a shared part.
- A sparse set or mapping (huge or infinite domain, few significant entries) is represented by its significant entries plus a default value. Representations: sorted sequence of entries (batch processing), in-store table with sort or hash lookup, indexed sequential for backing store, submatrix tables for locally dense matrices, grid chains for cross-classification.
- Each type constructor comes with an axiom schema. The axioms state exactly what a program may rely on, leaving the implementor free to pick any representation that satisfies them, and they are the basis of correctness proofs.

## When to reach for this

- You must pick a concrete container (array, linked list, ring buffer, hash map, B-tree-ish index) and want the decision driven by the operation mix instead of habit.
- You are designing a recursive type (AST, tree, nested document) and must choose between an in-memory pointer form and a flat serialized form.
- A mapping has a huge key space with few significant entries (caches, symbol tables, sparse matrices, random access files) and the dense representation is impossible.
- You need to justify a two-stage design: an abstract program over abstract types first, then a representation-level refinement that provably implements it.
- You are writing down the contract of a data type and want axioms rather than an implementation to define it.

## Key concepts

### Why advanced structures are a different world

For elementary types the value count is finite, storage is fixed by the declaration, and all reasonable representations perform about the same. Advanced types break all of that: storage is only known at run time and varies, large values force selective updating of components instead of whole-value assignment, dynamic allocation brings pointers and either explicit release or garbage collection, and the efficiency of each primitive operation now depends critically on the representation, so you must know the relative frequency of operations before choosing one. Hoare's advice: stay elementary unless the application forces you out.

### The sequence and its five usage disciplines

A sequence is an arbitrary-length ordered collection of items of one type. Notation: empty T(), unit T(v), literal [v1, ..., vn]. Operations: concatenation, x.first and x.last, initial(x) and final(x) (drop last or first), begins and ends tests (expensive, avoid), length, lexicographic ordering, append (write), "v from x" (read and remove first), "v back from x" (pop last), and "for v in x do S" for scanning. The classification that decides representation:

1. Input sequence: only reads. Opened from an outer file at declaration, closed at block exit.
2. Output sequence: only appends. Its final value is handed to an outer variable (an output file).
3. Stack: append and pop from the same end. Starts empty.
4. Queue: append at one end, read at the other. Starts empty.
5. Deque: all four operations. Costly to make uniformly fast, and most programs can avoid needing one.

### The representation ladder

Contiguous: one fixed area, right when length is constant, known at block entry, or safely bounded (accepting termination on overflow). A stack needs one pointer, a queue wraps around as a cyclic buffer (also the classic bounded producer-consumer channel between parallel processes). Two stacks can grow toward each other from opposite ends of free store. Many contiguous sequences can share a region with reshuffling on collision, workable only if reshuffles are rare.

Chained: items linked by pointers, with free areas kept on a free chain. Links must point in the reading direction. Chained stacks can share tails, but then popped cells cannot be freed eagerly, which leads to scan-mark-collect garbage collection. Hoare warns that garbage collection looks like relief from responsibility but that in serious applications the responsibility cannot be evaded so lightly. Deques need two pointers per item, compressible to their difference (the XOR-style trick).

Blocked: chain fixed-size blocks holding tens of items each. This slashes link overhead and per-item allocation cost, sidesteps variable-length allocation, and is almost obligatory once backing store is involved because tiny transfers are ruinous. Block sizing is a compromise: at least ten typical items per block, and at least ten blocks per typical sequence, with 128 to 1024 words a common answer and a factor of two rarely mattering.

Backing store and paging: keep the active end in main store, use double buffering to overlap transfer with compute, and do not stack extra buffers against a raw speed mismatch, they cannot help. Under automatic paging, just declare the maximum contiguously and let the pager allocate lazily and migrate cold blocks. The one thing the pager cannot do is read ahead on input.

### Recursive data structures

Each data constructor corresponds to a control structure, and the recursive type corresponds to the recursive procedure: the type name appears inside its own definition (or mutually, in a preceding one). Standard examples: arithmetic expressions (sequence of terms, term as sequence of factors, primary as constant or variable or bracketed expression), family trees (head person plus offspring, a sequence of families), and LISP binary lists (atom or cons of two lists). The abstract type captures structure while deliberately omitting concrete syntax choices such as bracket symbols or infix versus prefix. When recursion occurs only once, at the start or end of a definition, replace it with a sequence, exactly as a tail-recursive procedure becomes a while loop.

Representation: components of the recursive type become pointers because their size is unbounded (the tree representation). The alternative is the linear bitstream: lay the substructures out contiguously, recover the bracketing from tags and context, often with packing, and gain roughly a factor of ten in compactness at the price of serial access. Choose tree form for active processing by recursive procedures, bitstream for output and re-input, since linearizing also kills the ugly problem of pointers on backing store. Multipass translators routinely convert between the two at each phase boundary. Sharing common branches saves space but has no semantic effect, so it must be avoided if any owner selectively updates the shared part. Pointers back into an owning structure are impossible in this discipline: a value cannot be its own component, only an infinite structure could be, and infinite structures break the induction principle that proofs over recursive data rest on. The worked example is a recursive descent parser (compile expression, compile term, compile primary), where each function consumes the longest prefix in its category and the program's shape follows the shape of the result type.

### Sparse data structures

When a powerset base or array domain is huge or infinite, dense representation is impossible, but if every actual value has only finitely many members, or only finitely many elements differ from a default, the type is sparse and each value is finitely listable. Examples: sets of car numbers, a random access file keyed by owner name (infinite domain), sparse vectors and matrices, a compiler dictionary mapping identifiers to declaration info, and cross-classified customer files. A partial mapping is the variant defined on only a subset of the domain, with constant omega (undefined everywhere) and the function domain(x) yielding the defined subscripts, and it needs no recorded default.

A sparse mapping is a collection of entries, each a key plus its information (a sparse set stores keys only). Representations, chosen by access pattern:

- Sequential: a default plus a sequence of entries, usually sorted by key. Random access is slow, so batch the accesses into key order and merge sorted updates. Classic magnetic tape file processing is exactly this abstraction implemented on an unsympathetic medium.
- Tabular: with an acceptable bound N on entry count, keep an in-store table. Sort once then binary search if all entries arrive before use. If insertion interleaves with lookup, hash the key into 0..N, and on collision probe onward, better with a second hash as step length and N+1 prime to avoid clustering.
- Indexed sequential: when the table exceeds main store, a sorted top table maps key ranges to sequences (like encyclopedia volume spines), balanced periodically, aligned to cylinders and tracks so a random access costs about one head movement, with second-level index tables if needed.
- Locally dense: a sparse matrix whose significance clusters in submatrices. Fix a standard submatrix size (say 16x16), keep a pointer table with null for all-zero blocks, and address by interleaving the bits of the two subscripts so the high bits select the block and the low bits the element. This is equally efficient by rows and by columns, which recommends it for any large array on a paged machine. Hoare credits the interleaving method to Dijkstra.
- Grid: for two-way cross-classification, border chains for each used key of either dimension, with every entry on two linked lists, one per dimension. Main-store only unless blocked.

### The timetable example: abstract program before representation

The examination timetable problem shows the whole method end to end. First formalize the data (load: array student of powerset exam, timetable: powerset session) and the six correctness conditions, noting that minimality is deliberately left informal because an absolute minimum may be too expensive. The conditions split into whole-timetable conditions (partitioning: exhaustive and exclusive) and per-session conditions (at most k exams, hall capacity, no student clash). That split dictates the program shape: an outer loop that keeps exclusiveness as its invariant and works toward exhaustiveness as its termination condition, and an inner function "suitable" that builds one valid session. The inner search generates supersets of a trial session recursively, prunes using the fact that a failed trial cannot be rescued by growing it, removes incompatible exams from the untried set eagerly, and keeps the best trial by session count. Only after the abstract program is reviewed for feasibility (search time is the real risk, mitigated by ordering exams by incompatibility set size) does representation start, and each variable is decided by its operations and estimated sizes: sessions as small arrays used as stacks with a cached count, the timetable inverted into array exam of session numbers (valid only because sessions are exclusive), the hot bitset variables (remaining, untried, incompat rows) as bit patterns because their density is around fifty percent and set operations dominate, and the voluminous load data as an external sequence read once, formatted for human punching. The two-stage design means the abstract version acts as the frame on which the intricate coded version is stretched, the same lesson as the prime sieve at the start of this unit, whose packed word-level version expresses the identical algorithm as the abstract set version.

### Axiomatization

Intuitive descriptions leave room for misunderstanding, so each type constructor gets an axiom schema, a pattern from which the axioms of any particular defined type follow. Axioms state what real world and representation share, frame the concepts, record the assumptions, constrain any valid representation while leaving the implementor circumscribed freedom, and ground correctness proofs. They are not for direct use in proofs of nontrivial programs. Rather they establish familiar properties which are then used informally. The schemas:

- Enumerations and subranges: Peano-style axioms (min, succ, "the only elements are" induction, injectivity of succ, order laws), plus mapping axioms tying a subrange to its base type.
- Cartesian products: constructor plus selector equations, with lexicographic order if ordered.
- Discriminated unions: distinct tagged constructors, and x.k is defined only for the current tag.
- Arrays: built from a constant array T(r) and single-point updates T(x, d:r). The key laws: a later update at the same subscript overwrites the earlier one, lookup returns the last write at that subscript, and equality is extensional (x = y iff all elements are equal).
- Powersets: finite sets over hierarchically ordered bases, which dodges the paradoxes of full set theory. Built from the empty set by union with unit sets, with membership, subset, intersection, difference, size, min, up and down shifts, ranges, and comprehension all axiomatized.
- Sequences: built from the empty sequence by appending unit sequences, with associativity of concatenation, first/last/initial/final laws, begins and ends, length, and lexicographic order.

## Applying it in modern code

- Choose containers by operation mix, exactly as section 8 prescribes: append-only log, stack, FIFO queue, or deque map directly to vector, vector-as-stack, ring buffer, and only reluctantly a doubly linked structure. If you cannot name which of the five disciplines your sequence follows, you are not ready to pick a type.
- Repeated string or list concatenation in a loop is the modern echo of Hoare's warning: it copies both operands. Use a builder, buffer, or append idiom (selective updating) instead.
- Blocked representation lives on in every B-tree, database page, unrolled linked list, and I/O buffer size. When designing anything that touches disk or network, batch small items into blocks and size them so per-block overhead and wasted slack both stay small.
- Tree versus bitstream is exactly in-memory object graph versus serialized form (JSON, protobuf, flat buffers). Process in tree form, ship and store in linear form, and expect a big compactness win from linearizing. Treat shared substructure as an optimization that becomes a bug the moment anything mutates through one alias.
- Sparse mapping representations map onto today's menu: sorted run files and log-structured merge for batch key order, hash maps for interleaved insert and lookup, indexed sequential for range-partitioned storage, block-pointer schemes for sparse matrices. Pick by whether accesses can be batched into key order.
- Design in two stages: write the abstract program over sets, sequences, and mappings first, verify its logic (invariant of the outer loop, pruning argument of the search), then refine each variable's representation from its operations and measured sizes. Keep the abstract version as the documented frame.
- Write down the algebraic laws of a new abstract type (the axiom schema idea) and turn them into property-based tests: update-then-lookup returns the written value, later updates shadow earlier ones at the same key, equality is extensional.
- Estimate sizes and frequencies before optimizing representation, as the timetable example does with its explicit assumptions (500 exams, 5000 students, density around fifty percent), and let those numbers, not fashion, pick dense versus sparse.

## Pitfalls

- Reaching for an advanced structure (dynamic, pointer-linked, sparse) when a bounded elementary one would do, importing allocation, aliasing, and representation problems for nothing.
- Choosing a representation before knowing the operation frequencies. For advanced types the primitives differ wildly in cost across representations, so the habit-based choice is often the slow one.
- Concatenating instead of appending, or using begins/ends style scans where a cheaper discipline would serve.
- Mutating shared substructure. Sharing is only sound while values behave as if fully disjoint, and update through one owner silently corrupts the other.
- Trusting garbage collection or extra I/O buffers to absorb a design problem: GC does not remove the responsibility for storage behavior, and buffering beyond double or triple cannot fix a throughput mismatch between processing and transfer.
- Greedy search without pruning or ordering: the timetable search is feasible only because failed trials are never extended, incompatible candidates are removed eagerly, and candidates are ordered to shrink the search fastest.

## Cross-refs

- [[s15-notes-on-data-structuring-i]] first half of the same monograph: the elementary type constructors (products, unions, arrays, powersets) whose axioms and representations this half extends, including the start of the prime sieve example finished here.
- [[s13-notes-on-structured-programming-i]] Dijkstra's stepwise refinement, the program-structuring twin of Hoare's two-stage data refinement.
- [[s17-hierarchical-program-structures]] the next monograph, which begins on this unit's last page and carries the type-plus-operations idea into classes and SIMULA 67.
- [[d07-array-variables]] Dijkstra's formal treatment of arrays as functions, matching the array axiom schema given here.
