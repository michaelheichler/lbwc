# Pragmatic Programmer, ponytail's cut

Nine chapters of *The Pragmatic Programmer* (Hunt & Thomas), read through one lens: does this make ponytail lazier, or stop ponytail from being careless? Each doc lists the chapter's tips, marks them supports / guardrail / tension, and ends with the sharpest quotable lines. Pull a chapter open only when you need the warrant behind a rule.

## Supports (this IS the lazy move)

- **[ch01 — A Pragmatic Philosophy](ch01.md)** — Good-enough software and "know when to stop": shipping today beats the fantasy of perfect tomorrow, and overpolish loses the painting in the paint.
- **[ch02 — A Pragmatic Approach](ch02.md)** — ETC ("easier to change") is the one axis under every design rule; simplest code is almost always the most changeable. Tracer bullets, orthogonality, reversibility.
- **[ch05 — Bend, or Break](ch05.md)** — Coupling, inheritance, and hard-coded values are invisible weight on every future change. Decouple, pass state, prefer has-a. "A gorilla holding the banana and the entire jungle."
- **[ch08 — Before the Project](ch08.md)** — Policy is metadata; find the box before solving. The best solution sometimes isn't software at all.

## Guardrail (lazy means efficient, not careless)

- **[ch03 — The Basic Tools](ch03.md)** — Version control even on throw-aways, a failing test before the fix, "don't assume it, prove it." Plain text and shell pipes are the lazy multipliers.
- **[ch04 — Pragmatic Paranoia](ch04.md)** — Crash early over elaborate recovery, assertions stay in production, finish what you start. "A dead program does a lot less damage than a crippled one."
- **[ch06 — Concurrency](ch06.md)** — A quick mutex is not enough; shared state is incorrect state. Reach for actors only when a synchronous call won't do (tension: heavier to reason about).
- **[ch07 — While You Are Coding](ch07.md)** — Tests as design thinking, not overhead. Refactor early or pay compound interest. Simple code = smaller attack surface. Name well, rename now.
- **[ch09 — Pragmatic Projects](ch09.md)** — Do what works, not what's fashionable. Automate once, never pay again. Find each bug once, then a test owns it forever.
