---
unit: "Ch 11"
slug: "d07-array-variables"
title: "Array Variables"
book: "A Discipline of Programming"
one_liner: "Treats an array as one single variable (a function from a finite integer domain to values) and defines a small set of array operations, each with exact wp semantics, instead of assignment to subscripted variables."
when_to_use: "Load when reasoning about array mutation, aliasing through indices, growing or shrinking sequences, in-place swaps, or writing pre and postconditions over array state."
topics: [arrays, array variables, aliasing, subscripted variables, wp semantics, function view of arrays, domain bounds, shift, extend, remove, swap, alt, stack operations, array assignment, initialization]
key_terms: [array variable, base type, lob, hib, dom, low, high, subordinate name, shift, hiext, loext, hirem, lorem, hipop, lopop, swap, alt, enumerated constant]
related: [d03-wp-semantics-of-the-language, d06-nondeterminacy-and-scope, d08-search-permutation-flag-file-merging, s15-notes-on-data-structuring-i]
---

# Array Variables

How to give arrays a semantics as clean as scalars: one variable whose value is a whole function, changed only by a small set of exactly specified operations. **Source:** A Discipline of Programming, Ch 11.

## TLDR

- Do not model an array as a set of subscripted variables. That view breaks value initialization discipline and makes aliasing unanswerable: is `A[i], A[j] := x, y` legal when `i = j`? The subscripted-variable notion is the bug, not the concurrent assignment.
- Instead, an array variable is a single variable whose value is a function from a finite domain of consecutive integers to values of a base type. Equality of two array values is decidable: same domain and same value at every point.
- The domain is part of the value, not part of the type. Every array variable carries its bounds with it: `ax.lob` (lowest index), `ax.hib` (highest index), `ax.dom = ax.hib - ax.lob + 1 >= 0` (size). The empty array still has a position on the number line (`hib = lob - 1`).
- Arrays are changed by named operations, each a total redefinition of the one array variable with exact wp semantics: `shift` (move the domain), `hiext`/`loext` (grow by one point), `hirem`/`lorem` (shrink by one point, abort on empty), `swap(i, j)` (exchange two values), `alt(i, x)` (redefine one value, written `ax:(i) = x`).
- Every wp is computed by substituting a primed array `ax'` for `ax` in the postcondition, where `ax'.lob`, `ax'.dom`, and `ax'(arg)` are defined in terms of the old value. Index-in-domain conditions are conjoined for the partial operations.
- Classic subscripted assignment `ax[i] := x` is exactly `ax:alt(i, x)`. It changes the array as a whole: two functions differing in one point are different functions.
- Whole-array assignment `ax := bx` is deliberately withheld because it hides a copy of unbounded size. Only small enumerated constants may be assigned, so expensive operations cannot appear on paper as innocent ones.
- All the primitive operations are assumed to cost roughly the same, independent of argument values. Operations chosen as primitive must not invite micro-optimization case analysis.

## When to reach for this

- You need a precise pre/postcondition for code that mutates an array element, and indices may alias (`a[i]` and `a[j]` with possibly `i = j`).
- You are designing an API for a growable or shrinkable sequence (stack, deque, sliding window) and must decide which operations to expose and what each guarantees.
- You are writing assertions or proofs about loops that build an array value step by step.
- You are deciding whether an operation that copies a large structure should look syntactically cheap in an interface.
- You need to reason about out-of-bounds access as a specified failure (abortion) rather than undefined behavior.

## Key concepts

### Why the subscripted variable must go

Two reasons kill the ALGOL 60 view of an array as numbered elementary variables. First, initialization discipline (each variable has a passive scope, then a syntactically marked initialization, then an active scope) cannot be enforced element by element when element names are computed at run time. Second, and more fundamental, the axiomatic definition of assignment works by substitution of a variable, and substitution cannot tolerate uncertainty about whether two variables are the same. `A[i]` and `A[j]` are the same variable exactly when `i = j`, which is a run-time fact. Allowing `A[i], A[j] := x, y` only under side conditions piles logical patch upon patch. The cure is to make the whole array one variable.

