# Organizing the Content: Information Architecture and Application Structure

Source: Designing Interfaces, 3rd Edition (Tidwell, Brewer, Valencia, 2020), Chapter 2.

## In one line

Information architecture is the invisible foundation, built before visual design, that organizes content, tasks, and navigation around the user's own vocabulary and mental model, and it only gets noticed when it fails.

## Core ideas

- **IA is a foundation layer, not decoration.** Think in three layers: the data/IA foundation (concepts, labels, relationships, categories), the middle functionality layer (screens, tools, search, filter), and the top presentation layer (visual design). Do IA work before locking in visual design, because IA decisions shape everything built on top of them. Why: skipping this step locks you into a structure driven by screen aesthetics instead of by how users actually think about the content.

- **Design like an absent customer service rep.** Since you can't be there to guide the user personally, the interface has to anticipate needs, use the customer's own words, offer clear next steps, and confirm task completion on its own. Why: good IA is invisible, users only notice it when it is missing or wrong (confusing terms, can't find things, unclear location in the app).

- **Separate information from presentation.** Work out structure, labels, and workflows in the abstract before touching color, type, or layout. Ask: what information and tools must be shown, when, how are they categorized or ordered, what must users do with them, and how many ways might you need to present them. Why: this keeps you from prematurely committing to one visual solution for what is a structural problem.

- **MECE categorization**: Mutually Exclusive, Collectively Exhaustive. Categories must not overlap confusingly, and together they must cover every piece of content and every use case, with room to add new content later without breaking the scheme. Why: overlapping or incomplete categories create dead ends and confusion, and a scheme that can't grow will need a disruptive rebuild.

- **Six/LATCH ways to organize content**: Alphabetical, Number (integer, ordinal, or by value), Time (chronological, often reverse-chronological, or by frequency or sequence), Location (geographic or spatial, often nested), Hierarchy (parent-child containers), Category or Facet (grouping by shared quality, faceted systems assign multiple category dimensions per item, e.g. Amazon's price, availability, and rating filters). Why: matching the organizing method to the data's natural structure makes browsing and sorting intuitive instead of arbitrary.

- **Task and workflow design rules**: (1) surface frequently used items immediately, hide rarely used ones behind navigation (settings, help). (2) "chunk up" big jobs into a sequence of steps to reduce cognitive load per step, and always show the user where they are in the sequence. (3) design for both novices (extra guidance, onboarding, wizards) and experts (shortcuts, customization, keyboard-only paths) since one interface density rarely serves both well.

- **Design across channels and screen sizes.** Users expect access via desktop, mobile, messaging, voice (no screen at all), and more. This should shape how information is organized, segmented, and sequenced, not bolted on afterward. Cards are a common building block because they scale down to mobile and can be arranged into lists or grids on larger screens.

- **Build a system of screen types.** Give every screen a clear, differentiated job so users learn to predict how a screen works even as its content changes. Theresa Neil's framework of four goal-based screen types anchors this chapter's pattern catalog: Overview (show a list or set), Focus (show one thing), Make (create a thing), Do (facilitate one task). Most products mix these, but each screen should still have one dominant organizing principle.

- **Overview screens** need decisions about dataset size, available space, flat versus hierarchical structure, user-controllable ordering, search or filter or sort tools, and what info or actions attach to each item and when. Common overview idioms: Feature+Search+Browse, Streams and Feeds, Grids or Media Browser.

- **Focus screens** show one thing (article, map, video) and pair well with Mobile Direct Access, Alternative Views, Many Workspaces, and Deep-Linked State (covered in Chapter 3).

- **Make screens** center on Canvas Plus Palette and typically need Many Workspaces so users can work on multiple documents in parallel.

- **Do screens** facilitate a single task. Simple tasks need little IA (a sign-in box), but longer or branched tasks call for a Wizard, while open-ended preference changing calls for a Settings Editor.

## Named patterns and principles

**MECE (Mutually Exclusive, Collectively Exhaustive)**
What: a rule of thumb for category design, no overlap between categories, full coverage of all content and cases.
When: any time you're carving content or functionality into top-level categories or a navigation scheme.
Why: prevents "where does this go" confusion and dead-end gaps, and lets the structure absorb new content later.

**LATCH (Location, Alphabet, Time, Category, Hierarchy)**
What: Richard Saul Wurman's mnemonic for the core ways to organize content (this chapter adds Number as a sixth).
When: whenever deciding how to sort, group, or let users browse or filter a dataset or list.
Why: gives a short checklist of proven organizing schemes instead of reinventing one per project.

**Feature, Search, and Browse**
What: three elements combined on a homepage, a featured item or article or product, a search box (expanded or collapsed), and a browsable list of items or categories.
Use when: your site has long lists of content (articles, products, videos) that need both searching and browsing, or when search or transacting is the primary goal (search becomes dominant, features and browse secondary).
Why: covers both users who know what they want (search) and those browsing openly, while the featured item gives an immediate, low-effort hook to engage new visitors.
How: place search prominently (or collapsed to an icon or label to save space), use Center Stage for the featured item, put a browsable category or topic list nearby, and support "stay found" navigation with Breadcrumbs as users drill into categories.

**Mobile Direct Access**
What: the first screen presents actionable output with zero input from the user, using assumptions from device data (location, time) about the primary use case.
Use when: your app does one thing well and is known for that one thing.
Why: instant value and immediate engagement beat asking the user to configure anything first.
How: pull live location or time data (with permission), assume the most likely intended action, and get the user as close to task completion as possible with minimal input.

**Streams and Feeds**
What: a continuously updated, scrollable list of cards (image, headline, teaser, source) for news, social content, or business collaboration discussion, typically reverse-chronological.
Use when: content updates frequently and users check often (news, social, collaboration tools with async multi-person feedback).
Why: guarantees new content always appears first, rewarding repeat visits, supports quick "microbreak" checking, and lets asynchronous, distributed collaborators (e.g. remote teams) stay in sync.
How: list newest first, let users refresh or scroll to older items, offer curated or custom streams for advanced users, show what, who, when, and where per item, provide a "More" link for long items, enable low-effort responses (like, star) alongside full replies. Business chat tools (e.g. Slack-style) flip the order, newest at the bottom.

**Media Browser** (the chapter's pattern list also calls this "Thumbnail Grid")
What: a grid-of-objects structure for browsing and selecting from a collection, using thumbnails plus a single-item detail view.
Use when: users need to browse and select from many media items or documents (photos, videos, files) for viewing or editing.
Why: an instantly recognizable style, users immediately understand they can browse, click to view, or manage a collection.
How: build two coordinated views, the grid or matrix and the large single-item view. Provide a browsing interface (search, filters, sort by date or label or rating). Support keyboard navigation and multi-select (shift-select, checkboxes) if items can be reordered or deleted. Put editing tools and previous or next navigation in the single-item view.

**Dashboard**
What: an information-dense single page showing key data points, charts, messages, and actionable links, updated regularly, typically the first screen after login for business platforms.
Use when: users need a quick status check across an incoming flow of data (metrics, financials, operational data) that they must monitor continuously.
Why: dashboards are a familiar, well-understood page style, so users already expect self-updating status info presented graphically.
How: aggressively edit down to what matters (an editor's eye, not just a data dump), use strong visual hierarchy, keep it on one page with minimal scrolling, group into Titled Sections, prefer simple line or bar charts over decorative gauges or 3D charts, use One-Window Drilldown for details and Datatips for point-level info, consider offering user customization (movable panels).

**Canvas Plus Palette**
What: a central blank workspace (the canvas) surrounded by grids of iconic tools (palettes) that the user applies to create or edit objects on the canvas.
Use when: designing any graphical editor (image, vector, prototyping tools).
Why: a familiar mental model (a workbench or artist's easel), and icon reuse across apps (paintbrush, hand, magnifying glass) draws on existing visual recognition.
How: give the canvas its own clear space, place the palette as an icon grid (with text labels if icons are ambiguous) to the side or top, group palette subsections with Module Tabs or Collapsible Panels, and usability-test the creation gestures (click, drag-and-drop, pressure-sensitive input) since they aren't always obvious.

**Wizard**
What: a component that walks the user through a task step by step in a prescribed order.
Use when: the task is long, complicated, and likely novel for the user (not a frequent task they want fine control over), and you (the designer) know the task structure better than the user does.
Why: divide-and-conquer, breaking the task into digestible chunks removes the burden of figuring out the task's overall structure. But it backfires for expert users, creative work, or anyone who wants to learn the underlying system, since a Wizard hides what's changing in the application state.
How: chunk the task into a sequence of groups (thematic if order doesn't matter, decision-point-based if later steps depend on earlier choices), balance chunk size against step count (too few steps feels pointless, too many feels tedious), allow back and forward navigation, consider a step-overview map, and use Good Defaults and Smart Prefills. For same-page alternatives, use Titled Sections (numbered, for lightly branched tasks), Responsive Enabling (steps stay visible but disabled until ready), or Progressive Disclosure (reveal each step only when the prior one is done, often the most elegant compact option).

**Settings Editor**
What: a self-contained page or window (often split into tabs or pages) where users view and change settings, preferences, or properties in any order (random access).
Use when: building an app with app-wide preferences, an OS or platform with system settings, a signed-in product needing account or profile editing, a complex-document tool with per-object properties, or a product configurator.
Why: unlike a Wizard, users need to jump directly to one setting without walking a sequence, and they also use it just to view current values, not only to change them.
How: put it in the platform's conventional location, group properties into well-labeled categories (card-sorting exercises help find the right categories and names), choose a layout (Tabs, Two-Panel Selector, or One-Window Drilldown with a menu page), and decide whether changes apply immediately or need Save and Cancel based on platform convention and settings type.

**Alternative Views**
What: substantially different ways of viewing or editing the same underlying content or data.
Use when: conflicting design requirements can't be reconciled in one view (e.g. print versus screen, structural editing view versus end-user preview, map view versus list view), or users have differing style or performance preferences.
Why: no single view can serve every scenario, so design each specialized view separately and let users switch.
How: pick a handful of scenarios the default view can't serve well, design a targeted view for each, keep core content stable across views while adding or removing supporting detail, place a switch control (it doesn't need to be prominent) and preserve session state (selections, undo history) across switches, and consider remembering the user's last-chosen view.

**Many Workspaces**
What: an interface letting users view or work on more than one page, project, file, or context simultaneously, via tabs, separate windows, panels, or split views.
Use when: users need multiple task "modes" open at once (browser tabs, code editor plus output, multiple documents, multiple monitored social feeds).
Why: supports natural multitasking (switching tasks and returning later), enables side-by-side comparison, and connects to Prospective Memory (leaving a window open as a reminder) and Safe Exploration (no cost to opening another workspace).
How: choose from tabs, separate OS windows, panels or columns, or adjustable split windows depending on content complexity. Consider auto-restoring the workspace set after a crash or restart as a courtesy to users.

**Help Systems**
What: a spectrum of assistance mechanisms, from inline copy and tool tips up through full documentation, guided tours, knowledge bases, and online communities.
Use when: always, in some form. Every product needs some level of help, and complex or unfamiliar tools need multiple, layered forms of it.
Why: users differ enormously in commitment level and learning style (some want a video, some find tool tips annoying), so a single help mechanism can't reach everyone. Layered options each reach a different segment without overwhelming the rest.
How: build up from lightweight to heavyweight along a continuum, on-page instructions and labels, prompt or example text in form fields, brief tool tips (short hover delay reduces irritation, essential for icon-only controls), Hover Tools for longer explanations, Collapsible Panels for longer text, guided tours or onboarding videos for first-time orientation (with an opt-out), full separate help documentation or manual, live technical support, and an online community for heavily invested user bases. Match the technique to the platform: tool tips need adaptation for touch (tap instead of hover) since mobile has no hover state.

**Tags**
What: descriptive labels or metadata attached to content (often user-generated) that create a topic-based faceted classification and navigation system, commonly rendered as clickable hashtags.
Use when: you want to exploit users' desire to classify, browse, and share content by topic, and when your content volume is large enough that a crowd-sourced organization layer adds real value (news publishers, social platforms, discussion boards).
Why: tags increase engagement (users find more relevant content, and self-tagging invests users further in the platform) and let a topic-navigation structure emerge organically at a fraction of the cost of building it top-down.
How: allow words to be attached to content as tags, make tags clickable links that generate a results page of same-tagged content, and support search across tagged content by keyword.

## How to apply

- Do information architecture before locking in visual design. Map content, categories, workflows, and labels in the abstract first.
- Check every top-level category scheme against MECE: no overlaps, no gaps, room to grow.
- Pick organizing methods (alphabet, number, time, location, hierarchy, category or facet) based on what's natural for the specific dataset, not by default habit.
- Put frequent actions front and center, bury the rare ones behind navigation.
- Break long or complex tasks into clearly sequenced, appropriately sized chunks, and always show progress or position.
- Design explicitly for both first-time and expert users, extra guidance for one, shortcuts and density for the other.
- Decide, per major screen, whether its job is Overview, Focus, Make, or Do, and let that decide its organizing pattern.
- Match a named pattern to its "use when" trigger rather than picking one because it looks familiar. Use Wizard only for long, branched, novel tasks users are willing to surrender control over. Use Settings Editor for random-access property editing. Use Alternative Views only when one view genuinely cannot serve conflicting requirements.
- Layer help from lightweight (labels, prompts, tool tips) to heavyweight (manuals, guided tours, community) rather than picking just one mechanism.
- Consider tags as a low-cost, user-driven way to add a secondary, topic-based navigation layer on top of your designed IA.

## Watch out for

- A Wizard can feel patronizing to users, and needing one at all may signal the task is too complicated. If a short form can replace it, prefer the short form.
- Wizards frustrate expert users and anyone doing creative work, and they hide from users what state their actions changed.
- Don't confuse Settings Editor with Wizard: Settings Editor requires random access and viewing of existing values, not a forced sequence.
- Tool tips hide whatever is underneath them and can annoy users if shown instantly, use a short hover delay.
- Hover-based help (tool tips, hover tools) does not translate directly to mobile, which has no hover state, redesign as tap-triggered on touch devices.
- Guided tours and onboarding overlays should be dismissible, and once dismissed, still reachable again elsewhere for users who want to revisit them.
- Losing session state (selections, undo history, current position) when a user switches Alternative Views will surprise and frustrate them, preserve it.
- Break platform conventions for Settings Editor location and behavior at your own peril, experienced users have strong expectations here.
