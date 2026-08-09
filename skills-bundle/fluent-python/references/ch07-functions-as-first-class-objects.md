## Chapter 7: Functions as First-Class Objects
### Core Ideas
- Python functions are ordinary runtime objects: they can be rebound, stored, passed into other functions, returned, inspected, and documented through attributes.
- A higher-order function accepts another function or produces one. Common Python examples include `sorted`, `min`, `max`, `map`, `filter`, `reduce`, and `functools.partial`.
- In modern Python, comprehensions and generator expressions often express `map` and `filter` patterns more clearly, while built-ins such as `sum`, `all`, and `any` cover many reduction cases.
- `lambda` creates a function object, but its expression-only body makes it best suited for tiny inline callbacks, especially sort keys or simple adapters.
- Python has many callable forms beyond plain functions, including built-ins, methods, classes, callable instances, generators, coroutines, and async generators.
- Defining `__call__` lets an instance behave like a function while keeping state between calls. This is useful for stateful callbacks, memoizing helpers, and decorator objects.
- Function signatures can control argument binding with positional varargs, keyword varargs, keyword-only parameters, and Python 3.8+ positional-only parameters.
- The `operator` and `functools` modules provide small callable factories and adapters that reduce boilerplate lambdas.

### Practitioner Guidance
- Treat functions as values during design: pass behavior into APIs instead of hard-coding conditionals when a caller-supplied policy is clearer.
- Prefer comprehensions or generator expressions over `map` and `filter` when they improve readability or remove a throwaway lambda.
- Use named functions instead of complex lambdas. If the explanation of a lambda needs a comment, it likely deserves a `def`.
- Use `callable(obj)` for capability checks rather than assuming only function objects can be invoked.
- Reach for `__call__` when a callback needs persistent internal state and a class gives cleaner structure than a closure.
- Use keyword-only parameters for options that should be explicit at call sites, especially booleans, formatting controls, and API modifiers.
- Use positional-only parameters sparingly, mainly when parameter names are implementation details or when matching built-in-like APIs.
- Prefer `operator.itemgetter`, `operator.attrgetter`, `operator.methodcaller`, and `functools.partial` for simple extraction, method invocation, or argument binding.

### Pitfalls
- Overusing functional tools where a comprehension, loop, or named helper is easier to review.
- Hiding meaningful behavior inside lambdas that are hard to debug and appear only as anonymous frames.
- Forgetting that generator, coroutine, and async generator functions return workflow objects, not final application values.
- Assuming a callable has function-specific attributes. Classes, methods, partials, and callable instances have different surfaces.
- Letting `*args`, `**kwargs`, `/`, and `*` signatures become clever instead of making the call contract clearer.
- Using `reduce` for common aggregations already handled by clearer built-ins.

### Skill Hooks
- first-class functions, functions as values, pass function as argument, return function
- higher-order functions, callback design, function object attributes, `callable`
- `lambda`, anonymous function refactor, sort key, key function
- `map`, `filter`, `reduce`, comprehensions vs functional style
- `operator.itemgetter`, `operator.attrgetter`, `operator.methodcaller`, operator functions
- `functools.partial`, argument freezing, callback adapter, partial application
- `__call__`, callable instance, stateful callable, decorator object
- positional-only parameters, keyword-only parameters, `*args`, `**kwargs`

### Cross-Links
- Chapter 4 / Unicode Text: normalization can be wrapped with `functools.partial` for repeated text handling.
- Chapter 8 / Type Hints in Functions: annotations and function signatures are treated in depth after this chapter.
- Chapter 9 / Decorators and Closures: decorators, closures, `cache`, `singledispatch`, and stateful function behavior build directly on first-class callables.
- Chapter 10 / Design Patterns with First-Class Functions: functions can simplify pattern implementations that otherwise need heavier object structures.
- Chapter 17 / Iterators, Generators, and Classic Coroutines: generator functions and iterable reductions get fuller treatment there.
- Chapter 21 / Async Programming: native coroutines and asynchronous generators require async frameworks and are expanded there.
