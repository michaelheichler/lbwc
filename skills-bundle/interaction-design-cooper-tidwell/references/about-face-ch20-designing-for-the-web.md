# Designing for the Web

Source: About Face: The Essentials of Interaction Design, 4th Edition (Cooper, Reimann, Cronin, Noessel, 2014), Chapter 20, "Designing for the Web."

## In one line

The web is organized around pages and hyperlinks rather than persistent screens, so navigation, scrolling, search, and responsive layout carry the interaction design weight that panes and toolbars carry in native software.

## Core ideas

- The page is the atomic unit of the web, not the screen or view. Native apps offer a small set of persistent modes or spaces where content changes underneath fixed chrome. The web instead gives almost every piece of content its own address (URL), so the central design problem becomes helping people find and move between pages rather than switching modes within one. Any designer who moves between native and web work should notice this difference deliberately, because it changes what "navigation" even means.
- Because content lives across many separate pages, organizing that content is its own discipline (information architecture), distinct from visual design and from interaction design. An agent building a web product needs both: a sound content structure and the interaction patterns that let people traverse it.
- Search matters more on the web than in most native software because the page model produces so much content to sift through. Most people are weak at composing search queries, so the burden is on the system to bridge from an imprecise query to the right page, not on the user to phrase things well.
- Scrolling is normal and expected on the web in a way it usually is not for persistent native app chrome. Toolbars and key controls scroll away by default unless a designer pins them, whereas in native apps the same behavior would surprise and annoy users. Touch input and modern trackpads have made scrolling itself feel natural, further encouraging long, single scrolling pages over paginated content.
- Responsive design exists because screen size (and other device factors like touch input and lighting) varies enormously across web contexts, and a single flexible layout is usually preferable to maintaining multiple discrete versions, even though it costs more design and engineering effort per breakpoint.
- The header and footer are structurally special because of scrolling: the header is the first (and sometimes only) thing seen on load, and the footer is a reward zone reached only by users who scrolled through everything else, making it a good spot for "what to do next" and rarely used links.
- Infinite scroll and pagination solve different problems. Infinite scroll suits streams where older items quickly lose relevance and the point is browsing what's recent (news feeds, social streams). Paginated results suit any case where users need to jump to a specific position, return to a specific item, or reach the end deliberately, because infinite scroll breaks predictable navigation to a location and often breaks browser back/forward state.

## Named patterns and principles

- **Primary navigation**: the persistent links (top or side) that expose the major sections of a site or app. Top navigation is usually superior because its limited space forces short, clear labels and a small number of top-level sections, a constraint that improves comprehension. Side (left) navigation trades that discipline for capacity: use it when you have a large, heterogeneous content space where forcing everything into a short horizontal bar would produce vague, catch-all labels. Left-aligned items are also easier to scan quickly.
- **Fat navigation**: a secondary-navigation technique where hovering or clicking a primary nav item expands a much larger temporary panel of sub-section links. Effective because it builds on an interaction the user is already making with primary nav, and because its modal, temporary nature lets it use generous space without permanently cluttering the page.
- **Breadcrumbs**: a trail of links showing the user's path through the site hierarchy, reinforcing their mental model of where they are. "Breadcrumbs with lateral links help speed navigation," meaning breadcrumb steps that open a menu of sibling pages let users jump sideways in the hierarchy, not just upward, cutting the number of clicks needed.
- **Auto-complete (type-ahead)**: as the user types a query, the system offers likely complete search terms, drawn from prior searches or from live results. Raises the odds the submitted query actually returns a meaningful result set, compensating for weak natural query-forming skills.
- **Auto-suggest (disambiguation)**: when a typed term is a near-miss for a more common term, the system offers corrected alternatives alongside results (in effect, autocorrecting spelling in the search box). Recovers users who mistyped or misremembered the term they wanted.
- **Faceted search**: lets users narrow a large result set by selecting specific attributes of the item they want, and shows them the characteristics of the current set so they can see how to shrink it further. Useful because forming one perfect query up front is hard, but successively filtering by known attributes is easy and reliable.
- **Categorized suggestions**: search suggestions that each scope the query to a particular content category, useful when the same term could mean different things across an app's different content domains (a retail site's departments, for example).
- **Responsive design**: a single layout that reflows at defined breakpoints (screen-width thresholds where the grid changes more substantially, for example collapsing side-by-side content into a stack) rather than maintaining separate site versions per device. Chosen for the sake of one shared design and engineering framework, at the cost of a single, more complex UI to build and one more layout to design per breakpoint.
- **Separate mobile site/app**: an alternative to responsive design when screen size is not the only mobile concern, when touch input, other device sensors, or difficult lighting conditions (like outdoor sunlight) also need distinct handling that a single reflowing layout cannot address well.
- **Infinite scrolling**: continuously appending more results to the bottom of the page as the user scrolls, instead of paginating. Feels natural if latency stays low, but is unsuitable whenever users need to reach a specific position quickly, return to a specific item after navigating away, or rely on keyboard/screen-reader navigation, since these all tend to break under infinite scroll.

