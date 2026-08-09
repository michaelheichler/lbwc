## Chapter 16: Operator Overloading
### Core Ideas
- Python supports operator overloading through special methods, but only for existing operators and not for `is`, `and`, `or`, or `not`.
- Unary and ordinary infix operators should compute results without mutating their operands. Return a fresh object unless the object model clearly says otherwise.
- For binary operators, Python first tries the left operand's forward method, then the right operand's reverse method if the first result is `NotImplemented`.
- Return `NotImplemented` from an operator method when the operand is unsupported. Do not confuse it with raising `NotImplementedError`.
- Duck typing works well when an operand only needs to support a behavior, while ABC-based checks can make operator APIs safer and error behavior clearer.
- Rich comparisons have special fallback rules: equality can fall back to identity comparison, while ordering failures generally raise `TypeError`.
- Augmented assignment defaults to rebinding from the ordinary operator result, but mutable classes may implement in-place methods such as `__iadd__`.
- The `@` operator is available for matrix-style operations via `__matmul__`, `__rmatmul__`, and `__imatmul__`.

### Practitioner Guidance
- Overload operators only when the meaning is unsurprising for the domain. Math-like objects, paths, packet layers, and containers can justify it.
- Keep `+`, `*`, `/`, `@`, and comparison behavior consistent with user expectations from built-ins or established libraries.
- If a forward method can support mixed operand types, implement the matching reverse method when the operation is commutative or otherwise meaningful.
- Do not implement a reverse method when the forward method intentionally accepts only same-type operands and reversed mixed use should fail.
- Prefer `NotImplemented` over `TypeError` inside binary operator methods when another operand type might handle the operation.
- Use narrow checks for equality when permissive comparisons would surprise users, for example avoiding equality between a domain object and a plain tuple unless intentional.
- For mutable classes, make `__iadd__` and similar methods mutate `self` and return `self`. For immutable classes, rely on the default rebinding behavior.
- Make `+=` more permissive than `+` only when the left-hand object identity and result type remain obvious.

### Pitfalls
- Raising `TypeError` too early blocks Python from trying the reversed operation.
- Treating every iterable as compatible can produce misleading errors or overly broad equality.
- Implementing in-place operator methods for immutable objects breaks normal Python expectations.
- Overloading an operator for a clever but non-obvious meaning makes APIs harder to review and maintain.
- Forgetting that generator expressions are lazy can hide where an operator error actually occurs.
- Assuming `!=` always needs custom code can duplicate behavior already provided through `__eq__`.

### Skill Hooks
- operator overloading
- special methods for arithmetic
- `__add__`, `__radd__`, `__mul__`, `__rmul__`, `__matmul__`
- `NotImplemented` operator dispatch
- reverse/reflected operator methods
- rich comparison methods
- equality semantics review
- augmented assignment, `__iadd__`, mutable versus immutable
- duck typing versus ABC checks in operator methods

### Cross-Links
- Chapter 1: special methods and emulating numeric behavior.
- Chapter 11: `Vector2d` equality behavior and mixed-type comparisons.
- Chapter 12: the `Vector` sequence type used for operator examples.
- Chapter 13: ABCs, goose typing, and the `Tombola`/`BingoCage` example family.
- Chapter 17: generator expressions and lazy evaluation.
