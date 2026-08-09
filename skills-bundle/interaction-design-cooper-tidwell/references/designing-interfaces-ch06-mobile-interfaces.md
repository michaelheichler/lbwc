# Mobile Interfaces

Source: Designing Interfaces, 3rd Edition (Tidwell, Brewer, Valencia, 2020), Chapter 6, "Mobile Interfaces."

## In one line

Mobile design is not a shrunk-down desktop site, it is a separate discipline built around tiny screens, touch input, distracted users, and unreliable connections, so strip content to its essence and design the interaction sequence, not just the layout.

## Core ideas

- Mobile is often the primary or only way users reach a product, so treat mobile design as core work, not a secondary adaptation. Many users worldwide have no other way to get online.
- Mobile-first (design the mobile experience before the fuller desktop one) or responsive design (one design that scales across screen sizes) are the two dominant strategies. Decide up front whether you need a mobile web version, a native app, a desktop version, or some combination, because each has different constraints and costs.
- Tiny screens force removal, not compression. Cut sidebars, long menus, decorative images, and long link lists. Put the few things users actually need at the top, discard or bury the rest.
- Variable screen widths mean you cannot assume a fixed layout. Content needs to reflow gracefully because you rarely know the exact pixel width in advance.
- Touch screens demand large tappable targets because fingers are imprecise. Minimum touch target guidance: roughly 48x48 dp (about 9mm) on Android, 44x44 pt on iOS, with space between targets. This trades off against how much content fits on screen.
- Typing is the enemy. Reduce or eliminate text entry through autocomplete, prefilled fields, and preferring numeric input over free text where possible.
- Physical context is hostile and unpredictable: bright sun, dark rooms, moving vehicles, noisy or silent-required environments. Design text contrast, audio cues, and hit targets for these worst cases, not for a quiet desk.
- Location awareness is a mobile-only asset. Devices know where they are, so location data can drive what content or defaults are surfaced, and can even support inferring the user's likely situation.
- Users are distracted and often only partially attending to the device, sometimes in social settings (showing a screen to someone else, needing to mute suddenly). Design for quick, resumable, self-explanatory task sequences, not deep-focus workflows.
- Approach mobile design by first asking what users in a mobile context actually need (a quick fact, a few minutes of entertainment, a social connection, an urgent alert, something relevant to their current location), not by porting the desktop feature list.
- After identifying the narrow set of mobile use cases, strip the interface down: minimal branding, no "layer cake" of stacked logos, ads, and headers pushing useful content off-screen. Useful content should appear within roughly the first 100 pixels.
- If you strip a mobile site down, still give users a clear path to the full site, since many users only have the phone and cannot switch to a desktop version.
- Alternatively, build a fully parallel mobile site with everything included, restructuring navigation to be narrower and deeper (fewer links on the home screen, more screens to reach detail) rather than flat and broad.
- Use the device's native hardware (location, camera, voice, gestures, haptics, background multitasking) where it can remove friction, this is capability the desktop does not offer.
- Linearize content into a single vertical flow rather than fighting for side-by-side layouts that don't fit narrow widths.
- Optimize the common task sequences: minimize typing, minimize screen loads (bandwidth is often poor), minimize scrolling and sideways dragging except where it avoids a screen load, and minimize the number of taps to complete a task.

## Named patterns and principles

**Vertical Stack**
What: lay out screen content in a single scrolling vertical column, avoiding side-by-side elements, letting text wrap and the screen scroll past the fold.
When: use for most mobile web screens, especially text and form heavy ones, that must work across device widths. Skip it for immersive full-screen content like video or games that doesn't scroll like text. Favor it more heavily when navigating between screens is costly (web page loads) since it avoids extra downloads, less critical for native apps where screen switching is instant.
Why: screen widths vary unpredictably, and a design that only works at one width forces sideways scrolling or zooming, both less usable than vertical scroll. Line-wrapped vertical content also adapts gracefully to font size changes.
How: put the most important content first, ideally within the first 100 pixels. Never stack logos, ads, and toolbars into a "layer cake" that buries useful content. Put form labels above controls, not beside them, to save horizontal space. Only place buttons side by side if you're certain their combined width will never exceed the screen, especially risky with localized or resizable text. Thumbnails can sit beside text safely down to narrow widths (around 128px).

