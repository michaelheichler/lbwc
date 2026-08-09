---
unit: "Ch 9-10"
slug: "d06-nondeterminacy-and-scope"
title: "Bounded Nondeterminacy and the Scope of Variables"
book: "A Discipline of Programming"
one_liner: "Proves that every executable mechanism has bounded nondeterminacy (the continuity property) and designs a scope-and-initialization discipline that makes uninitialized variables statically impossible."
when_to_use: "Load when reasoning about nondeterministic choice, fairness, and termination guarantees, or when designing variable scoping, initialization order, const-vs-mutable declarations, and read/write access boundaries."
topics: [continuity, bounded nondeterminacy, unbounded choice, fairness, scope, initialization, declarations, block structure, const, immutability, definite assignment, information hiding, uninitialized variables, nomenclature]
key_terms: [property 5 (continuity), unbounded nondeterminacy, textual context, passive scope, active scope, initializing statement, virgin variable, privar, pricon, virvar, vircon, glovar, glocon]
related: [d03-wp-semantics-of-the-language, d02-states-and-semantic-characterization, d04-termination-and-euclid, d07-array-variables, d05-formal-treatment-of-small-examples]
---

# Bounded Nondeterminacy and the Scope of Variables

Why no real program can choose among infinitely many outcomes in finite time, and how to structure variable scope so that every read provably follows an initialization. **Source:** A Discipline of Programming, Ch 9-10.

## TLDR

- Property 5 (Continuity): for any increasing chain of predicates C0 => C1 => C2 => ..., wp(S, (E r: Cr)) == (E s: wp(S, Cs)). Every construct in the language (skip, abort, assignment, semicolon, IF, DO) provably satisfies it.
- The proof for IF hinges on the guard set being finite. Finitely many guarded commands means a maximum bound over the branches exists. Continuity is exactly bounded nondeterminacy.
- Consequence: the mechanism "set x to any positive integer" (guaranteed termination, no a priori bound on the result) cannot be programmed. Assuming it exists derives T == F.
- This protects the DO semantics: wp(DO, T) as "weakest precondition for guaranteed termination" is only justified because unbounded choice is impossible.
- Variables exist as nomenclature: Cartesian coordinates for a state space too large to name point by point. A program component touching few variables can be understood in the subspace it spans, independent of everything else (factorization).
- ALGOL-style "everything outer is visible" scoping makes outer variables vulnerable. Dijkstra proposes that each block enumerates its complete nomenclature, inherited and private, describing exactly its possible interference with the surrounding state, "no more and no less".
- A variable's scope splits into a passive scope (reference forbidden) and an active scope, separated by exactly one syntactically distinct initializing statement. The placement rules make definite-assignment analysis trivial and static.
- Six declaration headers combine origin (pri, vir, glo) with mutability (var, con). Initialization is creative, assignment is destructive, and they deserve different notations.

## When to reach for this

- You are tempted to assume fairness ("this branch will eventually be taken") to argue a loop terminates. Continuity says a guaranteed-terminating mechanism has a bounded set of outcomes, so fairness-based termination is outside the wp semantics.
- You are designing or reviewing declaration and initialization rules: const versus mutable, where types are stated, whether a variable may be read before its first write.
- You are auditing a function or module for what outer state it can touch, and want the interface to declare its full read/write footprint.
- A bug hunt for "who clobbered this variable" is forcing you to read every nested scope. That is the failure mode this chapter's discipline removes.
- You must decide whether initialization inside a conditional or a loop is safe on every path.

## Key concepts

### Continuity (Property 5) and why it holds

Take predicates C0 => C1 => C2 => ... (an ever-weakening chain, for all states). Property 5 states that S can establish the limit predicate (E r: r >= 0: Cr) exactly when it can establish some single Cs:

    wp(S, (E r: r >= 0: Cr)) == (E s: s >= 0: wp(S, Cs))