### The array as a function

A scalar integer variable is an integer-valued function on a one-point domain. An array variable generalizes this: its value is a function of one integer argument, defined on a finite set of consecutive integers, unchanged unless explicitly changed. Because the domain is an aspect of the value (not of the type), there is just one type "integer array" and one type "boolean array", and any code can ask an array for its own bounds. Contrast ALGOL 60, where bounds live in the declaration, so an inner block cannot even test whether two global arrays are equal.

### Subordinate names and inquiries

The dot notation `ax.lob` means: the name after the dot is subordinate to the type of the variable before the dot. Inquiries on an array value:

- `ax.lob`, `ax.hib`: lowest and highest point of the domain.
- `ax.dom`: number of points, always `ax.hib - ax.lob + 1 >= 0`.
- `ax(i)`: the function value at point `i`, defined only for `ax.lob <= i <= ax.hib`.
- `ax.low = ax(ax.lob)` and `ax.high = ax(ax.hib)`, defined only when `ax.dom > 0`.

Redundant names like `hib` are provided deliberately. If `hib` had to be written as `lob + dom - 1`, it would be "twice as expensive" to use, and cost asymmetries between equivalent formulations are guaranteed to twist the programmer's thinking.

### The modifiers

Written `ax:op(...)`. The colon signals that the variable's value is being redefined (the notation echoes `:=`).

- `ax:shift(k)`: move the whole domain k places up the number line. Values and their order are untouched. `shift(0)` is `skip`.
- `ax:hiext(x)` and `ax:loext(x)`: extend the domain by one point at the high or low end, with new value `x` (of the base type). Defined even on the empty array, which is why the empty domain keeps a position on the number line.
- `ax:hirem` and `ax:lorem`: remove the high or low point, losing its value. Abort when `dom = 0`.
- `x, ax:hipop` is `x := ax.high; ax:hirem` (and `lopop` likewise with `low` and `lorem`). These give stack and queue behavior directly.
- `ax:swap(i, j)`: exchange the values at `i` and `j`. Aborts unless both indices lie in the domain. `i = j` is explicitly allowed and is a no-op, so no case analysis is needed at call sites.
- `ax:alt(i, x)`, written `ax:(i) = x`: redefine the single value at point `i`. Aborts unless `i` is in the domain. This is the traditional subscripted assignment, renamed to stress that it changes `ax` as a whole.

### The economics of array assignment

Building an array value gradually, by steps whose new value is a pleasant derivation of the old, is the normal case, and each step above is cheap. Whole-array assignment `ax := bx` implies copying a possibly huge value, so a language where `x := y` is nice but `ax := bx` is secretly expensive would mislead. The compromise: only enumerated constants may be assigned, e.g. `bx := (5, true, true, false, true)` sets `bx.lob = 5` with the listed values, so big initializations cannot be written down unnoticed. Most initializations are expected to be with `dom = 0`. Storage limits ("hints to the compiler") are not part of the program: they permit, but never oblige, an implementation to abort when a stated limit is exceeded.

## The formal apparatus

All modifier semantics follow one scheme: `wp("ax:op", R) = (domain conditions) and R[ax := ax']`, where `R[ax := ax']` is R with every occurrence of `ax` replaced by `ax'`, and `ax'` is defined from the old `ax`. Postconditions need only mention `ax.lob`, `ax.dom`, and `ax(arg)`, since these determine the value.

shift:
```
wp("ax:shift(E)", R) = R[ax := ax']  where
  ax'.lob = ax.lob + E,  ax'.dom = ax.dom,  ax'(arg) = ax(arg - E)
```
(Equivalently: replace `ax.lob` by `ax.lob + E` and `ax(arg)` by `ax(arg - E)` throughout R.) If E itself depends on ax, first compute wp with a fresh name K, then substitute E for K, the same trick as for `x := x + f(x)`.

