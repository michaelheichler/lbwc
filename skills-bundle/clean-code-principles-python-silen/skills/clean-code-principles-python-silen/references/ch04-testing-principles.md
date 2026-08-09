# ch04: Testing Principles

> When this governs: writing, structuring, or reviewing automated tests for Python, choosing the test level (unit / integration / E2E), naming and structuring test methods, placing mocking seams, deciding what to assert, and refusing untestable designs.

## Principle index

- **Testing pyramid:** Many unit tests, fewer integration, a handful of E2E.
- **Unit = public functions in isolation:** Test public methods only, and mock all dependencies.
- **Test private code indirectly:** Never import or call a `_private` helper from a test.
- **Specify scenarios before implementing:** List happy/edge/failure/security cases first (USDD).
- **TDD red-green-refactor:** Write a failing test, make it pass, then refactor.
- **Test the specification, not the implementation:** Assert observable behavior, not internal calls you can drop.
- **AAA / Given-When-Then:** Three sections, keep the assert phase tiny.
- **Scenario-encoding test names:** `test_<method>__<scenario>` so a failure name pinpoints the case.
- **Cover edge and failure paths:** Empty, boundary, wrap-around, and every raise.
- **Mock at your own boundary:** Wrap third-party deps behind a seam, and mock the seam.
- **Choose the right test double:** Stub for results, spy/mock only to verify calls.
- **Keep test code clean:** Fixtures and helpers kill duplication, and type-hint tests.
- **Short test methods:** Max ~5-9 statements. More than 5-6 mock expectations means refactor the SUT.
- **Parametrize table cases:** One parametrized test, not copy-pasted near-duplicates.
- **Property-based for invariants:** Let Hypothesis generate inputs you would not pick.
- **Integration tests are black-box:** Drive public interfaces with real dependencies, and reuse across rewrites.
- **E2E tests are end-to-end and few:** Southbound input to northbound output, verify wiring, not detail.
- **Make features end-to-end testable:** Every backlog feature must have an observable output to assert.
- **Non-functional testing:** Performance, stability, reliability, security need their own (automated) gates.

## Principles

### Testing pyramid

- **Rule:** Write many unit tests, fewer integration tests, and only a handful of E2E tests.
- **Why:** Unit tests run in milliseconds and pinpoint the broken function. E2E tests are slow, flaky, and only say "something is wrong somewhere." Inverting the pyramid gives a slow suite that nobody runs and that fails for unrelated reasons.
- **Python:** Each level is a different scope of `pytest`. Unit: one function, deps mocked. Integration: real DB/broker via Docker Compose. E2E: deployed services, driven through the outermost interface. Keep them in separate directories (`tests/unit`, `tests/integration`, `tests/e2e`) so CI can run the cheap layer on every commit and the expensive layer on a schedule.

### Unit = public functions in isolation

- **Rule:** Unit-test public functions only. Replace every external dependency with a test double.
- **Why:** Tying tests to public behavior lets you rewrite internals freely. Isolation keeps the suite fast (no DB/network) and makes a failure mean "this function is wrong," not "some dependency is down."
- **Python:** Inject dependencies through a `Protocol` parameter so a unit test can pass a fake. Do not reach into module globals.
  ```python
  class LineReader(Protocol):
      def read_lines(self, source: str) -> list[str]: ...

  class ConfigParser:
      def __init__(self, reader: LineReader) -> None:  # seam
          self._reader = reader
  ```
- **See also:** `examples/testing-principles/config_parser.py`, `test_config_parser.py`, and fluent-python ch08 (Protocol/Callable), ch13 (Protocols/ABCs).

### Test private code indirectly

- **Rule:** Never call a `_name` helper from a test. Cover it through the public method that uses it.
- **Why:** Tests bound to private helpers break on every refactor even when behavior is unchanged, defeating the safety net. Private methods that are hard to reach indirectly are a signal to *extract a class* with its own public surface.
- **Python:** `ConfigParser._parse_line` is exercised only via `try_parse`. ✗ `parser._parse_line("x=1")` in a test. ✓ assert on the `Configuration` that `try_parse` returns. If a private method needs direct testing, promote it to a public method on a new collaborator.
- **Anti-slop:** LLMs love to "achieve coverage" by calling underscored helpers directly. That is coupling, not coverage.
- **See also:** `examples/testing-principles/test_config_parser.py`.