**Filmstrip**
What: let users navigate by swiping left and right through parallel, full-screen content panels, like a carousel of top-level screens.
When: use for a set of conceptually parallel screens (weather in different cities, scores for different sports) where users are willing to browse through several to find the one they want. Can substitute for toolbars, tabs, or full-screen menus as a navigation scheme.
Why: each screen gets the entire display since no space is spent on nav chrome, and the format encourages serendipitous browsing since users pass through neighboring content on the way to their target. Swiping itself feels satisfying to many users.
How: treat it like a carousel for top-level app screens, but typically without showing metadata or peeking at adjacent screens the way carousels do. Add a dot indicator (as the iPhone Weather app does) to signal that more screens exist and are swipeable. Downsides: it does not scale to many top-level screens (too much swiping annoys users), and it is not discoverable, a first-time user can't tell swiping is the navigation method just by looking.

**Touch Tools**
What: show controls only in response to a tap or key press, as a small, temporary overlay floating above otherwise unobstructed content.
When: use for immersive, full-screen experiences (video, photos, games, maps, books, e-readers) where controls are needed only occasionally but full-screen presentation matters most of the time.
Why: content dominates the experience and isn't fighting persistent chrome for attention, which matters even more given mobile's limited space. The user decides when to summon controls.
How: show the full-screen content unadorned by default. Reveal tools on tap, ideally restricted to a defined touch region so ordinary handling doesn't trigger them accidentally. Render tools in a small, translucent floating panel so they read as ephemeral. Auto-dismiss after a few seconds of inactivity, or immediately if the user taps outside the tool area, waiting passively for them to vanish is annoying.

**Bottom Navigation**
What: place global navigation links at the bottom of the screen rather than the top.
When: use when a mobile site needs global nav links that represent low-priority paths for most users, and the top-of-screen priority is fresh or immediately relevant content.
Why: the top of a mobile home screen is the most valuable real estate, reserve it for content that interests most visitors, not nav chrome. Users can and will scroll to the bottom to find navigation even when it's far below the fold.
How: arrange menu items vertically (or in an easy-to-tap row) at the screen bottom, sized generously for touch, stretched full width if needed. In native apps, keep the footer to a few well-chosen links rather than a full site map, the goal is pushing lower-priority navigation out of premium top space.

**Collections and Cards**
What: present lists of items (articles, videos, products) as thumbnail image plus text, "cards," rather than plain text lists.
When: use for lists of articles, blog posts, videos, apps, or other content-rich items, especially ones with associated imagery, where you want to invite tapping.
Why: thumbnails make text-only lists more appealing, help users identify items faster, and create generous, consistent row heights. Under imperfect mobile reading conditions, visual differentiation via images speeds scanning. This has become the converged standard for how news and content sites present link lists.
How: place a thumbnail (usually on the left) next to the item's text. Layer in other visual markers, such as star ratings or social-presence icons. Don't shy away from bright, saturated color, small screens tolerate visual intensity that would feel garish on a desktop.

**Infinite List**
What: a list that loads more content automatically or on demand as the user scrolls or taps toward the bottom, rather than paginating.
When: use for long, effectively bottomless lists, email, search results, article archives, where users mostly find what they want near the top but occasionally need to dig further.
Why: the initial screen loads fast since only a chunk of items is fetched. Each subsequent chunk load is also fast and user-initiated. Because new items simply append, the user never loses context by navigating to a new page, unlike paginated results.
How: truncate the initial list at a length suited to item size, download speed, and whether the user is reading closely or scanning for one item. Add a "load more" control at the bottom that tells the user roughly how many more items will load, or skip the button and silently prefetch the next chunk once the user nears the end of the current list (only fetch more if they actually scroll that far). This general technique is known in engineering as lazy loading.

**Generous Borders**
What: surround tappable elements (buttons, links, list items) with ample margin and whitespace on touch-screen interfaces.
When: use for any touch target that isn't already large by nature, text buttons, links, list rows.
Why: fingers need targets that are large enough, tall targets especially, to hit reliably, and this must hold up even for users with large fingers, imprecise motor control, or degraded conditions (bad light, a moving vehicle, split attention).
How: add enough inner padding and outer whitespace around each control to create a sufficiently large hit area. A useful trick: make the surrounding whitespace tappable too, so the visible button stays its intended size while the actual hit region is larger. Reference minimums: 48x48 dp (about 9mm) on Android, 44x44 pt on iOS.

