# Getting Input from Users: Forms and Controls

Source: Designing Interfaces, 3rd Edition (Tidwell, Brewer, Valencia, 2020), Chapter 10.

## In one line

Forms cost users time and attention, so shrink the work (fewer fields, smart defaults, forgiving input), make required structure and errors obvious at a glance, and pick the pattern that best telegraphs what the control expects.

## Core ideas

- Treat every field as a cost the user pays. Cut fields you can derive (infer city/state from a zip code, infer card type from the first digits, skip a separate name field if email doubles as username). Fewer questions means fewer chances to abandon or error out.
- Explain the exchange. Tell users why the form is asking and what they get for answering, this reduces the feeling of being interrogated and improves completion.
- Keep the form visually quiet. No competing content or decoration, a form is a task, not a showcase.
- Chunk long forms into titled, labeled sections instead of one wall of fields, so users can navigate by structure instead of scanning everything at once.
- For long or optional-heavy forms, show only the first section by default and reveal the rest progressively, this lowers the intimidation of the form and reduces the odds a buried field gets skipped.
- Align labels and inputs on a clean vertical axis (single or multi-column) so the eye travels a short, predictable path from label to field.
- Decide, per product, one consistent convention for marking required vs. optional fields, and hold to it everywhere. Nielsen Norman Group's research still favors explicitly marking every required field as the most usable option. Two common alternatives: mark only the minority (whichever of required/optional is rarer), or mark all fields "optional" and leave the rest unmarked (the approach used by the US and UK government web design systems).
- Match control width and type to the expected answer length, a one-line text field signals a short answer, a radio group signals one-of-many, a large text area signals a paragraph. The control itself sets the user's expectation.
- Prefer accepting varied input formats over demanding one exact format (see Forgiving Format below), reserve strict formatting for fields with one universally understood shape.
- Validate as early as possible, field by field, not only at submission. Tell the user which field is wrong, why, and how to fix it, vague or delayed errors cost far more user effort than immediate, specific ones.
- Use top-aligned labels for responsive/mobile layouts, they survive column-stacking and viewport resizing without breaking label-to-input alignment, unlike left-aligned labels.
- Design for internationalization early: layouts that survive text-length changes and right-to-left scripts, locale-correct units/dates/currencies, and awareness that data privacy law may constrain what you can even collect.
- Confirm success explicitly after submission, tell the user what happens next.
- Usability-test forms specifically. Terminology, acceptable answers, and perceived intrusiveness are places where designers and users diverge more than almost anywhere else in a UI.
- Floating labels (label text that starts full size inside the field and shrinks to a caption on focus) are a live alternative to static labels, they save vertical space and look modern, but weigh whether the animation and reduced permanence suit your audience before adopting them everywhere.

## Named patterns and principles

**Forgiving Format**
What: Accept many input variations (spacing, hyphens, abbreviations, order) and let the software interpret them, rather than demanding one syntax.
Use when: input format is unpredictable or has many valid variants (search terms, dates typed different ways, stock tickers, credit card numbers) and you want the UI to stay visually simple.
Why: users do not want to think about "correct" formatting, they want to finish the task, computers are well suited to disambiguating input the user typed naturally.
How: this converts a UI problem into a parsing or software problem. Enumerate the realistic input variants, decide whether the software can disambiguate them, and test heavily with real users. Often paired with Input Hints or Input Prompt so users know roughly what is acceptable.

