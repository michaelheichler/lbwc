## Chapter 9: Decorators and Closures
### Core Ideas
- A function decorator is a callable applied to a function object. The name originally assigned to the function is rebound to the decorator's return value.
- Decorator application happens while a module is being loaded, while the decorated function body runs only when later called.
- Registration decorators can leave the function unchanged while recording it in a registry. Wrapper decorators usually return an inner callable that adds behavior.
- Python decides local names at compile time: assigning to a name inside a function makes it local unless `global` or `nonlocal` says otherwise.
- A closure lets a nested function keep access to bindings from an enclosing function after that outer call has returned.
- `nonlocal` is required when a nested function must rebind an enclosing function's immutable state, such as counters or totals.
- `functools.wraps` preserves metadata and improves introspection for decorators that replace functions.
- `functools.cache`, `functools.lru_cache`, and `functools.singledispatch` show three major decorator uses: memoization, bounded caching, and type-based generic functions.

### Practitioner Guidance
- Treat decorator code as import-time code: avoid expensive work, hidden I/O, or environment-sensitive side effects unless registration at import is intentional.
- When writing wrappers, forward `*args` and `**kwargs`, return the wrapped result, and use `@functools.wraps` unless there is a strong reason not to.
- Use simple registration decorators for plugin tables, route maps, or strategy catalogs when the decorated callable should remain directly usable.
- Prefer `@cache` only when argument sets are small or process lifetime is short. Use `@lru_cache(maxsize=...)` for long-running services.
- Check that cached function arguments are hashable, because cache keys are built from call arguments.
- Use `@singledispatch` when behavior should vary by the first argument type and independent modules should be able to add implementations.
- Register `singledispatch` handlers against ABCs or protocols when broader type compatibility matters more than concrete class matching.
- For parameterized decorators, model the shape explicitly: outer factory accepts options, inner decorator accepts the function, wrapper handles each call.

### Pitfalls
- Forgetting that decorators execute at import can create surprising side effects or order-dependent registries.
- Assigning to an outer-scope immutable name inside a nested function without `nonlocal` causes local-binding errors.
- Returning a wrapper without `functools.wraps` hides the original function's name, documentation, and other metadata.
- A wrapper that accepts only positional arguments breaks decorated functions called with keywords.
- Unbounded caching can grow without limit when argument diversity is high.
- Stacked decorators apply from the closest decorator upward, so order changes behavior.

### Skill Hooks
- decorators, function decorators, wrapper functions, decorator factories
- closures, free variables, nested functions, lexical scope
- `nonlocal`, `global`, `UnboundLocalError`, local variable binding
- import-time side effects, registration decorators, plugin registries, route registration
- `functools.wraps`, preserving function metadata, introspection-safe decorators
- `functools.cache`, `lru_cache`, memoization, hashable arguments, bounded cache
- `singledispatch`, generic functions, first-argument dispatch, ABC registration
- stacked decorators, parameterized decorators, class-based decorators with `__call__`

### Cross-Links
- Chapter 10: decorator-backed registration for the Strategy pattern.
- Chapter 13: ABCs, virtual subclasses, and protocols used with `singledispatch`.
- Chapter 23: descriptors, relevant to robust decorator and wrapper behavior.
- Chapter 24: class decorators.
- Later method/attribute sections: `property`, `classmethod`, and `staticmethod`.