**Loading or Progress Indicators**
What: microinteraction animations that signal something is happening or about to appear, covering unspecified or estimated wait times for content or task completion.
When: use whenever the user must wait for content to load or a dynamic screen change to complete, which is common given inconsistent mobile connection speeds.
Why: showing whatever content has already loaded, plus a lightweight indicator for what's still pending, makes wait times feel shorter and reassures the user that their action registered, especially when the indicator appears right at the point of the gesture. Done well it can also reinforce brand personality.
How: render as much of the screen as loads quickly, and place an animated indicator specifically where the slow element (image, video) will eventually appear. When an action triggers a partial or full screen reload, show the indicator in situ, at the point of interaction, not just generically at the top of the screen.

**Richly Connected Apps**
What: hand off data in your app to the native functionality it's naturally associated with (phone numbers to the dialer, addresses to maps, dates to the calendar, emails to the mail app, links to the browser, media to the player) instead of forcing the user to retype or manually context-switch.
When: use whenever your app displays data that is obviously "connectable" to a device capability, phone numbers, addresses, dates, emails, hyperlinks, media, or when you can capture data live via camera, mic, or location.
Why: users can only view one app at a time and manual app-switching is friction. Mobile devices carry enough ambient context (location, contacts, camera) to offer smart shortcuts between apps. Mobile also lacks easy free-form ways to move small pieces of data between apps (no easy copy-paste-everywhere or filesystem the way desktop has), so the app should automate that handoff.
How: track which pieces of your app's data map to another app or system capability. When the user taps or selects that data (or a dedicated affordance you provide), launch the appropriate native app or capability and pass the data through. Typical mappings: phone numbers to dialer, addresses to maps or contacts, dates to calendar, email addresses to mail, links to browser, music/video to media players. You can also invoke camera, map, or location capture inline within your own app's flow rather than leaving it.

Note: this chapter also references two list-presentation patterns detailed elsewhere in the book, Carousel and Thumbnail Grid, as options that work well in mobile designs alongside Infinite List and ordinary text lists.

## How to apply

- Before laying out anything, define the narrow set of mobile-context needs your users actually have (quick fact, brief entertainment, social connection, urgent alert, location-relevant info), and design only for those.
- Default to a single vertical column layout (Vertical Stack) for text and form content, reserve side-by-side layout only for cases you're sure will fit the width.
- Put the single most important thing on screen within roughly the first 100 pixels, no stacked logos, banners, or nav bars ahead of it.
- Size every tappable element to at least the platform touch-target minimum (about 48dp/9mm Android, 44pt iOS) with Generous Borders around it, and never assume precise taps.
- Cut typing wherever possible: autocomplete, prefill, prefer numeric/choice input to free text.
- Choose a top-level navigation approach deliberately: persistent toolbar, tabs, full-screen menu, Filmstrip, or Bottom Navigation, based on how many top-level destinations you have and how discoverable navigation needs to be.
- For long or open-ended lists, default to Infinite List with either a manual "load more" control or unobtrusive auto-fetch near the bottom, never force full pagination reloads.
- For immersive content (video, maps, games, books), hide controls by default and surface them via Touch Tools on tap, auto-dismissing after a few seconds.
- Use content thumbnails (Collections and Cards) for any list of rich items, and don't be afraid of bold color choices that would look too loud on desktop.
- Wire up Richly Connected Apps handoffs for any data your app shows that maps naturally to a device capability (phone, map, calendar, camera, browser, mail).
- Always show a Loading/Progress Indicator anchored at the specific point of user interaction rather than a generic spinner elsewhere on screen.
- Provide a visible path to the full/desktop site if you've stripped the mobile version down, since some users have no other way to reach the full feature set.
- Design explicitly for interruption: quick, reentrant task flows that make sense to someone who is walking, in a conversation, or only half paying attention.

## Watch out for

- Do not just cram the existing desktop layout into a small viewport, that is the core mistake this chapter argues against. Step back and redesign for mobile needs.
- Avoid the "layer cake effect": logos, ads, tabs, and headers stacking up and pushing the content users actually want off the bottom of the screen.
- Filmstrip does not scale to many top-level screens and is not discoverable to first-time users, since nothing signals that swiping is how you navigate. Pair it with a dot indicator and use it only for a small set of parallel destinations.
- Don't let Touch Tools wait too long to auto-dismiss, or trigger on any incidental screen touch, both create annoyance.
- Side-by-side buttons are risky if their text can be localized or resized, total width assumptions can silently break.
- Remember mobile connections and devices are frequently slow, small, and quirky, always design assuming degraded conditions (bad light, motion, low bandwidth, split attention) rather than ideal ones.
