"""Custom AST rules encoding the distinctive principles from *Clean Code:
Principles and Patterns, Python Edition* (Petri Silen, 2024) that generic
linters (ruff/mypy) do not catch.

Each rule is a small function ``(tree, source, path) -> Iterable[Finding]``
registered in ``RULES``. Keep rules **low false-positive**: an agent will treat
a finding as a real defect, so a noisy rule is worse than a missing one.

This module is pure standard library so it can be vendored into both the skill's
``scripts/`` and the MCP server without extra dependencies.
"""

from __future__ import annotations

import ast
import re
from collections.abc import Iterable
from dataclasses import dataclass

# Approved prefixes for functions/methods that return a boolean (predicates).
# Silen, ch.4/ch.3 "Naming Boolean Functions": a predicate must read as a yes/no
# question so call sites read like prose (``if order.is_paid():``).
PREDICATE_PREFIXES: tuple[str, ...] = (
    "is_", "are_", "was_", "were_", "has_", "have_", "had_", "can_", "could_",
    "should_", "shall_", "will_", "would_", "may_", "might_", "must_", "does_",
    "do_", "did_", "contains_", "exists", "matches_", "needs_", "allows_",
    "supports_", "uses_", "wants_", "owns_", "knows_",
)

# Methods that are bool by an external contract (stdlib/framework override), so a
# predicate prefix would be wrong, exclude them from CCP001.
KNOWN_BOOL_OVERRIDES: frozenset[str] = frozenset({"filter"})  # logging.Filter.filter

MUTABLE_COLLECTION_HINTS: tuple[str, ...] = (
    "list", "List", "dict", "Dict", "set", "Set", "bytearray",
    "MutableSequence", "MutableMapping", "MutableSet", "deque", "defaultdict",
)


@dataclass(frozen=True, slots=True)
class Finding:
    """One rule violation. ``rule_id`` is stable and links to a skill principle."""

    rule_id: str
    severity: str  # "error" | "warning" | "info"
    line: int
    col: int
    message: str
    principle: str  # human pointer into the skill, e.g. "ch02 Encapsulation Principle"
    tool: str = "clean-ast"


def _returns_bool(node: ast.FunctionDef | ast.AsyncFunctionDef) -> bool:
    ann = node.returns
    if ann is None:
        return False
    if isinstance(ann, ast.Name):
        return ann.id == "bool"
    if isinstance(ann, ast.Constant):  # e.g. "bool" as a string annotation
        return ann.value == "bool"
    return False


def _is_dunder(name: str) -> bool:
    return name.startswith("__") and name.endswith("__")


def _annotation_is_mutable(ann: ast.expr | None) -> bool:
    if ann is None:
        return False
    if isinstance(ann, ast.Name):
        return ann.id in MUTABLE_COLLECTION_HINTS
    if isinstance(ann, ast.Subscript) and isinstance(ann.value, ast.Name):
        return ann.value.id in MUTABLE_COLLECTION_HINTS
    if isinstance(ann, ast.Constant) and isinstance(ann.value, str):
        return any(h in ann.value for h in MUTABLE_COLLECTION_HINTS)
    return False


def rule_predicate_naming(
    tree: ast.AST, source: str, path: str
) -> Iterable[Finding]:
    """A function annotated ``-> bool`` should read as a yes/no question."""
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef):
            continue
        if _is_dunder(node.name) or node.name in KNOWN_BOOL_OVERRIDES or not _returns_bool(node):
            continue
        name = node.name.lower().removeprefix("_")
        if name.startswith(PREDICATE_PREFIXES):
            continue
        # info, not warning: a `-> bool` function may legitimately be a command
        # that returns a status (e.g. an idempotency handler), which a syntactic
        # rule can't distinguish from a query. Nudge, don't gate.
        yield Finding(
            rule_id="CCP001",
            severity="info",
            line=node.lineno,
            col=node.col_offset,
            message=(
                f"Boolean function {node.name!r} reads better as a predicate "
                f"(is_/has_/can_/should_/…) if it is a query, so call sites read like prose."
            ),
            principle="ch03 Uniform Naming / Naming Boolean Functions",
        )