**Structured Format**
What: Break one field into multiple small fields that mirror the exact shape of the expected data (for example separate boxes for a 4 digit code, or month, day, year fields).
Use when: the format is fixed, well known, and unlikely to vary by user or locale (security codes, license numbers, a single country's phone numbers). Avoid it for anything that varies internationally (names, addresses, postal codes), use Forgiving Format there instead.
Why: the field structure itself tells the user what is expected, removing ambiguity about delimiters. Short chunks are also easier to proofread and remember than one long string, matching how the brain processes numbers.
How: size each sub-field to the expected character count, auto-advance focus to the next field once one is filled (while still allowing the user to go back), and optionally add Input Prompt text like "dd/mm/yyyy" inside the fields.

**Fill-in-the-Blanks**
What: Present one or more inputs embedded inside a natural language sentence or phrase, instead of as separate labeled fields.
Use when: label and value pairs read too dryly to convey intent, but you can phrase the whole task as a sentence the user completes (common for building filter rules or search conditions). Reimann and Cooper call this style "natural language output."
Why: a completed sentence is self-explanatory in a way that a label like "Field:" often is not, and it reads naturally when specifying conditional logic.
How: write the sentence carefully, use text fields, drop-downs, or combo boxes sized and baseline-aligned like words within it. Major caveat: localization becomes hard because comprehension depends on the source language's word order, plan for that or avoid this pattern in heavily localized products.

**Input Hints**
What: A short explanatory phrase or example placed beside or below an otherwise empty text field.
Use when: the field's purpose is not fully clear from its label alone, but you do not want to bloat the label itself.
Why: it gives context without forcing every user to read it, someone who already knows what to do can ignore the hint and focus on the label and control.
How: keep it short (a sentence or two, any longer and eyes glaze over), visually subordinate to the label (for example a couple points smaller), and either always visible or shown only on focus or on a triggering condition (for example only reveal password rules once the user starts typing a non-compliant password). If hints appear conditionally, budget layout space for them so the form does not jump.

**Input Prompt**
What: Placeholder text prefilled inside the control itself (a text field, drop-down, or combo box) that disappears once the user interacts with it. Distinct from floating labels: an Input Prompt vanishes on focus, a floating label shrinks and relocates but stays visible.
Use when: there is no sensible default value to prefill, but you still want to make the control self-explanatory without adding a separate hint.
Why: it sits exactly where the user will type, so it cannot be scanned past the way a side hint can, a direct instruction like "Type your message here" gets noticed.
How: for drop-downs use verbs like "Select" or "Choose," for text fields use "Type" or "Enter," followed by a noun naming what is wanted. The prompt itself must never be a selectable value. Disable the completion action (submit, next) while the prompt is still untouched, so you avoid throwing an error instead. Restore the prompt if the user clears their entry. Prefer Good Defaults and Smart Prefills over Input Prompt whenever you can make an accurate guess at the value instead of just describing it.

**Password Strength Meter**
What: Real time feedback on a new password's strength and validity as the user types (or on blur).
Use when: the product cares about password strength (registration, security sensitive account creation) and wants to steer users toward strong choices instead of rejecting weak ones only after submission.
Why: weak passwords are a security liability for the user and the system, immediate feedback lets the user fix it while they are still engaged instead of after a frustrating rejection.
How: show at minimum a weak, medium, strong indicator (color coded, for example red, yellow, green), ideally with specific advice ("needs 8+ characters," "add a number"). Pair with an explanatory hint before the field so expectations are set upfront. Do not show the password by default, but a visibility toggle is reasonable. Do not suggest alternate passwords for the user, general guidance is enough. Checklist style meters that tick off each satisfied rule (GitHub, Airbnb, H&M style) are a strong contemporary variant, thermometer style color fill meters (Menlo Club) or simple pass/fail states (Glassdoor) are lighter weight variants for lower stakes contexts.

**Autocompletion**
What: As the user types into a field, predict and surface likely completions (a selectable list, or an inline auto filled remainder) based on history, popular values, or matching content.
Use when: the expected input is predictable, drawn from the user's own history, a known set of values, or crowd sourced popular terms, search boxes, URL bars, email fields, filenames, and command line or code input are classic fits. Especially valuable on mobile, where typing is slow and error prone.
Why: it saves typing effort and reduces cognitive and physical burden (fewer keystrokes, less to remember), and it lowers error rates for long or awkward strings like URLs and emails. For search, showing what other people commonly type doubles as a map into what content or intent is popular.
How: build the completion set from the user's own history, a built-in dictionary of common phrases, the indexed content being searched, or contextual sources (for example a company directory for internal email). Offer completions either on demand (for example a Tab key, seen in code editors, good when users would recognize the right answer but cannot recall exact syntax) or unprompted once there is a single confident match (auto filled with the added text selected, so a keystroke overwrites it). Always default to not keeping an unconfirmed completion, never block ordinary typing, and stop re-offering a suggestion the user has repeatedly rejected. The core risk to manage is a wrong guess irritating the user into extra corrective work, so guess conservatively and correctly.

**Drop-down Chooser**
What: A closed control (button or field with a down arrow) that, on click, opens a compact panel containing a more complex selection UI: a list, table, tree, calendar, calculator, color picker, thumbnail grid, and so on.
Use when: the input is a choice (color, date, number, a hierarchical option) rather than free text, and you want a rich picking UI without permanently spending page space on it.
Why: users already understand the basic drop-down interaction, so extending it to richer content hides complexity until it is requested, keeping the surrounding page simple. It is a good substitute for launching a full modal dialog when the choice is common enough to warrant quick access.
How: show the current value plus a down arrow in the closed state, toggle the panel open and closed on click. Keep the panel compact using a familiar internal layout (list, table, tree, or a specialized widget). Scrolling inside the panel is acceptable for large sets but harder for users with limited dexterity, so weigh that cost. The panel can launch secondary modal dialogs (for example a full color picker) for less common needs, while surfacing the most common or recent choices directly to cut clicks for the average case.

**List Builder** (also called a two column multiselector)
What: Two visible lists, a source set and a destination set, with a way (buttons or drag and drop) to move items between them.
Use when: the user must build a subset selection from a source list too long to render as a flat set of checkboxes.
Why: showing both lists at once lets the user see the full state of their selection without leaving the page or scrolling through a giant checkbox list to verify what is checked.
How: place source and destination lists side by side or stacked, with Add and Remove controls between them (or rely on drag and drop if your users find it intuitive). Support multi-select so users can move batches at once. Decide deliberately whether moving an item removes it from the source (appropriate when items are truly being reassigned) or leaves the source list intact (appropriate when the source represents a stable underlying set, like a filesystem). Optional enhancements: search within either list, an orderable destination list, or a multilevel tree structured source list.

**Good Defaults and Smart Prefills**
What: Prefill form fields with reasonable default values drawn from session data, account info, location, current date and time, or other inferable context.
Use when: you can predict, with real confidence, what most users would answer, or the field is low stakes enough that "whatever the system decides" is fine with most users. Avoid defaulting sensitive or value laden fields (passwords, gender, citizenship) and never pre-check opt-in marketing checkboxes by default, doing so risks user discomfort or a sense of manipulation.
Why: a good default removes work outright, at worst it still models the expected answer format, saving the user a moment of guessing. The tradeoff to watch: a field the user can breeze past without engaging may not register with them at all, which matters if you need the user to consciously understand what they set.
How: prefill at initial render, or dynamically derive later defaults from earlier answers in the same form (for example infer state and country from a submitted zip code). Only default a field when you are genuinely confident most users will not change it, defaulting just to avoid a blank looking form creates rework instead of saving it. Occasional use flows like installers are a good candidate for aggressive defaulting, since most users do not care about the specifics.

**Error Messages**
What: Place a clear, actionable error message directly on the form near the field that caused it, when an input is invalid or missing.
Use when: any point users can submit unacceptable input (skipped required fields, unparsable values, malformed emails), and you want to guide correction with as little friction as possible.
Why: keeping messages and the offending control on the same page and visually connected means the user never has to memorize an error, dismiss a dialog, or hunt through the form to find the problem field. Historically, modal dialog errors or separate error screens forced users to close or navigate away and then re-locate the broken field from memory, both are worse than in place messaging.
How: prevent errors up front where possible (drop-downs instead of free text for constrained choices, Input Hints, Input Prompt, Forgiving Format, Autocompletion, and Good Defaults to reduce mistakes, a clear required and optional convention). When errors do occur on longer forms, also show a summary message at the top (visible first, and read first by screen readers), styled with stronger visual weight (bold, a strong color) than body text. Always mark the specific offending field or fields too, with color plus a non-color cue (icon, bold text) since color alone excludes colorblind users. Validate client side and in real time, as soon as focus leaves a field (or, for some validations, as the user types), rather than waiting for full form submission, this lets users fix problems before committing. Never show an error mid-typing a still incomplete but eventually valid entry, that is just noise. Write messages that name the specific field and problem in plain language ("You haven't given us your address," not "Not enough information"), and stay polite in tone rather than exposing raw system or error codes.

## How to apply

- Before adding any field, ask if it can be derived, defaulted, or dropped. Design for the minimum set that still gets the job done.
- Pick a text input strategy deliberately: Forgiving Format for open ended or variable input, Structured Format only for one rigid, universal shape, Fill-in-the-Blanks when the whole task reads as a sentence.
- Combine Input Hints and or Input Prompt with Forgiving Format so users know roughly what is acceptable even though the format is flexible.
- Wire up Autocompletion wherever input is predictable from history or a known set, but make wrong guesses cheap to override and defaulted to "not accepted."
- Add a Password Strength Meter to any new password flow, with live, specific, actionable feedback, not just pass or fail at submit.
- Use a Drop-down Chooser to keep rich pickers (calendars, color pickers, thumbnail grids) out of the main page flow.
- Reach for a List Builder instead of a giant checkbox list whenever the source set is large enough that scrolling to verify selections becomes a burden.
- Prefill with Good Defaults wherever you can predict the answer confidently, skip defaulting anything sensitive, identity related, or opt in.
- Validate field by field in real time, and always render error messages in place next to the offending control, plus a summary banner at the top for longer forms.
- Pick one convention for marking required vs. optional and apply it uniformly across the whole product, not just one form.
- For long or complex forms, break into Titled Sections, consider progressive show and hide of later sections, and for gatekeeper forms (signup, purchase) use Center Stage or a Modal Panel to remove distraction, with a Wizard and Progress Indicator if it spans multiple pages.
- Give every form a clearly Prominent "Done" button for the primary action, and visually de-emphasize secondary actions like reset or help.
- Design and test for internationalization (text expansion, right to left scripts, locale formats, legal data constraints) rather than retrofitting it later.

## Watch out for

- Do not mark all fields required by habit without deciding a real convention, inconsistency between forms in the same product confuses users.
- Do not over-rely on placeholder only labels (Input Prompt used as the sole label), disappearing text can make users think a field is already filled in, and it is an accessibility problem, real labels still matter.
- Do not put critical information only behind a "why we ask for this" link, most users filling out a form quickly will never click it.
- Do not let Autocompletion or auto-fill interfere with a user who is clearly typing something else, and stop re-suggesting a completion the user keeps rejecting.
- Do not use Structured Format for internationally variable data (names, addresses, phone formats), it breaks for locales it was not designed around, use Forgiving Format instead.
- Fill-in-the-Blanks is hard to localize because meaning depends on word order, plan for this explicitly in multi-language products.
- Avoid modal dialog error messages and separate post-submit error screens, both force the user to lose sight of the message while trying to fix the problem.
- Do not validate too aggressively mid-typing (flagging an incomplete but eventually valid entry as an error before the user finishes it), this reads as broken and annoying.
- Never default checkboxes for marketing or opt-in communications to checked.
- Be cautious with floating labels, the animation is stylish but can hurt certain audiences' usability, and it cannot substitute for a case where you need both a persistent label and separate hint text shown together.
