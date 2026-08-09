# Lists of Things

Source: Designing Interfaces: Patterns for Effective Interaction Design, 3rd Edition (Jenifer Tidwell, Charles Brewer, Aynne Valencia, 2020), Chapter 7, "Lists of Things."

## In one line

Almost every screen is a list of something, so decide the list's use case, information architecture, and detail-display strategy before picking a visual pattern.

## Core ideas

- Lists show up everywhere (articles, photos, messages, products, files, people). Treat "how to show a list" as a recurring design decision, not a one-off, because the same reasoning applies across wildly different content types.
- Before designing, name the use cases the list must serve. Different use cases pull the design in different directions, so pick a pattern only after you know which of these apply:
  - Getting an overview: can the user skim the whole list and understand it at a glance, sometimes needing images or layout, not just words.
  - Browsing item by item: does the user move through items in order, and can they get back to the list or the next item easily.
  - Searching for a specific item: can they find one item fast with minimal scrolling or backtracking.
  - Sorting and filtering: do they need to narrow by a property or get insight into the set.
  - Rearranging, adding, deleting, recategorizing: does the user own the collection, needing drag-to-reorder or multi-select (platform standard multi-select, or checkboxes for arbitrary selection).
- Analyze the list's information architecture independent of visuals, the same nonvisual traits shape which pattern will work:
  - Length: does it fit on screen, or is it effectively bottomless (search results, deep archives).
  - Order: does it have a natural order (alphabetical, chronological), should the user be able to resort it, and would a grouping scheme actually serve better than a flat order (or vice versa). Example: a time-ordered flat list can beat a monthly-grouped archive when users remember relative position ("before X, after Y") rather than the exact month.
  - Grouping: are there natural categories, do they nest into a hierarchy, are there multiple valid categorization schemes for different personas, can users define their own categories.
  - Item types: are items simple or rich, homogeneous or mixed, image-bearing, and do they have a strict sortable field structure (like timestamp/from/subject in email) worth exposing.
  - Interaction: show the full item or just a representation, what does the user do with items (view, select, act on, follow as a link), and is multi-select needed.
  - Dynamic behavior: how long does the list take to load, and does it update live (e.g., new items inserted at the top).
- A recurring design question is: when a user selects an item, where do the details appear? The chapter frames three answers as a spectrum (Two-Panel Selector, One-Window Drilldown, List Inlay), chosen by available space and how often users compare or hop between items.
- For long lists, loading strategy and interaction design are separate problems: Pagination, Infinite List, Continuous Scrolling, and Alpha/Numeric Scroller solve "how does the user get through it," independent of how each item is rendered.
- Structural equivalences worth remembering (choose based on space and existing conventions, not novelty): Two-Panel Selector behaves like tabs, List Inlay behaves like an Accordion, One-Window Drilldown behaves like a Menu Screen.

## Named patterns and principles

**Two-Panel Selector (Split View)**
What: Two side-by-side panels, list on one side, selected item's details on the other.
When: List items carry substantial content (email body, article, image, folder contents), the user needs the list visible at all times while browsing, only one item's content needs viewing at once, and the screen is wide enough for two panels (not small phones, but larger devices work).
Why: A learned but powerful convention. Keeping both panels visible cuts physical effort (no window switch, one click or key press to change selection), cuts cognitive load (no full context switch, small changed region), reduces memory burden (the list stays as a "you are here" signpost), and is faster than reloading a screen per item.
How: Put the list top or left, details below or to the right (mirror for right-to-left readers). Select with a single click, also support arrow-key navigation. Make the selected row visually distinct (toolkit selection styling, or a clear color/brightness difference). Let list layout follow the content's natural structure (hierarchy tree for files, timeline for video editors, canvas for GUI builders).

**One-Window Drilldown**
What: A single screen shows the list, selecting an item replaces the whole screen with that item's details.
When: Constrained space (mobile) where a Two-Panel Selector cannot fit, or when both list and item content need the entire screen (forums with wide topic lists and long scrollable threads).
Why: In tight space it is often the only option, and it gives each view full room to breathe. The shallow one-level hierarchy keeps users from getting lost and makes returning to the list simple.
How: Build the list in any layout (text, cards, rows, tree), scroll it if needed. On selection, replace the list with item details and provide a clear Back/Cancel affordance. Allow further drilldown or "previous/next item" links from the item screen to ease the pogo-stick effect of hopping between list and item repeatedly, since that hopping is this pattern's core weakness (no quick flicking or side-by-side comparison).