hiext (loext is the mirror image at the low end):
```
wp("ax:hiext(x)", R) = R[ax := ax']  where
  ax'.lob = ax.lob,  ax'.hib = ax.hib + 1,  ax'.dom = ax.dom + 1
  ax'(arg) = x         for arg = ax.hib + 1
           = ax(arg)   otherwise
```

hirem (lorem mirrors at the low end):
```
wp("ax:hirem", R) = ax.dom > 0 and R[ax := ax']  where
  ax'.hib = ax.hib - 1,  ax'.dom = ax.dom - 1
  ax'(arg) = ax(arg) for arg != ax.hib, undefined at ax.hib
```

swap:
```
wp("ax:swap(i,j)", R) = ax.lob <= i <= ax.hib and ax.lob <= j <= ax.hib
                        and R[ax := ax']  where
  domain unchanged,  ax'(i) = ax(j),  ax'(j) = ax(i),  ax'(arg) = ax(arg) otherwise
```

alt:
```
wp("ax:(i) = x", R) = ax.lob <= i <= ax.hib and R[ax := ax']  where
  domain unchanged,  ax'(i) = x,  ax'(arg) = ax(arg) for arg != i
```

The alt rule is the load-bearing one for everyday code: the wp of `a[i] := x` with respect to a postcondition mentioning `a(j)` must consider both cases `j = i` and `j != i`. That is where aliasing bugs hide, and the substitution-on-the-whole-array rule handles it mechanically.

## Applying it in modern code

- When proving or testing code with `a[i] = x`, rewrite the postcondition over the updated function: `a'(k) = (x if k == i else a(k))`. Never substitute for `a[i]` alone, since other index expressions may alias it.
- Treat bounds as part of the value: prefer containers that carry their own length (vectors, slices) over raw pointers plus a separately tracked size, so any code can ask the data for its domain.
- The modifier set maps directly onto modern APIs: `hiext`/`hirem`/`hipop` are `push`/`pop` on a stack or the grow end of a vector, `loext`/`lorem`/`lopop` give deque behavior, `swap` is the in-place exchange at the heart of sorting and partitioning.
- Make out-of-range indexing a specified failure (checked access, assert, exception), matching abortion in the wp, rather than silent undefined behavior.
- Follow the swap precedent: define operations to be total over easy edge cases (`swap(i, i)` is a no-op, extend works on empty) so callers need no defensive case splits.
- Keep hidden copies visible. An assignment or parameter pass that duplicates a large structure should be syntactically loud (explicit `clone()`, `copy()`), never spelled like a scalar assignment.
- Cost model discipline: expose as primitive only operations whose cost is roughly uniform and independent of argument values, otherwise call sites fill up with speculative micro-optimizations that need probability estimates to justify.

## Pitfalls

- Reasoning about `a[i]` as an independent variable. Under aliasing (`i = j`), substitution-based reasoning silently produces wrong preconditions. Always update the array as one function.
- Writing multiple simultaneous element assignments (`a[i], a[j] = x, y`) without deciding what `i = j` means. Any answer short of "one array update" is a logical patch.
- Forgetting the domain conjunct: the wp of element update, swap, and remove includes index-in-bounds. Dropping it turns abortion into false confidence.
- Letting equivalent formulations have different costs (like `hib` versus `lob + dom - 1`). The cheaper spelling will warp designs toward it regardless of clarity.
- Treating storage-limit hints as semantics. They license an implementation to abort, they never change what a correct execution computes.
- Making expensive whole-structure copies look like cheap scalar assignments in an API, which misleads every reader about the cost of the code.

## Cross-refs

- [[d03-wp-semantics-of-the-language]] for the wp calculus and the axiom of assignment these array rules extend.
- [[d06-nondeterminacy-and-scope]] for the concurrent assignment, initialization, and the passive/active scope discipline whose breakdown motivated array variables.
- [[d08-search-permutation-flag-file-merging]] for worked programs (Dutch national flag and others) that live on swap and alt.
- [[s15-notes-on-data-structuring-i]] for the companion treatment of data types and structured values in Structured Programming.