Right-to-left is easy monotonicity (Property 2). Left-to-right is the substance. For the alternative construct, each enabled branch j' guarantees some Cs from index s'(j') onward. Because there are at most n guards, the maximum smax of these indices exists, and monotonicity lifts every branch to C_smax, giving wp(IF, C_smax). Dijkstra flags the essential role of the guard set being finite. For DO, induction over the Hk approximations plus the IF case carries the property through, and swapping the two existential quantifiers ("there exists a (k, s) pair") finishes it.

Continuity matters because wp(DO, R) == (E k: k >= 0: Hk(R)) is itself such a limit of a chain (Hk(R) => Hk+1(R)), and that precondition will be fed as a postcondition into other statements. One payoff proved here: when BB holds initially, "do ... od" is equivalent to the same guard set run once as "if ... fi" and then repeated as "do ... od" (when BB fails initially, the first program acts as skip, the second as abort).

### The impossibility of "set x to any positive integer"

Specify S by (a) wp(S, x > 0) == T (always terminates with x positive) and (b) for every s, wp(S, 0 < x <= s) == F (no a priori upper bound). Since x > 0 is the limit of the chain 0 < x <= r, continuity gives

    T == wp(S, x > 0) == (E s: wp(S, 0 < x <= s)) == (E s: F) == F

a contradiction. No program for S exists. The natural attempt

    go_on := true
    x := 1
    do go_on -> x := x+1
    [] go_on -> go_on := false
    od

can leave x arbitrarily large but is not guaranteed to terminate. Capping the first guard with x < N restores termination but bounds the result. You get one or the other, never both.

Two reassurances follow. First, embedding the hypothetical S in "do x > 0 -> x := x-1 [] x < 0 -> S od" would make the formal wp(DO, T) == (x >= 0) clash with the intuition that x < 0 also terminates, so the impossibility is what keeps the DO semantics honest. Second, a terminating mechanism with unbounded nondeterminacy would choose among infinitely many possibilities in finite time, an insurmountable barrier to implementing the language. (Credit to John C. Reynolds for both observations.)

### Why variables at all

A circuit designer numbers automaton states as they occur to him and faces a painful "state assignment problem" later. The programmer cannot: his state count is astronomically larger. Variables are introduced immediately as Cartesian coordinates precisely because a nonsystematic terminology would make the design unmanageable. An assignment moves the state parallel to one axis, and a component touching few variables is understandable via its projection onto that small subspace. This separation (factorization) is the mental tool that scales, and the chapter's question is how program text should make it explicit.

### From free access to explicit inheritance

FORTRAN's implicit declarations meant a misspelling ("TETS" for "TEST") silently created a fresh variable. ALGOL 60 declarations caught that, and its blocks limited textual scope inward. But inner blocks could still see everything outer, and the "priority of innermost declarations" patch made outer variables extremely vulnerable: to find who tampered with one, you must read all inner blocks, including exactly those that should never touch it. Dijkstra's remedy: every block opens by enumerating its full textual context, global (inherited) names and local (private) names, all distinct. In his "confession" he rejects the softer opt-in version he first drafted: the inheritance list must name all and only the globals actually referenced, so it is a complete description of the block's possible interference with the surrounding state space.

### Passive and active scope: initialization by construction

What is a local variable's value on block entry? "Undefined" plus a runtime UNDEFINED check is expensive and breeds logical trouble (a manipulable NIL leads to "two bachelors married to the same nobody"). Default-zero initialization fools oneself by legalizing nonsense programs. Flow analysis warns but is approximate. Dijkstra instead restricts the language so the analysis is trivial: a variable's scope divides into a passive scope, where reference is forbidden and the variable is not yet a coordinate of the local state space, and an active scope, separated by an initializing statement. Placement rules guarantee, independent of guard values, exactly one initialization between block entry and exit and no active-scope statement before it:

- (A) The block's statement list contains a unique initializing statement for each private variable.
- (B) Statements before it lie in the passive scope. Inner blocks there may not inherit the variable.
- (C) Statements after it lie in the active scope and may inherit it.
- (D) The initializing statement is either primitive, or an inner block (which inherits the variable and recursively obeys A-D), or an alternative construct each of whose guarded lists obeys A-D.

The repetitive construct is excluded as an initializer: it cannot promise "exactly once". The ALGOL idioms this forbids (initializing x in only one branch of if B, or inside a for loop that may run zero times) are exactly the ones whose definedness cannot be decided statically, and they are pointless anyway: a variable whose value matters after a loop must occur in the invariant or the guards, so it had better be defined before the loop starts.

Initialization gets its own syntax (x vir int := E) because it is a different operation from assignment: initialization creates a variable with a value, assignment destroys the former value. A note adds the deeper point: without repetition you could program entirely with initialized constants. It is the loop that forces true variables into existence.

### The six headers and the interference table

Origin crossed with mutability gives privar, pricon, virvar, vircon, glovar, glocon.

- pri: private, no relation to the surrounding context, block must initialize it.
- vir: "virgin", inherited with the obligation to initialize (block starts in its passive scope, ends in its active scope).
- glo: inherited without permission to initialize, block lies wholly in the active scope.
- var/con: whether the block's own level may change the value after it is defined.

A table of permissible OUT headers per IN header enforces two consequences. "con" in the outer context excludes any inner block changing the value after initialization. Yet "con" outside still permits initialization to be delegated: an outer "pricon table" can be built up stepwise by an inner block that holds it as "virvar", after which it is constant forever. Immutability of the whole does not forbid a multistep construction phase. Type is stated at the initializing statement, not in the nomenclature, so type information does not diffuse through every inheriting block, and different alternative branches may even initialize with different types as long as the same operations apply.

Worked example (GCD of constants X, Y into global x, semicolon separators of the original omitted):

    begin
      glocon X, Y
      virvar x
      privar y
      x vir int, y vir int := X, Y
      do x > y -> x := x-y
      [] y > x -> y := y-x
      od
    end

## Applying it in modern code

- Definite-assignment analysis in Java, C#, Rust, and TypeScript strict mode is this chapter's proposal shipped: reads before initialization are compile errors, not runtime checks. Prefer languages and lint settings that enforce it, and structure code so every path initializes (rule D's if-form is match/switch arms that each assign).
- Declare at first use with an initializer instead of declaring early and assigning later. If initialization is genuinely multistep, wrap the build-up in a function or block that returns the finished value into a const (the pricon-built-by-virvar pattern, Rust's block expressions do exactly this).
- Default to const/final/readonly. Dijkstra's var-versus-con is exactly const discipline: it tells the reader whose text can be skipped when hunting a mutation.
- Make interference explicit: prefer parameters and return values over ambient captured state. Explicit capture lists (C++ lambdas), dependency injection, and narrow module exports approximate the "enumerate your inheritance, no more and no less" rule.
- Distrust nullable defaults and sentinel values. A manipulable UNDEFINED/NIL invites the bigamy-of-bachelors confusion. Use option types that force the uninitialized case to be handled.
- In concurrent or distributed reasoning, do not lean on fairness to prove termination. "Some branch is eventually scheduled" is unbounded nondeterminacy. If termination matters, bound it explicitly (a counter, a timeout, a variant function), which is exactly the x < N repair.
- Property-based tests can check the loop-unrolling equivalence: when the loop would be entered at all, forcing one guaranteed first iteration must not change observable behavior.

## Pitfalls

- Assuming a nondeterministic process that always terminates can still produce an unbounded result. The chapter proves you must give up one: bound the outcomes or give up guaranteed termination.
- Zero-initializing everything by default. It silences the detector for a widespread bug class by making nonsensical programs legal.
- Treating an inner scope's right to read outer variables as harmless. Unrestricted upward visibility means a corruption bug obliges you to read every nested block, including those that should never touch the variable.
- Initializing inside a loop or in only some branches. Whether the first assignment happened becomes a dynamic question, and static reasoning about the state space is lost.
- Conflating initialization with assignment. Reusing one notation hides that the first creates information and the second destroys it, and hides which reads can see a pre-initialization value.
- Enumerating inherited names but padding the list (imports or captures not actually used). The interference description then overstates the coupling and stops being documentation.

## Cross-refs

- [[d03-wp-semantics-of-the-language]] defines the constructs (IF, DO, Hk) and properties 1-4 that Property 5 extends.
- [[d02-states-and-semantic-characterization]] gives the state-space and predicate-transformer view that makes "variables as coordinates" precise.
- [[d04-termination-and-euclid]] treats termination via variant functions, the disciplined alternative to fairness assumptions ruled out here.
- [[d07-array-variables]] continues the "what constitutes a variable" question that the initialization discipline forces open.
- [[d05-formal-treatment-of-small-examples]] supplies the "for fixed x and y" example cited to motivate glocon.