**List Inlay**
What: Rows in a column expand in place to show item details when selected, independently openable and closable.
When: Item details are non-trivial but not huge, the list is a single vertical column (not a grid), the user needs the surrounding list visible while viewing details, and users may want two or more items' details open at once for comparison.
Why: Keeps items in their list context, and uniquely among these three patterns lets the user view multiple items' details simultaneously. Combines cleanly with a Two-Panel Selector to build a three-level hierarchy (e.g., mailbox picker next to a message list that itself uses inlay expansion).
How: Clicking a row expands it downward, pushing later rows down, inside a scrollable container (the column can grow long). Put the close control near the open control (ideally near the top of an expanded panel too, not just the bottom) so the pointer does not have to travel far. Animate the open/close transition to keep the user oriented. Can host an editor instead of, or alongside, read-only details. Attributed to Bill Scott and Theresa Neil's "Designing Web Interfaces" (2009), part of a family that also includes Dialog Inlays and Detail Inlays.

**Cards**
What: Self-contained UI components bundling image, text, and sometimes actions into one visually consistent unit.
When: Showing a heterogeneous list of items that all share the same behaviors (image, text, favorite/share, link to detail), especially when items vary in size or aspect ratio and the layout must be responsive.
Why: A now-familiar convention across mobile and web, flexible enough to reflow across viewport sizes and screen types.
How: Identify what every item has in common (image, title, description, rating) and what action every item supports (link out, add to cart, share). Mock up the card using the item with the most content and the item with the least, then tweak until both read cleanly. Decide icon vs. text-label actions, and test with real photos to pick portrait vs. landscape orientation.

**Thumbnail Grid**
What: A 2D "small multiples" grid of similarly sized images, a specialized case of Grid of Equals (Chapter 4).
When: Items have small, visually distinguishing representations (photos, logos, screenshots) of similar size and style, the list can run long (optionally split into Titled Sections), only light metadata is needed per item, users want a scannable overview and the ability to multi-select for move/delete/view.
Why: Dense and visually strong, draws the eye, and images are often easier to tell apart at a glance than text labels. Roughly square thumbnails make good touch and pointer targets, suiting mobile and tablet.
How: Scale thumbnails to a consistent size, keep metadata small and secondary to the image. When source images vary in aspect ratio, crop toward a common shape carefully (preserve the meaningful part of the image), unless the size/orientation itself is meaningful information the user needs (e.g., personal photos where portrait vs. landscape matters), in which case do not force-crop.

**Carousel**
What: A horizontal (or arced) strip of visual items that the user scrolls or swipes through, one screen-width or so at a time.
When: Items have unique, similarly sized/styled visuals, the list is flat (no categories), items are casually browsed rather than searched for, order can be curated (most interesting first, or chronological), and there is not enough vertical space for a Thumbnail Grid.
Why: Encourages serendipitous browsing since users cannot jump deep into the list, only scroll through it. Uses less vertical space than a grid, and can deliver "focus plus context" if the design enlarges a central item while keeping neighbors visible.
How: Build thumbnails as in Thumbnail Grid, but hold sizing and aspect ratio even more strictly consistent, mismatched thumbnails look worse in a Carousel than in a grid. Show fewer than 10 at once, hide the rest to the sides, provide left/right paging arrows that move more than one item per click, animate the scroll. If users frequently want to jump deep in the list (evidenced by heavy scrollbar use), that is a signal to add a scrollbar plus a proper find/search, or reconsider a vertical list instead. Enlarging the central item gives single-selection semantics for driving details or controls elsewhere on screen. The mobile Filmstrip pattern is a one-item-at-a-time variant.

**Pagination**
What: Split a long list into discrete pages, loaded one at a time via navigation controls.
When: The list may run long, users usually want only the first page or a specific item (not the whole set), and loading or rendering everything at once is too slow, or the list is bottomless and Infinite List/continuous scrolling is not feasible.
Why: Breaks content into digestible chunks and puts "load more" in the user's control. Cheap to implement and a widely recognized web convention, especially for search results.
How: Choose items-per-page based on item size, likely screen sizes (including mobile), load time, and the odds the desired item is on page one, and treat page one as must-succeed since most users will not go further (make sure top search results are high quality). For lingering use cases (product or video browsing) consider letting users set items-per-page. Place pagination controls at both top and bottom for long screens. Include Previous/Next (disabled at the ends), a persistent link to page one, a numbered sequence with the current page shown unlinked in contrasting style ("you are here"), ellipses to truncate beyond roughly 20 visible page links (always keep first, last if known, and pages adjacent to the current one), and optionally a total page count.