### Specify scenarios before implementing (USDD)

- **Rule:** Enumerate happy path(s), edge cases, failure scenarios, and security scenarios as test stubs before coding.
- **Why:** If you jump to the happy-path implementation you forget the edge/failure cases. An unimplemented case is also an untested case, so 100% line coverage still hides the bug.
- **Python:** Stub each scenario so none is forgotten, then implement.
  ```python
  def test_fetch__when_response_ok__returns_payload() -> None: ...
  def test_fetch__when_transport_raises__wraps_in_fetch_error() -> None: ...
  def test_fetch__when_status_is_error__raises_fetch_error() -> None: ...
  def test_fetch__when_json_invalid__raises_fetch_error() -> None: ...
  ```
  Use `pytest.mark.skip(reason="todo")` (not `assert False`) on stubs so the runner reports them as pending, not failing.
- **See also:** `examples/testing-principles/test_resource_fetcher.py`.

### TDD red-green-refactor

- **Rule:** Write a failing test, write the simplest code that passes it, then refactor with the test as a net.
- **Why:** Emergent design beats big-upfront-design. You write only code a test demands (YAGNI) and you refactor fearlessly. Working from specialized scenarios (empty, single, boundary) toward the general case surfaces edge bugs early.
- **Python:** For `CircularRoute.next_stop`, test empty → single-stop → middle → wrap-around → not-found, implementing the minimum each step. The final modulo (`(i + 1) % n`) emerges from the wrap-around test, not from guessing.
- **See also:** `examples/testing-principles/circular_route.py`, `test_circular_route.py`.

### Test the specification, not the implementation

- **Rule:** Assert on observable results. Only assert on internal calls at genuine boundaries you cannot observe otherwise.
- **Why:** Over-mocking turns a test into a transcript of the current code. It passes only while the implementation is byte-identical, and breaks on any refactor. The chapter's "max 5-6 mock expectations" rule is a smell threshold: more means the SUT does too much.
  ```python
  # ✗ asserts HOW it works (brittle): fails if you cache or reorder calls
  parser._parse_line.assert_called_once_with("host=localhost")
  # ✓ asserts WHAT it produces (stable)
  assert config.get("host") == "localhost"
  ```
- **Anti-slop:** Mocking the object under test, or asserting call order that the contract never promised.

### AAA / Given-When-Then

- **Rule:** Structure every test as Arrange, Act, Assert, and keep the Act to one call and the Assert minimal.
- **Why:** A uniform shape makes tests scannable and makes the single behavior under test obvious. Sprawling asserts test several things at once, so a failure no longer localizes the fault.
- **Python:** One logical assertion per test. If you need several, extract a well-named helper (`assert_called_with_timeout(...)`) so the test body still reads as one Then.
- **See also:** all `test_*.py` in `examples/testing-principles/`.

### Scenario-encoding test names

- **Rule:** Name tests `test_<method>__<scenario>[__<expected>]`, double underscore separating method from scenario.
- **Why:** A failing test name in CI output should explain the case without opening the file. Generic names like `test_parse_2` force you to read the body to learn what broke.
- **Python:** `test_try_parse__when_line_has_no_equals__raises_parse_error`. Order test methods to mirror the SUT's method order (and specialized → general) so navigation is mechanical.
- **Anti-slop:** `test_1`, `test_works`, `test_happy`, names that carry zero diagnostic signal.

### Cover edge and failure paths

- **Rule:** Test empty inputs, boundaries (first/last/off-by-one), wrap-around, and every code path that raises.
- **Why:** Bugs cluster at boundaries and in error handling (the code paths developers skip when chasing the happy path). The wrap-around in a ring and the "last loop counter" are classic off-by-one homes.
- **Python:** Give the trap its own named test, not a buried assertion:
  ```python
  def test_next_stop__when_last_stop__wraps_to_first() -> None:
      route = CircularRoute(["a", "b", "c"])
      assert route.next_stop("c") == "a"
  ```
- **See also:** `examples/testing-principles/test_circular_route.py`.

### Mock at your own boundary