def rule_leaky_getter(tree: ast.AST, source: str, path: str) -> Iterable[Finding]:
    """A zero-arg method returning a mutable internal collection by reference
    leaks modifiable internal state. Return a copy, a tuple, or a read-only view.
    """
    mutable_attrs = _mutable_collection_attrs(tree)
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef):
            continue
        args = node.args
        nondefault = len(args.posonlyargs) + len(args.args)
        if nondefault != 1:  # only 'self'
            continue
        body = [s for s in node.body if not _is_docstring(s)]
        if len(body) != 1 or not isinstance(body[0], ast.Return):
            continue
        ret = body[0].value
        if (
            isinstance(ret, ast.Attribute)
            and isinstance(ret.value, ast.Name)
            and ret.value.id == "self"
            and ret.attr in mutable_attrs
        ):
            yield Finding(
                rule_id="CCP002",
                severity="info",
                line=node.lineno,
                col=node.col_offset,
                message=(
                    f"{node.name!r} returns the mutable attribute self.{ret.attr} "
                    f"by reference. Callers can mutate internal state. Return a "
                    f"copy, a tuple, or an immutable view."
                ),
                principle="ch02 Encapsulation: don't leak modifiable internal state",
            )


def rule_param_alias_mutable(
    tree: ast.AST, source: str, path: str
) -> Iterable[Finding]:
    """Assigning a mutable parameter straight onto an attribute (``self._x = x``)
    aliases caller-owned state into the object. Copy it at the boundary.
    """
    for func in ast.walk(tree):
        if not isinstance(func, ast.FunctionDef):
            continue
        mutable_params = {
            a.arg
            for a in (*func.args.posonlyargs, *func.args.args, *func.args.kwonlyargs)
            if _annotation_is_mutable(a.annotation)
        }
        if not mutable_params:
            continue
        for stmt in ast.walk(func):
            if not isinstance(stmt, ast.Assign):
                continue
            if not (isinstance(stmt.value, ast.Name) and stmt.value.id in mutable_params):
                continue
            for tgt in stmt.targets:
                if (
                    isinstance(tgt, ast.Attribute)
                    and isinstance(tgt.value, ast.Name)
                    and tgt.value.id == "self"
                ):
                    yield Finding(
                        rule_id="CCP003",
                        severity="info",
                        line=stmt.lineno,
                        col=stmt.col_offset,
                        message=(
                            f"self.{tgt.attr} = {stmt.value.id}: aliases a mutable "
                            f"parameter into the object. Copy it "
                            f"(e.g. list({stmt.value.id})) to own the state."
                        ),
                        principle="ch02 Encapsulation: don't assign a mutable param to an attribute",
                    )


def rule_returns_none_and_value(
    tree: ast.AST, source: str, path: str
) -> Iterable[Finding]:
    """A function that sometimes ``return``s a value and sometimes falls through
    to an implicit ``None`` has an inconsistent contract. Make the return type a
    union and return explicitly, or never return a value.
    """
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef):
            continue
        returns_value = False
        bare_return = False
        for sub in ast.walk(node):
            if isinstance(sub, ast.FunctionDef | ast.AsyncFunctionDef) and sub is not node:
                continue
            if isinstance(sub, ast.Return):
                if sub.value is None:
                    bare_return = True  # a truly bare `return` (no value)
                elif not _is_const_none(sub.value):
                    returns_value = True
                # explicit `return None` is idiomatic with `-> X | None`. Ignore it.
        # Implicit fall-through to None is ruff's RET503. We only flag the mix of a
        # truly-bare `return` with a value-returning `return`.
        if returns_value and bare_return:
            yield Finding(
                rule_id="CCP004",
                severity="info",
                line=node.lineno,
                col=node.col_offset,
                message=(
                    f"{node.name!r} mixes 'return <value>' with a bare 'return'. "
                    f"inconsistent contract. Return a value explicitly (or 'return "
                    f"None') and annotate '-> X | None'."
                ),
                principle="ch03 Function Single Return / Error handling",
            )


# --- helpers -------------------------------------------------------------


def _is_docstring(stmt: ast.stmt) -> bool:
    return (
        isinstance(stmt, ast.Expr)
        and isinstance(stmt.value, ast.Constant)
        and isinstance(stmt.value.value, str)
    )


def _is_const_none(node: ast.expr) -> bool:
    return isinstance(node, ast.Constant) and node.value is None


