# 97 Things, ponytail's cut

The essays from *97 Things Every Programmer Should Know* (ed. Kevlin Henney, O'Reilly) that earn a place under ponytail's lens: does this make ponytail lazier, or stop it from being careless? A Sonnet swarm skimmed all 97 and most are about careers, tooling, or team process and do not touch the write-less-code question. The dozen below do. Titles and quoted lines are verified against the source. Pull one open only when you need the warrant behind a rule.

## Supports (this IS the lazy move)

- **Improve Code by Removing It** (thing_39). Names YAGNI by name and makes deletion the productive act. Features were "overimplemented, festooned with extra bells and whistles that were not required." Removing them improved performance and cut entropy, and the tests proved nothing broke. "If you don't need it right now, don't write it right now."
- **Simplicity Comes from Reduction** (thing_75). The boss who held the delete key down. Reduction is the work, not a cleanup afterthought: "mercilessly refactored, shifted around, or deleted," and if that fails, delete it all and retype from memory to cut the clutter.
- **Beware the Share** (thing_07). The sharpest statement of the trap behind ponytail's DRY rule. Reuse was frowned on because the shared code encoded two facts that "could evolve independently." Collapsing them coupled things that were never the same knowledge. Pull this when tempted to extract a helper from two look-alike blocks.
- **Don't Repeat Yourself** (thing_30). The canonical DRY definition ponytail's rule is built on: "every piece of knowledge must have a single, unambiguous, authoritative representation within a system." Knowledge, not lines.
- **The Unix Tools Are Your Friends** (thing_88). The ancestor of the ladder's stdlib/native/installed rungs. Compose small existing tools rather than write new code: "you create your own commands simply by combining the small but versatile Unix tools."
- **Resist the Temptation of the Singleton Pattern** (thing_73). A concrete named anti-pattern for "no unrequested abstractions." A singleton is global mutable state that "makes it harder to reason about the code" and breaks unit-test independence. Restrict it to classes that truly must never be instantiated twice, pass the interface instead.
- **Thinking in States** (thing_84). Replacing scattered boolean flags with one explicit state machine deletes the impossible states (an order that has shipped but is not paid). Fewer conditionals, fewer bugs, less code. State machines "are not particularly hard."
- **Beauty Is in Simplicity** (thing_05). The aesthetic anchor under "boring over clever." Plato, quoted in the essay: "Beauty of style and harmony and grace and good rhythm depends on simplicity."
- **Only the Code Tells the Truth** (thing_62). Backs the comment discipline: docs drift or get lost, "the source code may be the only thing left." Code that needs heavy explanation should be refactored, not annotated.
- **Put the Mouse Down and Step Away from the Keyboard** (thing_69). The literal form of "the best code is the code never written." The answer to the gnarly problem arrives on the walk back from the vending machine, not from typing more.

## Guardrail (lazy means efficient, not careless)

- **Test Precisely and Concretely** (thing_81). Sharpens "leave ONE runnable check behind." Test the essential behavior, not the incidental: a sort test that only checks "the result is sorted" passes a function that returns a constant sorted list. "Tests need to be both accurate and precise."
- **The Road to Performance Is Littered with Dirty Code Bombs** (thing_74). Why the lazy long game is not free. Coupled code turns a "3-4 hour" optimization into "3-4 weeks" when each fix breaks a distant dependent. The shortcut you skip cleaning up is the one that derails the schedule later.
