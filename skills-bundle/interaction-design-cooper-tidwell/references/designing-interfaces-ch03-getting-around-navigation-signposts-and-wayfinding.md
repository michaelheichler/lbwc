# Getting Around: Navigation, Signposts, and Wayfinding

Source: Designing Interfaces, 3rd Edition (Tidwell, Brewer, Valencia, O'Reilly 2020), Chapter 3.

## In one line

Navigation exists so users always know what's here, where they are, where they can go, and how to get back, and every jump between screens has a real cognitive and time cost, so keep distances short and signpost every decision point.

## Core ideas

- Navigation answers five questions for the user: what's available here, how is it structured, where am I now, where can I go, where did I come from / how do I back up. Design for all five, not just "how do I click to the next page."
- Signposts vs wayfinding: signposts are the concrete features (titles, tabs, breadcrumbs, progress bars) that mark immediate surroundings. Wayfinding is the user's overall process of finding their way to a goal, informed by good signage, environmental clues (culturally learned conventions like a close "X" in a modal's top right), and mental maps of the whole space. Design for all three: label decision points clearly, follow platform conventions, and give users an escape route back to a known place.
- Every screen or page load has a cognitive cost. The user has to re-perceive the new "room," figure out what it is, and decide what to do. This cost is present even on familiar pages, and it compounds with actual load latency, slow pages lose users before they ever find what they came for. Because of this cost, minimize the number and depth of jumps.
- Keep distances short, three tactics: (1) make global navigation broad and flat rather than deep, so more destinations are reachable at the top level, (2) promote frequently used items into top-level navigation regardless of where they logically sit in the site's hierarchy, (3) bring related steps together onto a single screen instead of forcing users through a chain of subpages, using progressive disclosure, tabs, or accordions to hide the long tail rather than the frequent tasks.
- Separate navigation design from visual design. First decide the structure and sequence of navigational options and what's shown by default, then decide layout and styling. This keeps you flexible and avoids conflating information architecture with skin.
- Navigational models describe the shape of the site graph, choose deliberately rather than by accident:
  - Hub and spoke: a home hub lists all major destinations, user visits a spoke, then returns to the hub. Common on mobile (home screen pattern).
  - Fully connected: every page can reach every other page in one jump via persistent global navigation. Preferred over multilevel when feasible.
  - Multilevel / tree: main pages are fully connected to each other, but subpages only connect within their own branch, so moving between two arbitrary subpages takes two or more jumps. Fat Menus or a Sitemap Footer can convert this into fully connected.
  - Step by step: a prescribed linear sequence (wizard, checkout, onboarding survey) with Back/Next controls.
  - Pyramid: a hub page lists a whole sequence, user can jump to any item then step through neighbors with Back/Next, and return to the hub anytime, see the Pyramid pattern.
  - Pan and zoom: for single large canvases (maps, big images, long documents, timeline media) where panning, zooming, and resetting to a known state are the navigation, not page jumps.
  - Flat navigation: dense tool-based apps (Photoshop, Excel) where the user always knows "where" they are (there's only one canvas) but must locate the right tool among many, driven by menus, toolbars, and palettes rather than page hierarchy.
  - These models mix and match within one product. Full global navigation is not free, it costs screen space and cognitive load, so a temporarily minimal-navigation mode (e.g., full-screen slideshow with just Back/Next and an Escape Hatch) is sometimes the better choice.
- Navigation types by function (not all are named patterns, but route by these terms): global navigation (persistent top/side menus, present on every main screen), utility navigation (sign-in, help, settings, print, language, usually upper right, often collapsed behind an avatar icon), associative/inline navigation (in-content links, e.g., related articles), tags (user- or system-defined, support topical browsing, tag clouds work best at large scale), social navigation (friend activity feeds, trending/leaderboard modules).

## Named patterns and principles

**Clear Entry Points**
What: present just a few prominent, task-oriented "front doors" into the interface, sized and worded for the audience, with a clear call to action.
Use when: many first-time or infrequent visitors need a starting point and don't yet know the terminology or structure.
Why: an unstructured landing screen ("OK, here I am, now what?") stalls new users. A few well-labeled doors give immediate gratification or, at minimum, teach the visitor what the site does.
How: phrase entry points in plain, audience-level language, not internal tool names, size them by importance, and keep ordinary global/utility navigation visually secondary to these doors.

**Menu Page**
What: a page that is essentially a pure table of contents, a list of links to content-rich destinations, with just enough context per link to choose well, and no other major content competing for attention.
Use when: the page's whole job is routing (home page, index, mobile nav screen), your users already know roughly what they want, and you don't need to sell the site's value with promo or teaser content.
Why: no distractions means users can devote full attention to choosing the right destination.
How: label links clearly, add teaser text/thumbnails only if the label alone won't sell the click, reflect the underlying category/hierarchy visually, include a search box, keep it from becoming an overwhelming wall of undifferentiated links (align, group, label).

**Pyramid**
What: a parent (hub) page lists a sequence of child pages. Each child page carries Back/Next plus an Up/Cancel link back to the parent.
Use when: content is naturally sequential (slideshow, wizard, chapters, product set) but some users want to jump in out of order or bail after browsing a few items.
Why: a pure Back/Next chain traps users who change their mind, they'd have to click Back many times or "pogo stick" to the parent repeatedly. Adding the parent link turns two navigation options into three (Back, Next, Up) with little added complexity but much lower cost for casual or non-linear use.
How: render the parent's list format to suit the content type (thumbnail grid, rich text list), give each child a Back/Next plus preview of the next item, and an explicit Up/Cancel. If looping the last item back to the first, be aware users may not realize they've looped, prefer linking last-to-parent if sequence order matters.

**Modal Panel**
What: a focused, single-purpose screen or overlay (often a dimmed lightbox) that blocks other navigation until the user acknowledges it, completes it, or dismisses it.
Use when: a single decision needs the user's full attention, or you need a quick focused detour (e.g., asking for a missing filename) without losing the main task's context, or the app genuinely cannot proceed without input (sign-in, confirmation).
Why: it channels attention onto exactly one decision with no competing paths, but it is inherently disruptive. Reserve it for input that truly can't wait, and if input can be deferred, use an inline "hanging" field instead of blocking everything.
How: keep exits few (1-3), label them with short verb labels ("Save," "Don't save"), include a clear Close/X in the upper right, return the user to their prior context afterward, prefer lightweight web overlays over OS-level modal dialogs (which freeze the whole app and are better suited to native desktop software).

**Deep Links**
What: a URL (or app link) that captures both a location and a state (scroll position, zoom level, filters, sign-in state, search results) so reloading or sharing it recreates exactly what the user saw.
Use when: content has meaningful sub-states (a map location and zoom, a video timestamp, a filtered search) that would otherwise take many steps to reconstruct, and users may want to bookmark or share that exact state.
Why: saves the user rework and enables sharing, a link becomes a "socially mediated object" people can post, embed, or discuss.
How: encode position plus relevant supporting parameters in the URL as the user interacts, keep the browser URL bar updated live, consider an explicit "Link" or "Embed" affordance since not everyone thinks to copy the address bar, and avoid capturing settings a recipient wouldn't want silently overridden (e.g., personal zoom preference). On mobile, configure OS-level deep links so a shared URL opens the native app instead of a browser, preserving richer controls.

**Escape Hatch**
What: a clearly labeled, always-available link or button that returns the user to a known safe place (home, hub, or a self-explanatory page), from any constrained or dead-end screen.
Use when: the user is in a serial process, a modal, a page reached out of normal context (search result, deep link), or a dead end (404, error state).
Why: a way out reduces the feeling of being trapped, and it substitutes for users bailing out entirely (closing the app/tab). It functions like an "undo" for navigation, it encourages exploration because backing out is always possible.
How: place it somewhere conventional (site logo linking home is the most common pattern), or a Cancel button in dialogs. Make sure every dead-end and every constrained-navigation screen has one.

**Fat Menus** (a.k.a. mega-menus)
What: large drop-down or fly-out menus that expose most or all of a category's subpages at once, organized and spread horizontally.
Use when: the site has many pages across a deep or wide category hierarchy and you want casual browsers to discover subpages without drilling down manually.
Why: this is progressive disclosure applied to the whole site map, headings give a quick overview, opening the menu reveals the depth on demand, and it effectively turns a multilevel tree into a fully connected site (any subpage reachable from any page in one jump).
How: organize into titled sections or a natural sort order, use whitespace/headers/dividers for scannability, use full horizontal width, keep visual style consistent with the rest of the site, verify screen-reader/accessibility support (fall back to a Sitemap Footer if it doesn't work), and linearize into a single stacked column for mobile (often better placed on a dedicated nav screen rather than every mobile screen).

**Sitemap Footer**
What: a page-wide footer holding a comprehensive, categorized index of the site's major sections and pages, plus utility links (careers, help, partner sites, contact, promotions).
Use when: the site has more than a handful of pages, you have generous vertical space at the page bottom, and you'd rather not spend header/sidebar space on a deep navigation tree, or Fat Menus raise implementation or accessibility concerns.
Why: like Fat Menus, it exposes many more paths than users would otherwise find and can convert a multilevel tree into a fully connected site. It's simpler to implement (static links, no dynamic fly-outs), easier for screen readers, and doesn't need fine pointer control. Tradeoff: busy or casual users may never scroll down to see it, so validate with usability testing and click metrics.
How: place a full site map (or as complete as practical) in every page's footer, treat it as part of global navigation complementary to the header, let the header stay task-oriented ("what do I do right now") while the footer stays structural ("what is the whole site").

**Sign-In Tools**
What: a cluster of utility navigation for signed-in users (account/profile settings, sign-out, help, shopping cart, notifications, saved items) placed in the upper-right corner.
Use when: the product has a sign-in / account concept at all.
Why: pure convention, users already expect account-related tools in that corner, so meeting the expectation makes the tools findable without explanation.
How: put the user's name and/or avatar there first, keep every tool consistent across all pages, keep the cluster visually modest (utility, not a headline), use recognizable icons where possible (cart, help, messages), and reuse the same corner for a sign-in box/call to action when no one is signed in.

**Progress Indicator**
What: on each step of a linear sequence, a small "map" of all steps with a "you are here" marker.
Use when: the flow is a wizard, written narrative, checkout, or any other page-by-page linear process. If the structure is large and hierarchical rather than linear, prefer Breadcrumbs instead. If step order barely matters, this becomes a Two-Panel Selector.
Why: tells the user how far they've come and how much remains, which supports the decision to continue, an estimate of remaining effort, and orientation. When steps are clickable, it doubles as backward navigation.
How: keep it small (one line or column) near Back/Next controls, visually distinguish current step from visited and unvisited steps, label steps with both number and short title so users know what's ahead and behind.

**Breadcrumbs**
What: a horizontal chain of parent-to-child links showing the current page's position in the site's content hierarchy, from top level down to (often) the current page.
Use when: the structure is hierarchical with two or more levels and users can arrive at any depth via search, filtering, or a deep link, so global navigation alone can't show "you are here."
Why: unlike a Progress Indicator, breadcrumbs are not primarily about "how you got here" (most users didn't drill straight down, they searched or filtered in). They show where you are relative to the rest of the structure right now, so you can navigate sideways or upward from an unfamiliar landing point. They're also clickable, functioning as real navigation, not just a status display.
How: place near the top of the page, list ancestor levels left to right down to the current page, separate levels with a directional glyph (>, /, », arrow), label each with the actual page title, make the current page visually distinct (usually non-clickable) if included.

**Annotated Scroll Bar**
What: a scroll bar enhanced to act as a content map, notification surface, or position ("you are here") indicator, either with static markers (e.g., colored blocks for diffs) or dynamic ones (e.g., a tooltip showing the current page number or heading as the user drags).
Use when: the interface is a long document, code file, spreadsheet, or other pan-and-zoom-style single space where users need to know their position or find specific points (page numbers, headings, search matches) while scrolling.
Why: users' attention is already on the scroll bar while scrolling, and content flies by too fast to read, so putting signposts right there (rather than elsewhere on screen) lets users orient without a second point of focus. When markers appear in the track itself, the scroll bar behaves like a one-dimensional overview-plus-detail view.
How: choose static (unchanging track markers) or dynamic (live tooltip during drag) indicators based on need, base the annotation content on the content's own structure (headings for documents, function names for code, row numbers for spreadsheets), and surface active search-result locations directly on the bar.

**Animated Transition**
What: motion (slides, fades, zooms, bounces) applied to state changes so a transformation reads as continuous rather than an abrupt jump.
Use when: users zoom, pan, rotate, expand/collapse panels, or move between screens or app states, anywhere an instantaneous change would disorient them, or when you want to confirm an input was received or signal an action is in progress.
Why: instant, discontinuous changes (an abrupt zoom, a sudden re-layout after closing a panel) throw off spatial orientation. Letting the eye track a smooth in-between state keeps the user oriented and mimics physical reality, where nothing teleports. Done well it also reads as higher perceived quality and responsiveness.
How: animate only the affected screen region, keep it fast, minimal or no lag before the animation starts, and short (roughly 300ms is a commonly cited target for smooth scrolling), and merge rapid repeated actions (e.g., ten quick key presses) into one combined animation rather than queuing many. Test tolerance with real users, excessive or slow animation reads as motion sickness or sluggishness, not polish.

## How to apply

- Before laying out any screen, decide the navigational model on paper: hub-and-spoke, fully connected, tree, step-by-step, pyramid, pan-and-zoom, or flat. Pick deliberately, don't let it emerge by accident from adding pages over time.
- Audit every major task's happy path and count the jumps from entry to completion. If it takes more clicks than necessary, look first at whether steps can be merged onto one screen (progressive disclosure, tabs, accordions) before accepting a longer flow.
- Promote frequent actions to the top level of navigation even if they logically belong deeper in the hierarchy. Structure should serve frequency of use, not just taxonomy.
- Put a signpost at every decision point: label links so the destination is predictable, and never leave a user staring at an unlabeled fork.
- Give every constrained-navigation surface (modal, wizard step, error page, deep-linked landing page) an Escape Hatch back to a known place.
- Match the "you are here" pattern to the topology: Progress Indicator for linear flows, Breadcrumbs for hierarchical structures, Annotated Scroll Bar for single long documents or canvases.
- When converting a multilevel/tree site toward fully connected, reach for Fat Menus (if screen space and accessibility allow) or a Sitemap Footer (if you want a simpler, static, accessibility-friendly option).
- Reserve Modal Panel for input the flow truly cannot proceed without. For anything deferrable, use an inline, non-blocking prompt instead.
- Keep animated transitions short (roughly 300ms), scoped to the changed region only, and never stack multiple animations for rapid repeated input.

## Watch out for

- Menu Page is easy to overdesign into an overwhelming wall of links, reserve dense pure-menu treatment for reference/index screens and keep frequently visited pages simpler.
- Modal Panel was overused historically, don't reach for it just because it's easy to build, every use should be justified by "the app truly can't proceed" or "this needs full attention right now."
- Breadcrumbs are commonly misexplained as a history trail ("how you got here"), but most users arrive via search or filtering, not top-down drilling. Design them to answer "where am I in the structure," not "what path did I take."
- Fat Menus can break screen readers and other assistive tech, verify accessibility before committing, fall back to Sitemap Footer if needed.
- A Sitemap Footer only helps if users actually scroll to it, validate with usability testing and click metrics rather than assuming it's discovered.
- Full global navigation everywhere is not free, it costs screen space, adds cognitive load, and signals indifference to focus. In deliberately narrow-navigation contexts (full-screen slideshow, focused task), reducing chrome to Back/Next plus an Escape Hatch is often the right call, not a compromise.
- Animated Transition is a double-edged sword: too much, too slow, or applied to the whole window instead of the affected region can cause motion sickness or feel sluggish rather than polished.