def _mutable_collection_attrs(tree: ast.AST) -> set[str]:
    """Attributes assigned a list/dict/set literal or constructor anywhere."""
    attrs: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            value = node.value
            mutable = isinstance(value, ast.List | ast.Dict | ast.Set) or (
                isinstance(value, ast.Call)
                and isinstance(value.func, ast.Name)
                and value.func.id in {"list", "dict", "set", "defaultdict", "deque", "bytearray"}
            )
            if not mutable:
                continue
            for tgt in node.targets:
                if (
                    isinstance(tgt, ast.Attribute)
                    and isinstance(tgt.value, ast.Name)
                    and tgt.value.id == "self"
                ):
                    attrs.add(tgt.attr)
        elif isinstance(node, ast.AnnAssign) and _annotation_is_mutable(node.annotation):
            tgt = node.target
            if isinstance(tgt, ast.Attribute) and isinstance(tgt.value, ast.Name) and tgt.value.id == "self":
                attrs.add(tgt.attr)
    return attrs


# --- rules derived from the book's per-chapter machine-checkable list ---
# (only the ones ruff/mypy do NOT already cover, kept low false-positive)

WEB_FRAMEWORKS = frozenset(
    {"fastapi", "starlette", "flask", "django", "aiohttp", "sanic", "quart",
     "falcon", "bottle", "tornado", "rest_framework"}
)
# A module is in a "core" (framework-free) layer if its path has one of these segments.
CORE_LAYER_SEGMENTS = (
    "/services/", "/service/", "/repositories/", "/repository/", "/domain/",
    "/entities/", "/entity/", "/usecases/", "/use_cases/", "/application/",
)
HTTP_EXC_NAMES = frozenset({"HTTPException", "HTTPError", "abort", "HTTPNotFound", "HTTPBadRequest"})
SECRET_NAME = re.compile(r"(password|secret|token|api[_-]?key|credential|private[_-]?key)", re.I)


def _in_core_layer(path: str) -> bool:
    p = path.replace("\\", "/").lower()
    return any(seg in p for seg in CORE_LAYER_SEGMENTS)


def _build_parents(tree: ast.AST) -> dict[int, ast.AST]:
    parents: dict[int, ast.AST] = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            parents[id(child)] = node
    return parents


def _call_name(call: ast.Call) -> str:
    f = call.func
    if isinstance(f, ast.Name):
        return f.id
    if isinstance(f, ast.Attribute):
        return f.attr
    return ""


def rule_serializer_fields_all(tree: ast.AST, source: str, path: str) -> Iterable[Finding]:
    """``fields = "__all__"`` (DRF/serializer Meta) exposes every model field,
    including internal ones (an encapsulation/security leak)."""
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        if not any(isinstance(t, ast.Name) and t.id == "fields" for t in node.targets):
            continue
        v = node.value
        if isinstance(v, ast.Constant) and v.value == "__all__":
            yield Finding(
                rule_id="CCP005", severity="error", line=node.lineno, col=node.col_offset,
                message="fields = '__all__' exposes every field, whitelist an explicit public shape.",
                principle="ch01 Encapsulation / ch05 Security (no over-exposure)",
            )


