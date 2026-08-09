# Rethinking Data Entry, Storage, and Retrieval

Source: *About Face: The Essentials of Interaction Design*, 4th Edition (Cooper, Reimann, Cronin, Noessel, 2014), Chapter 14.

## In one line

Data entry, file storage, and search should be built around the user's mental model and forgiving of human behavior, not around the database's need for clean, pre-typed, pre-located records.

## Core ideas

**Data integrity vs. data immunity.** The traditional approach (data integrity) treats incoming data as suspect and blocks anything that doesn't validate, like a customs checkpoint. This protects the database but punishes the user for every real-world messiness: incomplete data, informal formats, honest typos. The better approach (data immunity) makes the application smart enough to accept imperfect input and work around it: parse "nine" as 9, flag "TZ" plus "Dallas" as a likely Texas typo, and annotate what it did. Why: software exists to serve the person using it, not the other way around. The computer should do the work of interpreting, and the human should make the decisions.

**Handling missing data.** Don't block save or progress just because a field is empty. Real workflows often mean partial information now, completed later. Flag missing required fields with quiet, modeless cues (color, icon, tooltip) rather than a blocking dialog. Why: a purchasing clerk who enters records all day has better situational awareness of what's missing than a popup does, and stopping him to state the obvious wastes his time and insults his competence.

**Treat professionals as professionals.** The old image of the data-entry clerk as an interchangeable, untrustworthy keypuncher is outdated. Most data entry today is done by engaged professionals or by customers themselves. Software that treats users as suspects breeds resentment, turnover, and more errors, not fewer. Trust produces better outcomes than surveillance.

**Fudgeability.** Real-world work processes are flexible: a clerk might reorder a queue, hold a record in suspense, or bend a rule to keep a customer happy. Systems that are too rigid to permit this force people to work around the software instead of with it. The fix is not to forbid workarounds but to make actions visible, reversible, and recorded so accountability is preserved even when flexibility is allowed.

**Auditing, not editing.** An application should not aggressively "fix" or block what a user enters, because it might be wrong about what's wrong, and because blocking removes the user's chance to learn from the mistake. Instead, it should quietly track and surface the user's actions (an audit trail) so problems can be found and undone later. Word's real-time wavy-underline spell check is the good example: it flags without interrupting. Word's AutoFormat is the bad example: it silently overrides and gives no easy way back.

**Rethinking storage: the two-copies problem.** Under the hood, every open document exists twice, once in memory, once on disk, and classic file-system UI (Save, Save As, Close, Save Changes dialogs) exposes that plumbing directly to the user. Most people's mental model is of one document, not two copies to reconcile. This mismatch produces confusing prompts ("Do you want to save changes?"), a Save As dialog that only works the first time, and a broken flow for renaming or archiving a file that's still open. The fix is a unified file model that hides the disk/memory split entirely and exposes only goal-level actions: autosave, copy, rename, move, revert, discard changes, version.

**Save Changes dialogs are a probability error.** The dialog treats "save" and "don't save" as equally likely outcomes worth asking about, but users click Save overwhelmingly more often. This is the same possibility-vs-probability confusion covered elsewhere in the book: rare cases shouldn't dictate the default interaction for the common case. Assume the yes.

**Storage and retrieval are separable, and should be separated.** In the physical world, where you put an object (storage) is also how you find it later (retrieval), the two are coupled by necessity. Computers don't have that constraint, but most software still couples them anyway, forcing users to remember a file's exact name and location (positional/identity retrieval) instead of using the computer's real strength: search by content or attribute. Library card catalogs show the pattern already worked out physically: the storage system (shelves and call numbers) is separate from the retrieval system (author/subject/title indices), and the index is what does the work of finding.

**Attribute-based retrieval is underused.** Digital systems can index nearly anything about a document (creator, app used, size, edit frequency, print history, last-touch time) essentially for free, yet most software still only supports finding files by remembering their name and folder. An attribute-based system lets a user phrase a search the way they actually think about the thing ("Word docs about Widgetco I edited and printed yesterday"), rather than the way the file system happened to store it.

**Why relational databases fail for open-ended real-world content.** Databases require defining a record's shape and type in advance, and a record belongs to exactly one type. Real information (email, web content) doesn't cooperate: a single email might legitimately belong under five different "categories" (a person, a project, a client, a meeting) at once, and users can't and won't predict their categorization needs ahead of time or stick to them once set. Adding more predefined keyword fields doesn't fix this ("give users 10 fields, someone wants an 11th").

**Digital soup.** The alternative is to decouple storage from retrieval completely: store any record, of any shape, in an undifferentiated store that returns a token per record, then build an unlimited number of independent indices on top (one per topic, person, or project) that just carry copies of the token. Retrieval becomes a query across as many indices as needed, rather than a single predetermined record type or location. Indices can be filled automatically (parsing names, addresses, dates out of content) or manually (user tags ad hoc), and both should be supported. Folksonomies (user-generated tag systems, term credited to Thomas Vander Wal) are the manual half of this in practice: useful especially in social/collaborative contexts where forcing one shared taxonomy on everyone doesn't fit how people actually talk about things.