- **Rule:** Wrap a third-party library behind a `Protocol` you own, and mock that, but never patch the library's deep internals.
- **Why:** Patching `requests.Response.__new__` or library private attributes makes tests fragile and version-coupled. Your own seam is stable, and the wrapper is where you translate library errors into one component-owned exception.
- **Python:** Inject a `Transport` Protocol. In the wrapper, translate `TransportError`/`ValueError` into `FetchError`. Use `create_autospec(Transport, instance=True)` so the mock rejects calls that violate the real signature. A bare `Mock()` silently accepts a renamed method or dropped kwarg.
  ```python
  transport = create_autospec(Transport, instance=True)
  transport.get.side_effect = TransportError("refused")
  with pytest.raises(ResourceFetcher.FetchError):
      ResourceFetcher(transport).fetch(url)
  ```
- **Anti-slop:** `@patch("requests.get")` scattered across tests instead of one injected seam, and using `Mock()` where `create_autospec` would catch the typo.
- **See also:** `examples/testing-principles/resource_fetcher.py`, `test_resource_fetcher.py`, and fluent-python ch08.

### Choose the right test double

- **Rule:** Use a stub when you assert on the result. Use a spy/mock only when the side effect is the behavior.
- **Why:** Mocks that verify calls couple the test to the implementation. A stub returning canned data keeps the test about *what the SUT produces*. Reserve `assert_called_*` for cases where "it called the dependency" is the spec (e.g., it must persist, must emit, must not retry).
- **Python:** `StubReader` (hand-written, returns lines) for `ConfigParser` result tests. `create_autospec` mock for `ResourceFetcher` where verifying the `timeout` kwarg reached the transport *is* the contract. Test-double vocabulary: fake (working but simplified), stub (canned answers), spy (records calls), mock (pre-programmed + verifiable).
- **See also:** `examples/testing-principles/test_config_parser.py` (stub) vs `test_resource_fetcher.py` (mock).

### Keep test code clean

- **Rule:** Hold test code to the same bar as production: type hints, no duplication, the project's linter.
- **Why:** Test code is read and refactored as often as production code. Copy-pasted setup rots and hides which detail actually matters. Duplicated arrange blocks are the #1 reason a test suite becomes unmaintainable.
- **Python:** A `pytest` fixture replaces the chapter's `__set_up`. A factory (`make_response`) and a shared assertion helper remove repetition. Fully annotate fixtures and helpers.
- **See also:** `examples/testing-principles/test_resource_fetcher.py`.

### Short test methods

- **Rule:** Keep each test to ~5-9 statements. If you need more than 5-6 mock expectations, refactor the production code.
- **Why:** A long test with many mock expectations means the function under test has too many collaborators, so *extract class* until each unit test is short and has few seams. The test length is a design feedback signal, not just a style rule.
- **Python:** Move repeated arrange into a fixture and repeated asserts into a helper so the test body stays at Given/When/Then length. If that still leaves six mocks, split the SUT.

### Parametrize table cases

- **Rule:** Collapse near-identical tests into one `@pytest.mark.parametrize` with `id=` labels.
- **Why:** Copy-pasted variants drift and bury the one differing input. Parametrization makes the input matrix explicit and each case reports as its own named test.
- **Python:**
  ```python
  @pytest.mark.parametrize("line", [
      pytest.param("=value", id="empty-name"),
      pytest.param("   =value", id="whitespace-name"),
  ])
  def test_try_parse__when_name_is_blank__raises_parse_error(line: str) -> None: ...
  ```
- **Anti-slop:** Three tests that differ by one literal and share an identical body.
- **See also:** `examples/testing-principles/test_config_parser.py`.

### Property-based for invariants

- **Rule:** When a property holds for all inputs, assert it with Hypothesis instead of hand-picked examples.
- **Why:** Example tests only prove the cases you imagined. Generated inputs find the ones you did not (empty, huge, duplicate, unicode). Invariants ("walking n steps around a ring returns to start") are ideal targets.
- **Python:** Guard the import so the file still runs without Hypothesis installed.
  ```python
  hypothesis = pytest.importorskip("hypothesis")
  from hypothesis import given, strategies as st

  @given(st.lists(st.integers(), min_size=1, unique=True))
  def test_next_stop__applied_n_times_returns_to_start(stops: list[int]) -> None: ...
  ```