Boxed callout guidelines quoted from the chapter (each a short, one-sentence rule the book calls out for emphasis):

- "Use persistent headers to maintain context." (docking the top nav bar, often shrunk, as the user scrolls down a long page)
- "Auto-complete, auto-suggest, and faceted search help users find things faster."
- "Make scrolling an engaging experience."
- "Infinite scroll and site footers are mutually exclusive idioms." (a user who never reaches the bottom of an infinite-scroll page never sees the footer, so do not rely on the footer for anything essential if you use infinite scroll)
- "If you have only one version of your site, make it responsive."

## How to apply

- Default to top navigation with a short list of clearly named top-level sections. Reach for left-side navigation only when the content space is large and heterogeneous enough that compressing it into a horizontal bar would force vague labels.
- Keep the navigation hierarchy as flat as practical. Assume most users struggle beyond two or three levels deep and lean on a strong search function and breadcrumbs rather than deep nested menus.
- Provide constant "you are here" feedback through active-state styling in nav elements and breadcrumbs, especially for anything more than a couple of levels deep.
- On mobile widths, collapse persistent navigation into a menu control (the "hamburger" pattern), but consider labeling it "menu" as well as or instead of the icon alone, since not all users reliably decode the icon.
- Build search assuming users will type imprecise or partial queries. Layer auto-complete, auto-suggest for likely misspellings, and faceted filtering so the system, not the user, does the work of narrowing a fuzzy query to a useful result set.
- Design scrolling pages deliberately: establish a clear visual rhythm with generous whitespace and type sizing, and give users cues about where they are on a long page (a docked, progressively shrinking header, section markers, or a progress indicator).
- Use pagination, not infinite scroll, whenever users may need to reach a specific item, return to one after navigating away, or use keyboard/assistive-technology navigation.
- Reserve infinite scroll for feeds where recency dominates and browsing (not retrieving a specific past item) is the primary task.
- Treat the footer as a deliberate landing spot for "what's next" suggestions and low-frequency links (legal, full sitemap), but only if your navigation pattern actually lets users reach it.
- Choose responsive design as the default for a single site serving many screen sizes. Consider a genuinely separate mobile experience only when touch input, sensors, or environmental factors (like sunlight glare) matter as much as screen width.

## Watch out for

- Do not assume a hamburger icon alone is universally understood. At least one credible study found the word "menu" outperforms the icon for some users.
- Do not paginate content purely to inflate ad-view counts. If the underlying content is a single finite unit, splitting it across pages mainly frustrates users trying to find, save, or print it. Pagination is justified for long lists of similar discrete items (search results, article listings), not for a single continuous piece of content.
- Do not combine infinite scroll with a footer that carries anything essential. Since infinite scroll pages have no true bottom in practice, footer content there becomes effectively unreachable for most users.
- Do not deploy infinite scroll where users need reliable back/forward browser behavior or need to relocate a specific item they saw earlier. Scroll position after using back/forward is often not preserved well, forcing users to re-scroll and re-hunt.
- Do not assume search relieves you of good navigation design. Even Google-trained user behavior does not mean people have abandoned or no longer need navigation, and most people remain weak at forming precise queries regardless of how much they search.
- Do not treat responsive design as automatically the right (or free) choice. It centralizes the team's design framework but adds real complexity, since each breakpoint is effectively an additional layout to design and build.