**Constrained natural-language output.** Full natural-language input parsing is unreliable outside narrow domains and expensive to build. A more tractable middle ground is to have the query interface produce natural-language-like sentences as output: chained dropdowns or underlined phrases that read like an English sentence ("Show items where [attribute] [is/is not] [value]"), where every choice is picked from a bounded, always-valid list. This gives users the readability of natural language and the reliability of structured queries, without needing NLP. The tradeoff: selecting one control can change what's valid in the controls after it (cascading), so the grammar has to be fully mapped in advance, and localization to languages with different word order needs separate grammar mappings.

## Named patterns and principles

- **Data integrity vs. data immunity**: Data integrity blocks anything unclean at the border. Data immunity makes the app smart enough to accept, interpret, and annotate imperfect input instead. Use data immunity as the default posture, reserve hard blocking for cases where bad data causes real, irreversible harm.
- **Audit, don't edit**: "An error may not be your application's fault, but it is its responsibility." Don't stop or silently overwrite a user's suspect input, flag it unobtrusively and keep a reversible record of what happened. Works because it preserves user agency and learning while still protecting against real mistakes.
- **Fudgeability**: Design systems to tolerate the informal workarounds real workflows require (reordering, holding items in suspense, bending a field) instead of forbidding them, backed by detailed action logging so the flexibility doesn't sacrifice accountability.
- **Unified file model**: Present a document as one thing the user owns, never as a disk copy and a memory copy to reconcile. Replace Open, Save, Save As, and Close with goal-level commands (autosave, create a copy, rename, move, discard changes, create a version). Use this instead of implementation-model file dialogs whenever the audience isn't professional file-system users.
- **Positional, identity, and attribute-based (associative) retrieval**: The three ways to find a digital document: remembering where you put it, remembering what you named it, or searching by some inherent property. Positional and identity retrieval are the historical default and scale poorly. Attribute-based retrieval is underbuilt but scales far better because it lets the machine do the remembering.
- **Digital soup**: Store records untyped and unstructured (returning only a lookup token), then layer independent, unlimited indices on top for retrieval, rather than forcing one predefined schema per record. Use when content genuinely resists a single fixed category (email, notes, mixed web content).
- **Folksonomy** (credited to Thomas Vander Wal): a retrieval index built from user-supplied tags rather than a designed taxonomy. Use in social or collaborative tools where imposing one shared vocabulary is impractical or unwelcome.
- **Constrained natural-language output**: A chained-dropdown query builder that reads like an English sentence, each segment chosen from a bounded, contextually valid list. Use as the front end for attribute-based or relational queries when full natural-language input isn't feasible, because it stays both readable and always valid.

## How to apply

- Default to accepting and interpreting imperfect input over rejecting it. Only hard-block when the risk of proceeding is genuinely severe.
- Never let a required-field or format-validation error interrupt the flow with a modal. Use inline, modeless, dismissible cues instead.
- Give data-entry fields the smartest available input tool for the data type: type-ahead or autocomplete for known values, bounded dropdowns for enumerations, smart parsing fields for structured data (phone, address), free text only as a last resort.
- Log and make reversible whatever a user does instead of trying to prevent them from doing it. Assume the user's intent is legitimate until proven catastrophic.
- Eliminate Save, Save As, and Save Changes dialogs where feasible: autosave continuously or on a short idle timer, and reserve manual save controls for power users who explicitly want them, without requiring anyone to use them.
- Give documents one identity users can rename in place (for example, click the title bar) and move, independent of any save action. Don't make renaming require closing the file.
- Separate "specify file type" and "make a copy" or "archive" from the save/close flow. Give them their own explicit commands so a rare action doesn't complicate a common one.
- Build genuine attribute-based search (by content, tag, recency, creator, related entity) rather than relying only on folder position and filename. Treat the folder/location system purely as storage, not as the retrieval mechanism.
- Where content resists one fixed schema (messages, notes, mixed media), design storage as an untyped store plus many independent indices rather than a single relational schema with fixed fields.
- Support both automatic attribute extraction (parse names, dates, addresses out of content) and manual tagging, so users can fill gaps the system can't infer.
- When building any query or filter UI, prefer constrained natural-language output (chained bounded dropdowns reading as a sentence) over exposing raw boolean or SQL-style query syntax to end users.

## Watch out for

- Don't ask users to confirm an action whose answer is overwhelmingly predictable (like "Save changes?"). This is a possibility versus probability confusion: design for the common case and use safety nets (undo, versions) for the rare one.
- Don't let an auto-correcting feature (like AutoFormat or AutoCorrect) silently change user input with no visible trace. When it's wrong, the user has no way to notice or recover, and no learning occurs either.
- Don't repurpose "close without saving" as a substitute for Undo or Revert. If users are doing this, it's a sign a proper session-level undo or revert is missing, not that the close dialog is working as intended.
- Don't bolt file type selection onto the save/close path. Conflating a rare action with a frequent one produces unnecessary confirmation dialogs on ordinary saves.
- Don't assume more predefined keyword or category fields solve unpredictable classification needs. Users will always want one more field than you gave them, a sign the schema itself is the wrong tool.
- Don't build natural-language input parsing for general-purpose commercial use unless the domain and vocabulary are tightly constrained. It's unreliable outside the lab and expensive to build well.
- When building cascading constrained-language controls, plan the full grammar (which choices restrict which downstream choices) up front. Remember word-order differences across languages require separate grammar mappings for localization.
