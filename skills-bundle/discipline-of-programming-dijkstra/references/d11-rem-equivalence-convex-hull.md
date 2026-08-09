---
unit: "Ch 23-24"
slug: "d11-rem-equivalence-convex-hull"
title: "Rem's Algorithm and the 3D Convex Hull"
book: "A Discipline of Programming"
one_liner: "Union-find with in-scan path compression derived from an invariant over the whole partition function, and an honest stepwise-refinement construction of a 3D convex hull including a general transitive-closure worklist algorithm."
when_to_use: "Load when implementing union-find or disjoint sets, incremental convex hulls or mesh data structures, worklist and transitive-closure algorithms, free-list storage reuse, or when decomposing a genuinely hard problem by stepwise refinement."
topics: [union-find, equivalence classes, disjoint sets, path compression, representation choice, convex hull, computational geometry, stepwise refinement, transitive closure, worklist algorithm, free list, edge data structure, invariants, termination]
key_terms: [identifying vertex, "part(f)", nonunique representation, Rem's algorithm, cap, light and dark faces, "inv/suc/end edge functions", consequences, "S(B)", holes, youngest hole, substitution hierarchy]
related: [d07-array-variables, d09-hamming-pattern-matching-two-squares, d10-prime-factor-villages-spanning-tree, d12-strong-components-manuals-retrospect]
---

# Rem's Algorithm and the 3D Convex Hull

How to choose data representations by update cost, how Rem derived a one-scan union-find from an invariant over the whole partition, and how stepwise refinement carries you through a problem you do not know how to solve. **Source:** A Discipline of Programming, Ch 23-24.

## TLDR

- Representation is an economic decision: the more redundant the stored information (edge list at one extreme, full connectivity matrix at the other), the more must be updated per new fact. Store a function that is cheap to query on average and cheap to update on average.
- Union-find: store f with f(k) = k marking the subset's identifying vertex and f(k) != k meaning "k is in the same subset as f(k)". Find is iteration of f to a fixed point, union is one assignment at the root.
- Intermediate nonunique representations of a unique abstraction (many forests encode the same partition) are legitimate, and deferring the cleanup of irrelevant information is a source of inventions.
- Rem's algorithm fixes the identifying vertex as the subset minimum, so f(k) <= k always. It processes an edge in one symmetric scan that compresses paths as it goes, each step decreasing at least one f-value, which is also the termination argument.
- The correctness proof works with part(f), the partition as a whole, not with N individual f-values. Choosing notation at the right abstraction level is what makes the proof possible.
- The 3D hull chapter is a live record: Dijkstra had never seen a solution when he started. Its method, stepwise refinement, produced 13 named code chunks in a substitution hierarchy 5 layers deep.
- Buried inside it is a general transitive-closure worklist algorithm (sets V and C, invariant V = S_C(B)) of which binary-tree traversal and the Hamming exercise are special cases, and whose element-choice from C is free (a stack is one option, not a necessity).
- Post-mortem lesson: all three transcription errors, plus a fourth found later by a reader, sat in sections announced as "coded quite easily". Premature efficiency concern (the "cap" idea) was the design's red herring.

## When to reach for this

- Implementing disjoint-set union (union-find), connected components over a stream of edges, or any equivalence-class bookkeeping.
- Choosing between storing raw input, precomputed answers, or a derived structure: this unit gives the query-cost versus update-cost framing.
- Building an incremental convex hull, a triangle mesh, or any topology where entities (faces) are anonymous and must be addressed through named edges.
- Writing a worklist algorithm (reachability, closure, garbage-collection-style marking) and wanting the invariant that proves it.
- Managing storage reuse with a free list of recycled names or slots.

## Key concepts

### The representation spectrum

For "are p and q connected after n edges", the raw edge list stores irrelevant facts and hides the answer. The full connectivity matrix (N^2 bits) stores every answer ready-made, but the answers are mutually dependent, so one new edge can force massive updates. A subset-numbering array answers queries in O(1) but makes union brutal: relabel a whole subset, found only by scanning the domain. The way out is a function f chosen so that both query (compute subset(p) from f) and update (process an edge) are cheap on average. This is the general design move: do not store the answer, store something from which the answer is cheaply computed and which is cheaply maintained.

### The parent-pointer forest

Initialize f(k) = k for all k. Iterating f from p walks within p's subset and reaches the identifying vertex, the fixed point. Find is `do ps != f(ps) -> ps := f(ps) od`. Union of the subsets of p and q is one assignment, f:(qs) = ps, at q's root. The naive version then adds cleanup passes (path compression) that re-walk each path to point its vertices at the root, which needs two scans per path and breaks the p-q symmetry. Dijkstra kept this clumsy version in the book deliberately, to show the economics and to legitimize nonunique intermediate representations: many different trees represent the same partition, and destroying the irrelevant differences may be postponed.

### Rem's algorithm

Rem restores symmetry and gets partial compression in a single scan by adding one design decision: the identifying vertex of a subset is its minimum, so the representation invariant is f(k) <= k, smaller f-values mean a cleaner tree, and the only cycles are the fixed points. Processing edge (p, q) is then derived, not guessed (see the formal apparatus below). The loop walks up both paths simultaneously, always advancing on the side with the larger current parent, and redirects each visited node toward the smaller parent found on the other side. On exit, p and q have a common ancestor value and the union is done. Every step lowers some f(k), so the walk both compresses and terminates.

### The 3D hull: topology through named edges

The 2D incremental hull generalizes: maintain the hull of the first np points, and for each new point split the hull surface into a "light" cap (faces the point sees from outside) and a "dark" cap, remove the light cap's interior, and fan new triangles from the point to the cap boundary. Faces have no names, so all administration is done in directed edges: inv(i) is the opposite edge (convention inv(i) = -i, so it needs no storage), suc(i) is the next clockwise edge of the face along i (suc(suc(suc(i))) = i for triangles), and end(i) is the endpoint. `ek := inv(suc(ek))` rotates around a vertex. Visibility of a face ("lumen") is the sign of the tetrahedron volume determinant between the new point and the face's three vertices.

### The design surprise: drop the phases

Dijkstra first designed a phase 1 (grow a cap of same-colored faces, worklist K) and a phase 2 (trace the light-dark boundary, second worklist H). Writing out the two guarded updates, he noticed neither used which set x came from: only membership in the union of H and K matters, to avoid re-confronting a face and thus to guarantee termination. The right/wrong color bookkeeping and the "cap" connectivity requirement were both unnecessary. His retrospective: he worried about efficiency too early, and had he focused on the logical requirement of guaranteed termination he would never have introduced caps at all.

### The transitive closure kernel

Finding the light cap's inner edges from its boundary B is an instance of a general problem. Given per-element "consequences", S(B) is the least set containing B and closed under consequences. Maintain V (found) and C (elements whose consequences may not yet be in V), starting V, C := B, B. Repeatedly pick any c from C, remove it, add its unfound consequences to both V and C. Stop when C is empty. The informal argument satisfied Dijkstra "for more than fifteen years" but is not a proof. The proof needs S_C(B), the closure computed as if elements of C had no consequences, and rests on two properties: S_C(B) is monotonic (shrinking C grows the closure) and unchanged when C gains elements outside it. Recursive binary-tree traversal is the special case where C is a stack and the membership test is skipped because trees have no sharing. Since any c may be chosen, recursion (LIFO) is one scheduling policy among many, which Dijkstra uses to deflate the claim that recursive solutions are "more basic".

### Holes: a free list for edge names

Deleting edges leaves gaps in the numbering. Rather than renumber (which invalidates every reference), keep the unused names on a free list threaded through the suc array itself: yh is the youngest hole, suc of a hole is the next older, 0 is permanently the oldest. Allocation pops yh, deletion pushes onto it. Each hole i stands for the pair {+i, -i}.

## The formal apparatus

Rem's derivation. Let part(f) be the partition represented by f, and part(f)$(p,q) the partition after merging the subsets of p and q (a no-op if already together). Required after processing edge (p,q):

    R:  part(f) = part(f_init)$(p, q)

Introduce local p0, q0 and the invariant

    P:  part(f)$(p0, q0) = part(f_init)$(p, q)

established by p0, q0 := p, q. With p1 = f(p0) and q1 = f(q0), we also want the loop to stop when

    Q:  part(f) = part(f)$(p0, q0)

since (P and Q) => R. Variant: the sum of all N f-values, decreasing every step because we only assign a value strictly smaller than the one replaced. That requirement generates the guards:

    do q1 < p1 -> f:(p0) = q1; p0, p1 := p1, f(p1)
    [] p1 < q1 -> f:(q0) = p1; q0, q1 := q1, f(q1)
    od

On termination p1 = q1, so f(p0) = f(q0), which gives Q. The redirection f:(p0) = q1 is safe for P because merging with q1 is the same merge as with q0 (they are already together), and p0 := p1 then restores the possibly broken link to p1. Dijkstra's note: proving this in terms of N separate f(k) values instead of part(f) is close to hopeless, the abstraction part(f) is what makes the argument writable.

Transitive closure. Invariants P1: V = S_C(B), P2: C is a subset of V, established by V, C := B, B. Termination: the count of elements in V but outside C grows by one per step and is bounded by the size of S(B), independent of which c is chosen.

## Applying it in modern code

- Rem's loop is a production-quality union-find variant: interleaved find with "splicing" compression, one pass, no recursion, no rank array. The invariant parent[k] <= k (or any fixed total order on nodes) is what makes it correct, so assert it.
- Frame storage decisions as query cost versus update cost per incoming fact. Caching every derived answer is the connectivity-matrix mistake, and invalidation pain is the predicted symptom.
- Allow temporarily messy internal states (unnormalized forests, deferred deletion, tombstones) as long as the abstraction function (part(f)) maps them to the right abstract value. Test through the abstraction, not the raw structure.
- The half-edge structures in every mesh library are Dijkstra's inv/suc/end. When entities are anonymous (faces, regions), address them through named handles and keep the administration in the handles.
- Write worklist algorithms with the V/C invariant in a comment, and keep the container choice (stack, queue, priority) an explicit policy decision, since correctness does not depend on it but fairness and performance do.
- Free lists threaded through the data they recycle (the holes trick) remain standard in allocators and slab designs. Reserve a sentinel name (edge 0) to smooth loop boundaries.
- When a design decision keeps resisting clean naming and definitions (as right/wrong did), treat that as a signal the concept is wrong, not that you need better names.
- Expect bugs in the parts labeled trivial. Dijkstra's errors were all in sections he had declared "coded quite easily". Test the boring glue as hard as the clever core.

## Pitfalls

- Storing precomputed answers without pricing their update cost: one new edge to the connectivity matrix can dirty a quadratic amount of state.
- Proving pointer-structure algorithms element by element instead of introducing an abstraction (part(f)) that captures the whole structure's meaning, which makes proofs unreadable or impossible.
- Optimizing before the termination argument is settled. The cap machinery and the two-phase design were pure overhead born of premature efficiency concern.
- Believing recursion is required for closure-style searches. The worklist formulation is more general and makes the scheduling policy explicit.
- Renumbering live entities after deletion instead of keeping a free list, which forces updating every reference.
- Forgetting to restore auxiliary invariants after structural surgery (the "start must again name a live edge" patch, and Bebie's set-value fix in Note 3): after removing or adding elements, re-establish every clause of the loop invariant, not just the obvious ones.

## Cross-refs

- [[d07-array-variables]] for the array operations (hiext, hipop, f:(i) = e) this unit's code leans on.
- [[d09-hamming-pattern-matching-two-squares]] for the Hamming exercise, named here as a special instance of the transitive-closure kernel.
- [[d10-prime-factor-villages-spanning-tree]] for the neighboring graph problem (minimal spanning tree) and similar representation trade-offs.
- [[d12-strong-components-manuals-retrospect]] for the next graph algorithm and Dijkstra's retrospective on the whole method.
