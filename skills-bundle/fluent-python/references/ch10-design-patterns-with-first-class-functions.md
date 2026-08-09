## Chapter 10: Design Patterns with First-Class Functions
### Core Ideas
- In Python, some object-oriented design patterns become smaller when single-method classes are replaced by plain callables.
- Strategy is the main case study: if each concrete strategy has no per-instance state, a function can stand in for a strategy object.
- A context object can accept an optional callable and invoke it with the context as an argument, keeping the algorithm swappable without an abstract base class.
- Lists and other containers can hold strategy functions, enabling meta-strategies such as selecting the best result from all registered algorithms.
- Module introspection can discover functions dynamically, but this creates implicit contracts about names, signatures, and module contents.
- Registration decorators make strategy collection explicit at definition time and avoid repeated manual lists.
- Command can also be simplified: many invokers can receive callbacks directly instead of command objects with an `execute` method.
- Callable instances and closures remain useful when a command or strategy needs stored state, undo behavior, or extra operations.

### Practitioner Guidance
- When reviewing a Strategy-like design, check whether concrete strategy classes contain state. If not, prefer functions with a clear callable type.
- Avoid creating an interface or abstract base class solely to declare one method when a callable protocol or `Callable` hint communicates the contract.
- Pass functions as configuration when the client should choose behavior at runtime, such as discounts, validators, exporters, or ranking rules.
- For "best available rule" behavior, collect candidate callables in a small registry and apply them uniformly to the same context object.
- Use a registration decorator when contributors may add strategies over time and forgetting a central list would cause silent omissions.
- Treat module introspection as a convenience for constrained modules, not as a default design. Enforce or test signatures if discovery is dynamic.
- For Command-like APIs, prefer callbacks for simple actions. Use callable classes or closures when the action must retain state.
- Keep names and type hints aligned with the callable contract so reviewers can see the expected input and return type without chasing inheritance.

### Pitfalls
- Do not replace classes with functions when each strategy needs independent mutable state, lifecycle hooks, or multiple public operations.
- Dynamic discovery via `globals()` or `inspect` can break if unrelated functions enter the module or expected signatures drift.
- A callable stored on an instance is not automatically bound like a method, so pass the context explicitly when the callable expects it.
- Manual registries are easy to forget when adding new strategies. Tests should cover aggregate paths such as "choose best".
- Over-applying classic patterns can add boilerplate and obscure the simpler Python abstraction.

### Skill Hooks
- design patterns in Python
- Strategy pattern
- Command pattern
- first-class functions
- callbacks vs command objects
- callable strategies
- registration decorators
- function registries
- plugin-like rule selection
- refactor single-method classes
- replace abstract base class with callable
- `Callable[[Context], Result]`
- `__call__`
- closures for stateful commands
- module introspection

### Cross-Links
- Chapter 9: decorators, registration decorators, and single-dispatch generic functions.
- Chapter 17: iterator pattern simplification through Python generators.
- Descriptor/method-binding discussion: why instance-held callables are invoked differently from methods.