def rule_web_framework_in_core_layer(tree: ast.AST, source: str, path: str) -> Iterable[Finding]:
    """A service/repository/domain module importing a web framework couples the
    core to the delivery mechanism (clean-architecture dependency-rule violation)."""
    if not _in_core_layer(path):
        return
    for node in ast.walk(tree):
        mods: list[str] = []
        if isinstance(node, ast.Import):
            mods = [a.name.split(".")[0] for a in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module:
            mods = [node.module.split(".")[0]]
        for m in mods:
            if m in WEB_FRAMEWORKS:
                yield Finding(
                    rule_id="CCP006", severity="error", line=node.lineno, col=node.col_offset,
                    message=f"core-layer module imports web framework {m!r}, keep delivery out of the domain.",
                    principle="ch06 API Design / ch02 Clean Microservice layering",
                )


def rule_http_exception_in_core_layer(tree: ast.AST, source: str, path: str) -> Iterable[Finding]:
    """Business logic raising a web HTTP exception couples it to the transport.
    Raise a domain error, let the controller map it to a status."""
    if not _in_core_layer(path):
        return
    for node in ast.walk(tree):
        if not isinstance(node, ast.Raise) or node.exc is None:
            continue
        exc = node.exc.func if isinstance(node.exc, ast.Call) else node.exc
        name = exc.id if isinstance(exc, ast.Name) else (exc.attr if isinstance(exc, ast.Attribute) else "")
        if name in HTTP_EXC_NAMES:
            yield Finding(
                rule_id="CCP007", severity="error", line=node.lineno, col=node.col_offset,
                message=f"core layer raises {name!r}, raise a domain error and map it in the controller.",
                principle="ch06 API Design: errors become wire responses at the boundary",
            )


def rule_jwt_insecure(tree: ast.AST, source: str, path: str) -> Iterable[Finding]:
    """JWT decoded without signature verification, or accepting alg 'none'."""
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or _call_name(node) != "decode":
            continue
        for kw in node.keywords:
            if kw.arg == "options" and isinstance(kw.value, ast.Dict):
                for k, v in zip(kw.value.keys, kw.value.values, strict=False):
                    if (isinstance(k, ast.Constant) and k.value == "verify_signature"
                            and isinstance(v, ast.Constant) and v.value is False):
                        yield Finding(
                            rule_id="CCP008", severity="error", line=node.lineno, col=node.col_offset,
                            message="jwt.decode disables signature verification, any token is accepted.",
                            principle="ch05 Security: verify tokens",
                        )
            if kw.arg in {"algorithms", "algorithm"}:
                vals = kw.value.elts if isinstance(kw.value, ast.List | ast.Tuple) else [kw.value]
                for e in vals:
                    if isinstance(e, ast.Constant) and isinstance(e.value, str) and e.value.lower() == "none":
                        yield Finding(
                            rule_id="CCP008", severity="error", line=node.lineno, col=node.col_offset,
                            message="JWT 'none' algorithm accepted, forgeable tokens.",
                            principle="ch05 Security: verify tokens",
                        )


def rule_process_pool_at_module_level(tree: ast.AST, source: str, path: str) -> Iterable[Finding]:
    """A ProcessPoolExecutor / multiprocessing.Pool built at import time (not inside
    a function or an ``if __name__ == '__main__'`` guard) breaks on spawn-based
    platforms with a fork-bomb-style re-import."""
    parents = _build_parents(tree)
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = _call_name(node)
        if name not in {"ProcessPoolExecutor", "Pool"}:
            continue
        anc = parents.get(id(node))
        in_func = under_main = False
        while anc is not None:
            if isinstance(anc, ast.FunctionDef | ast.AsyncFunctionDef):
                in_func = True
                break
            if isinstance(anc, ast.If) and _is_main_guard(anc):
                under_main = True
                break
            anc = parents.get(id(anc))
        if not in_func and not under_main:
            yield Finding(
                rule_id="CCP009", severity="error", line=node.lineno, col=node.col_offset,
                message=f"{name} created at module level, build it inside a function or under "
                        f"`if __name__ == '__main__'`.",
                principle="ch08 Concurrency: process pools and the spawn guard",
            )


def rule_secret_env_default(tree: ast.AST, source: str, path: str) -> Iterable[Finding]:
    """``os.environ.get('DB_PASSWORD', 'dev')`` ships a hard-coded secret default."""
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or _call_name(node) not in {"get", "getenv"}:
            continue
        if len(node.args) < 2:
            continue
        key, default = node.args[0], node.args[1]
        if not (isinstance(key, ast.Constant) and isinstance(key.value, str)):
            continue
        if not SECRET_NAME.search(key.value):
            continue
        if isinstance(default, ast.Constant) and isinstance(default.value, str) and default.value:
            yield Finding(
                rule_id="CCP010", severity="error", line=node.lineno, col=node.col_offset,
                message=f"hard-coded default for secret {key.value!r}, require it and fail fast if unset.",
                principle="ch05 Security / ch01 Externalized Configuration",
            )


def _is_main_guard(node: ast.If) -> bool:
    t = node.test
    return (
        isinstance(t, ast.Compare)
        and isinstance(t.left, ast.Name)
        and t.left.id == "__name__"
        and any(isinstance(c, ast.Constant) and c.value == "__main__" for c in t.comparators)
    )


RULES = (
    rule_predicate_naming,
    rule_leaky_getter,
    rule_param_alias_mutable,
    rule_returns_none_and_value,
    rule_serializer_fields_all,
    rule_web_framework_in_core_layer,
    rule_http_exception_in_core_layer,
    rule_jwt_insecure,
    rule_process_pool_at_module_level,
    rule_secret_env_default,
)


def run_ast_rules(source: str, path: str = "<string>") -> list[Finding]:
    """Parse ``source`` and run every registered rule. Returns [] on syntax error
    (ruff/pyflakes already report syntax errors with better messages)."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return []
    findings: list[Finding] = []
    for rule in RULES:
        findings.extend(rule(tree, source, path))
    findings.sort(key=lambda f: (f.line, f.col, f.rule_id))
    return findings