- **See also:** `examples/testing-principles/test_circular_route.py`.

### Integration tests are black-box

- **Rule:** Drive the component's public interface against real dependencies. Assert on outputs, not internals.
- **Why:** Black-box integration tests survive a rewrite in another language/framework and can be written in parallel with implementation (shift-left). They confirm public methods correctly understand each other's contracts and that real DB/broker wiring works, which unit tests deliberately mock away.
- **Python:** Use a generic BDD tool (Behave + Gherkin `.feature` files) over framework-specific test tools so tests stay decoupled from the implementation stack. Spin dependencies up with Docker Compose, wait for ports to open before running, and cover the happy path plus the *main* failure scenarios only (the rest were covered by unit tests). Touch every public function with at least one integration test.

### E2E tests are end-to-end and few

- **Rule:** Each E2E test exercises the whole system from its southbound input to its northbound output, and keep them to a handful.
- **Why:** E2E tests verify deployment and inter-service wiring, not feature detail (already unit/integration tested). They are the slowest and flakiest layer, so a few high-value happy-path flows beat many.
- **Python:** Specify with Gherkin, implement with Behave, and run after deploy to a production-like environment, on a schedule if slow. Configure services via ConfigMaps/jobs, and assert on observable output (exported CSV, consumed message).

### Make features end-to-end testable

- **Rule:** Define every backlog feature so it has an observable output you can assert against.
- **Why:** A feature with no observable output (e.g., "consume Avro from Kafka") cannot be acceptance-tested or demoed. You cannot prove it works. Build a *walking skeleton* (a thin end-to-end path) first, then add flesh, so every later feature is demonstrable.
- **Python:** Order features so the first establishes an input→output path. Subsequent features extend it. ATDD/BDD specs become the acceptance tests shown in the system demo.

### Non-functional testing

- **Rule:** Add automated gates for performance, data-volume, stability, reliability, stress/scalability, and security.
- **Why:** Functional correctness says nothing about whether the system is fast, leak-free, resilient, or secure. Without an automated baseline, a performance regression or memory leak ships unnoticed.
- **Python:** Benchmark the busy loop in a test that fails if duration exceeds a per-host threshold captured on the first run, so a slowdown breaks CI. Use chaos tooling for reliability (kill a pod/broker, assert recovery), JMeter-style load for stability/soak, ZAP/Burp for penetration testing, and container vulnerability scans in the pipeline.

## Anti-slop checklist

- Do not call `_private` helpers from tests. Cover them through the public method.
- Do not mock the object under test, or assert call order the contract never promised.
- Do not patch third-party library internals (`requests.Response.__new__`). Wrap and mock your own seam instead.
- Do not use bare `Mock()` where `create_autospec` would catch a renamed method or dropped kwarg.
- Do not name tests `test_1` / `test_works`. Encode `<method>__<scenario>` so failures self-explain.
- Do not chase line coverage by exercising getters/trivia while leaving error paths and edges untested.
- Do not copy-paste near-identical tests. Parametrize them.
- Do not leave NotImplemented scenario stubs as silent passes. `skip` them so they show as pending.
- Do not write multi-screen tests with a dozen mock expectations. That is a design smell, so extract a class.
- Do not let integration/E2E tests assert internal detail already covered by unit tests.
- Do not duplicate arrange/assert blocks. Use fixtures and helpers, and type-hint test code like production code.

## Bundled examples

| File | Principle(s) demonstrated |
| --- | --- |
| `examples/testing-principles/config_parser.py` | Dependency seam (Protocol injection), private helper tested indirectly, named failure exception |
| `examples/testing-principles/test_config_parser.py` | Unit-in-isolation, AAA, scenario names, stub double, edge cases, parametrization |
| `examples/testing-principles/resource_fetcher.py` | Wrap third-party dep behind a seam, collapse all failures into one component exception |
| `examples/testing-principles/test_resource_fetcher.py` | Mock at the boundary, `create_autospec`, `side_effect` per failure, fixtures + shared assertion helper |
| `examples/testing-principles/circular_route.py` | Small index-driven SUT built for TDD, defensive copy, wrap-around logic |
| `examples/testing-principles/test_circular_route.py` | Red-green-refactor ordering, off-by-one edge cases, property-based invariant with Hypothesis |