**Jump to Item**
What: Typing a name or value in a sorted list jumps the selection straight to the matching item.
When: A scrolling list, table, drop-down, combo box, or tree holds a long alphabetically or numerically sorted set, and the user wants to pick one item quickly, ideally without leaving the keyboard.
Why: Computers scan long sorted lists far better than people do, use that strength. Keeping the user's hands on the keyboard (typing a few characters instead of scrolling and clicking) speeds up form and dialog completion.
How: On each keystroke, jump to and select the first exact match to what has been typed so far, auto-scrolling it into view. If no match exists, hold position at the nearest match rather than resetting to the top, optionally beep to signal no match. (Spotify's incremental search-as-you-type, surfacing likely results before the full query is typed, is cited as a related variant.)

**Alpha/Numeric Scroller**
What: Letters, numbers, or a timeline displayed along a list's scrollbar, clicking one jumps the list to that point.
When: Users need to find specific items fast in a long scrolled list, table, or tree, typically alphabetized or date-ordered.
Why: Acts as an interactive map of the list's contents, similar to an Annotated Scroll Bar, and is closely related to Jump to Item in that both allow immediate jumps to a point in an ordered list. Echoes the physical convention of tabbed dictionaries and address books.
How: Put the long list in a scrolled container, show alphabet letters (or dates) along the scrollbar, and scroll to the matching point on click.

**New-Item Row**
What: A dedicated first or last row in a list or table that, when activated, creates a new item in place for immediate editing.
When: The UI presents a table, list, or tree (one item per row) that users need to add to, screen space for a separate creation UI is limited, and item creation should be fast and explicit about the type of thing being added.
Why: Creating an item exactly where it will live is conceptually coherent and avoids a separate creation UI, saving screen space and eliminating a navigation jump for the user.
How: Make the empty row's activation obvious (a click starts editing, or a "New X" button). Make every column in that row editable inline (text fields, dropdowns), and prefill sensible values via Good Defaults (Chapter 10) so the user need not touch every field. Decide up front what happens if the user abandons a new item mid-edit, a safe approach is to instantiate a valid item immediately so it just sits there, editable, until explicitly deleted. Structurally similar to the Input Prompt pattern (Chapter 10): a dummy value doubles as an instructional placeholder.

## How to apply

- Before choosing a list pattern, write down which use cases apply (overview, browse, search, sort/filter, rearrange) and answer the information-architecture questions (length, order, grouping, item type, interaction, dynamic behavior). Let the answers drive pattern choice, not aesthetics first.
- Decide the item-detail display strategy (Two-Panel Selector vs. One-Window Drilldown vs. List Inlay) based on available screen width and whether users need to compare multiple items at once, not by default habit.
- For image-heavy lists, pick Cards, Thumbnail Grid, or Carousel based on space (vertical room favors a grid, tight vertical space favors a Carousel) and whether items are homogeneous (grid/carousel) or need per-item flexible actions (cards).
- For long or bottomless lists, separate the loading-strategy decision (Pagination vs. Infinite List vs. Continuous Scrolling) from the item-rendering decision, they compose independently.
- Add Jump to Item and/or an Alpha/Numeric Scroller whenever a sorted list is long enough that scanning by eye becomes a chore.
- When users must create new list items in a data-management view, prefer New-Item Row over a separate creation dialog if screen space is tight and the creation flow is simple.
- Reuse the pattern-equivalence shortcuts: think of Two-Panel Selector as tabs, List Inlay as an Accordion, One-Window Drilldown as a Menu Screen, when deciding how a chosen pattern should behave.

## Watch out for

- Do not force a grouping scheme onto data that actually reads better as a flat ordered list, and vice versa, test against how users actually recall position (e.g., "before X, after Y" beats "which month").
- Two-Panel Selector fails on small phone screens, do not try to cram it in, fall back to One-Window Drilldown.
- One-Window Drilldown's biggest weakness is the "pogo-stick" effect between list and detail screens, mitigate with Back/Next links rather than accepting the friction.
- List Inlay's expanding column can grow tall fast, contain it in a scrollable area, and place a close control near the top of long panels, not only at the bottom.
- Thumbnail Grid cropping can destroy meaningful information, do not force-crop images whose aspect ratio itself matters to the user (e.g., personal photo orientation), but do standardize aspect ratio for uniform content like product photography.
- Carousels only support linear scrolling, if analytics show users scrubbing back and forth a lot trying to find something specific, that is a signal the format is wrong, consider a searchable vertical list instead of tacking on more Carousel affordances.
- In Pagination, page one carries outsized importance, most users never go past it, so weak first-page results (especially in search) will silently lose users rather than prompt them to page forward.
- For New-Item Row, plan explicitly for the abandoned-edit case, decide whether a partially filled item persists or gets discarded, do not leave that behavior undefined.
