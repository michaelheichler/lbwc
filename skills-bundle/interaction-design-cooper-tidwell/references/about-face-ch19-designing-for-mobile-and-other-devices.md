# Designing for Mobile and Other Devices

Source: About Face: The Essentials of Interaction Design, 4th Edition (Cooper, Reimann, Cronin, Noessel, 2014), Chapter 19.

## In one line

Mobile and embedded interfaces are not shrunken desktop software, they demand transient posture, finger-scale controls, context-driven behavior, and a small vocabulary of well-known gestures and layout idioms tuned to each form factor.

## Core ideas

**Mobile apps are transient, not sovereign.** Desktop apps tend toward sovereign posture (see Chapter 9), but most mobile apps are used in brief, intermittent, task-focused bursts, even though they occupy the whole screen. Design for quick entry, a fast task, and a quick exit, not for a persistent workspace. Games are the main exception.

**Screen and touch constraints force dialog-like density.** Finger-sized hit targets and narrow screens mean the amount of content and controls per screen resembles a desktop dialog box more than a full application. Zooming to fit more in is not a good substitute, it adds complexity and conflicts with the zoom gesture that many platforms already use for switching between apps.

**Form factor changes the right structural pattern.** Handhelds (4 to 6 inch, mostly portrait, tall narrow screens), tablets (9 to 10 inch, more breathing room), and mini-tablets (7 to 8 inch, narrow aspect ratio in both orientations) each call for different layout choices. What works as an overlay on a handheld may need to become a permanent adjacent pane on a tablet. Mini-tablets are a genuine third category, not just a small tablet or big phone, because they have neither the room of a full tablet nor the forgiving proportions of a phone.

**Full-screen apps beat window management on small devices.** Since the earliest handheld touchscreens (Newton, PalmPilot), abandoning desktop-style window management for one full-screen app at a time has made better use of limited real estate. This holds even as resolutions have grown.

**Orientation should follow the content, not be supported for its own sake.** Portrait suits one-handed list and grid browsing, since most people hold a phone one-handed in portrait. Landscape suits content whose medium is naturally landscape, like photo or video capture. Apps with complex, fixed control layouts (streaming video, e-readers, authoring tools) often do better locking to one orientation and treating the other as an opportunity for a genuinely different layout, rather than mechanically reflowing the same one.

**Don't port your desktop app onto a tablet.** The high resolution of tablet screens tempts designers to shrink desktop layouts onto touch. For browse, search, view, or purchase apps this is a mistake, but for productivity and creative authoring apps that are genuinely trying to replace a desktop tool (audio or video production, painting), a more desktop-like set of tool bars, panes, and drag-and-drop can be justified because the task complexity demands it.

**Hardware-like controls can work on touch where they failed on desktop.** A mouse operating a virtual knob is awkward, a finger operating one directly is natural. This changes the calculus for music-production-style interfaces. Still support drag gestures as an alternative to indirect metaphors, and do not let a hardware metaphor artificially cap what direct manipulation could do (for example, scrubbing a waveform directly beats only offering a slider).

**Browsing dominates over data entry on mobile.** Given the difficulty of typing on mobile, design first for browse and select, and treat manual data entry as a last resort. This is why mobile has produced a rich vocabulary of browse-optimized idioms: lists, grids, carousels, swimlanes, cards.

**Zooming into a grid is usually a bad idea.** Pinch-to-zoom on a grid of thumbnails looks appealing but breaks legibility and hit-area sizing, especially in narrow portrait layouts. Prefer scrolling and drill-down over zoom for browsing structured content.

**Circular wrap and clear end markers make browse controls easier to navigate.** Carousels, screen carousels, and tab carousels should wrap from the last item back to the first rather than dead-ending, unless the domain makes that confusing. Always signal clearly when the user has reached the last item, and use a page marker widget so position in the sequence is visible.

**Auto-advancing content needs restraint.** A carousel that advances on its own can help make an app feel alive and expose users to featured content, but advancing too fast or during a user's interaction with something else on screen creates disorientation. Pause auto-advance while the user is engaged with other elements. Swimlanes, unlike carousels, should not auto-advance, since they exist to let users browse at their own pace across categories.

**Bars are trained as "these are controls."** Because most native OSes have moved to flat visual styles, the strong affordance bars used to have has eroded. Users now largely rely on a learned convention that text or icon inside a bar equals a navigation or function control, rather than the visuals telling them that directly. Do not defeat this learned convention with ambiguous bar content.

**A practical ceiling exists on the number of controls in a single bar.** With finger-sized hit targets, roughly five items is the practical limit for one bar on a handheld. Beyond that, push overflow into a "More…" control or a tab or tool carousel rather than shrinking hit targets.

**Menu bars are a desktop idiom that does not transplant to mobile.** A row of plain text labels in a bar reads to touch users as a tab bar, and a full desktop-style menu bar interaction (hover, cascading submenus) is not expected on tablet. Worse, hiding function names in menus with unclear labels defeats discoverability. A stacked tool bar plus tool carousel usually reproduces the same functional coverage with better visual clarity.

**Overloading animated transitions confuses users.** When multiple panes slide in from different edges (top, bottom, side) to reveal different kinds of controls stacked on top of each other, users lose track of what layer they are in and how to get back out. Keep the number and direction of screen transitions small and predictable.

**The hamburger drawer critique has some truth but goes too far.** Drawers do bury a whole navigation hierarchy behind one icon, and this can genuinely reduce feature discovery and engagement. But this is fixable (a text label like "Menu", an initially open drawer, a help overlay on first use) rather than a reason to reject drawers outright. Drawers earn their keep in apps with many functions used constantly, or many infrequent but necessary functions, freeing the main screen for content. For lightly used, casually opened apps, tabs (or a tab variant) are the safer choice, since infrequent users will not remember to look in a drawer.

**Direct manipulation beats indirect controls when the surface allows it.** Touch removes the need for sliders and knobs as proxies, letting the user act on the object itself (tilt-shift editing by dragging directly on the image, for example). The tradeoff is a steeper discovery curve, best offset with one-time welcome or help screens per tool rather than by avoiding direct manipulation.

**Sorting and filtering are functionally the same thing on mobile and should be merged.** Small screens and limited user patience mean a sort effectively filters out anything beyond the first screen or two of results, and most users do not distinguish sorting from filtering conceptually anyway. Combine sort and filter controls into one interface rather than separating them, and show a persistent filter summary bar on the results screen so users know what is currently applied.

**Search should minimize typing wherever context allows it.** Because manual text entry is slow and error-prone on mobile, favor voice search, auto-complete, auto-suggest (fuzzy, spell-corrected, synonym-aware), tap-ahead (re-running auto-complete on a selected suggestion), categorized suggestions across content types, and remembered recent or frequent searches over forcing a full manual query every time.

**Implicit personalization can pre-empt explicit search.** Tracking what a user has viewed, liked, or bought lets an app surface likely relevant content (Netflix-style category swimlanes) before the user has to search at all. Keep search available, but it need not be the primary way in.

**Learnability needs extra help on mobile because normal cues are missing.** Screen space is too limited for much instructional text, gestures have no visible affordance until touched, and there is no hover state to carry tooltips the way desktop has. This is why welcome screens, help screens, guided tours, and overlays carry real weight on mobile rather than serving as optional polish.

**Keep the gesture vocabulary small.** The power of mobile interaction comes from a short list of well-known gestures (tap, drag, swipe, pinch, rotate) applied consistently, not from inventing many gestures. A small, well-known vocabulary is what makes gestures discoverable and learnable at all.

**Multi-finger and rotate gestures are poorly discoverable.** They are hard for users to stumble onto, and multi-finger gestures risk colliding with OS-level gestures. Reserve them for advanced, optional functionality, if used at all, rather than for anything a user must find unaided.

**Standalone mobile apps under-integrate with each other.** Most phone OSes ship apps (phone, contacts, calendar, messaging, reminders) that barely talk to one another, leaving obvious cross-app value (like linking a caller to their related emails, appointments, and notes automatically) unrealized. Where the platform permits it (rule-based integration tools, audio routing between compatible apps), designing for this kind of cross-app context is a real opportunity, not just tidiness.

**Embedded and device interfaces are a different design problem than mobile apps, not a smaller one.** Kiosks, appliances, TVs, car dashboards, and lab equipment must contend with public noise, ambient distraction, constrained displays, and constrained input, and this changes the whole design approach, not just the visual style.

**Design hardware and software together for embedded devices.** Because embedded systems are usually built for one purpose rather than general use, and constrained by cost, power, and form factor, hardware controls often substitute for onscreen ones. Treating hardware and software as one integrated design problem, from the start, produces devices (TiVo, the original iPod) that feel coherent, whereas handing a finished mechanical design to software teams after the fact typically does not.

**Context of use should drive embedded interface decisions.** A host juggling hot plates cannot navigate a fussy oven control. A driver cannot read a soft key that changes meaning depending on state without taking her eyes off the road. Map the actual physical, cognitive, and social context of use for the device, not just its feature list, before deciding on the interface.

**Modes are especially costly on constrained devices.** Small displays and limited input make it hard to show what mode a device is in, and switching modes often costs significant navigation. Where possible, let mode changes happen automatically from context (a phone switching into call mode on an incoming call) rather than requiring the user to navigate into a mode manually.

**Scope embedded devices tightly.** Users are better served by a device that does a narrow set of things well than one that tries to be a general-purpose computer in miniature. Where a device shares data with a desktop system, treat it as a satellite of the desktop, an extension providing key functions when the desktop is unavailable, and use scenarios to decide what belongs on the satellite.

**Display-constrained devices force a hierarchy decision.** Limited display real estate creates an inherent tension between showing information clearly and keeping navigation simple. Flatten the information hierarchy if you can. Where you cannot, decide deliberately what is most important and give it the most prominent space, and avoid blinking or alternating between two pieces of information on the same display element since that reads as ambiguous rather than informative.

**Minimize and simplify input on embedded devices.** Full keyboards and mice are rarely available, so even sophisticated substitutes (touchscreen keyboards, voice, handwriting) remain comparatively slow and error-prone. Keep whatever input is required as small and simple as possible.

## Named patterns and principles

- **Transient posture (for mobile apps)**: most non-game mobile apps are used in short, interrupted, task-focused sessions even though they fill the whole screen. Design navigation and flow assuming the user will leave and return often, not settle in.
- **Stacks**: the default handheld top-level layout, a vertical structure of content area (list or grid) plus a top and/or bottom bar for navigation and functions. Use it as the default unless a more specific pattern (carousel, swimlane) fits the content better.
- **Screen carousels**: a top-level pattern for swiping between several full-screen, identically laid out instances (for example, weather for different cities). Use for dashboard-like content with no drill-down, and always make the swipe wrap circularly with a page marker.
- **Index panes**: a tablet-only supporting pane (see also Chapter 18) that lists content items alongside a detail pane showing the current selection, eliminating a level of drill-down. Launch it as an overlapping pane in portrait, promote it to a permanent adjacent pane in landscape.
- **Pop-up control panels**: tablet-scale panels, tied to a specific control or object by a speech-balloon caret, used to adjust that object's parameters without leaving the screen. Prefer these over full-screen control panel screens on tablets since they preserve context.
- **Lists**: the default browse structure for handhelds, tapping a row typically drills down, opens a modal option set, or opens a detail view. Support infinite scroll for large result sets as long as incremental load stays under about a second.
- **Grids (gallery views)**: rows and columns for icons, thumbnails, or media, used for app launchers and media browsing. Disambiguate scroll direction visually (for example, cut off the bottom row) rather than relying on the user to guess.
- **Content carousels**: a horizontally swipeable row of content objects living inside one screen (distinct from screen carousels, which swipe between whole screens). Use for a small, featured set of items, keep to one per screen in the most prominent position, wrap circularly, and if auto-advancing, pause on user interaction and do not advance too fast to read.
- **Swimlanes**: a vertical stack of independently horizontally scrolling carousels, combining a carousel's browsability with a grid's density. Use for browsing multiple content categories with minimal navigation (Netflix-style). Never auto-advance a swimlane, unlike a carousel.
- **Cards**: self-contained chunks combining media, text, links, and social or contextual actions, either socially oriented (Facebook, LinkedIn feed items) or context-data oriented (Google Now snippets). Use for content that benefits from a rich but bounded, consistently shaped unit, and they compose into lists, grids, carousels, or swimlanes.
- **Tab bars**: text and/or icon buttons that switch the main content area between separately maintained content hierarchies, preserving each tab's state. Use as the primary top-level navigation when you have a handful of persistent, parallel content areas.
- **"More…" control**: a bar item that opens an additional screen or pop-up of overflow navigation or functions when more than about five items would need to fit in a bar. Use it, or a tab carousel, instead of cramming or shrinking hit targets.
- **Tab carousels**: tabs that extend past the screen edge and can be swiped through like a carousel, with the active tab highlighted. Show at least one tab's label bleeding off screen so users know it scrolls.
- **Nav bars / action bars**: a top bar with back control and current title (and often function buttons), Android calls this an action bar. Provide a clear back path and current location at minimum.
- **Tool bars and palettes**: bars of function buttons that act on current or selected content, distinct from tab bars which switch views. Use bottom placement on handhelds, and vertical left or right placement or stacked tool bar plus tool carousel on tablets for larger toolsets.
- **Tool carousels**: a horizontally swipeable row of tool icons (often labeled thumbnails previewing the effect), used to fit more tools than a fixed bar can hold. Popular in image and audio editing apps.
- **Menu bars (avoid on mobile)**: a desktop-style text-menu bar is a mismatched idiom on touch, reads as a tab bar, and hides functionality behind unclear labels. Prefer a tool bar plus tool carousel instead.
- **Drawers**: a hidden vertical panel of navigation items (the "hamburger" icon is three stacked lines), revealed by tapping the icon or swiping, that slides the content area aside. Use to save screen real estate for content-heavy or feature-heavy apps, but address discoverability with a text label, an initially open state, or a help overlay if you rely on the icon alone.
- **Secondary-action drawers**: a drawer (often right-hand) dedicated to a secondary object set, like a friends or chat list, separate from the main left-hand navigation drawer.
- **Double drawers**: an app design using both a left-hand primary navigation drawer and a right-hand secondary drawer (for example, messaging), minimizing persistent chrome so the content area can dominate the screen.
- **Item-level drawers**: sliding an individual list or grid item to reveal a small per-item tool bar underneath, instead of a global tool bar. Has real drawbacks (poor discoverability without a visual cue, obscuring the item being acted on, conflicts with other horizontal gestures like delete or drawer-open), so use only when there is no natural OS-level swipe conflict and you accept low discoverability.
- **Tap-to-reveal controls**: manipulation or playback controls stay hidden until the user taps the object or content area, then appear (used heavily in video players and drawing tools). Use to reduce visual clutter for content that is primarily consumed, not constantly controlled.
- **Guided tours**: a carousel of cards with text, images, or video explaining app functions, shown at first launch or after a major release, and re-launchable from settings. "Use guided tours to orient first-time users." Always let users exit from any card.
- **Overlays**: a semi-transparent full-screen layer with hand-drawn-style instructions and arrows pointing at gestures or controls, dismissed by a tap anywhere. "Use overlays to explicate gestures." Re-triggerable from help or settings.
- **ToolTip overlays**: an overlay variant that labels all primary functions on one screen at once, best used as an on-demand help screen for complex authoring apps rather than as a first-run welcome screen.

## How to apply

- Default new mobile app screens to transient posture: fast entry, one focused task, fast exit. Do not design them like a sovereign desktop workspace just because they fill the screen.
- Pick the structural pattern (stack, screen carousel, index pane, pop-up panel) based on form factor and content shape, not by copying whatever the last app used. Re-check the choice separately for handheld, tablet, and mini-tablet if you support all three.
- Cap bar items around five, route overflow to a "More…" control or a carousel variant, and never shrink hit targets below finger scale to fit more in.
- Default to portrait for list or grid browsing apps, and only support landscape (or lock to it) where the content's medium demands it (video, photo capture, e-reading).
- For any app that must replace a real desktop tool (audio, video, illustration), it is fine to raise control density and adopt tool bars, panes, and drag-and-drop, but still keep hit areas finger-scaled and pick one dominant orientation.
- Merge sort and filter into one control and show a live filter summary on the results screen. Never force a department, category, or other single choice before the user can even see other refinement options.
- Build search with voice, auto-complete, auto-suggest, tap-ahead, recent or frequent history, and categorized suggestions, in that rough order of investment, rather than a bare text box.
- Wrap carousels and tab carousels circularly, show a page marker or off-screen-bleeding hint, and pause any auto-advance during user interaction.
- Reserve drawers for apps with either constant heavy use of many functions or many rarely used but necessary functions. For lightweight, casual apps, use tabs instead.
- Limit animated transitions to one clear direction and layer per action, do not stack sliding panes from multiple edges over each other.
- For any embedded device (kiosk, appliance, dashboard, remote), design hardware and software as one system from the start, map the real physical and social context of use, minimize modes and let context switch them automatically, scope the device to a narrow job, and cut input demands to the minimum.
- For kiosks, decide transactional versus explorational early, since that changes placement, expected wait tolerance, and how much personality or sound the interface should have. Size touch targets around 20mm minimum, increase for arm's-length or rushed use, and avoid drag-and-drop and unnecessary scrolling.
- For TV or 10-foot interfaces, design for a five-way (up, down, left, right, select) remote, keep text and layout readable at distance, and integrate control of related devices where possible.
- For automotive interfaces, keep the driver's hands on the wheel and eyes on the road: put common controls on the steering wheel, use physically distinguishable and consistently placed hardware controls, keep visual hierarchy shallow and high contrast, and never bury mode switches (climate, audio, navigation) behind a shared multi-purpose knob.
- For audible or phone-tree interfaces, order options by actual usage frequency drawn from context scenarios, restate available options after every step, always offer a way back one level and to the top, and always offer an escape to a human.

## Watch out for

- Do not treat pinch-to-zoom as a fix for cramped grids or lists, it breaks legibility and hit areas, use scrolling and drill-down instead.
- Do not rely on tap-and-hold for contextual actions, it mirrors the desktop right-click but is poorly discoverable on touch, use a visible menu control or tap-to-select plus an action menu instead.
- Do not use multi-finger or rotate gestures for anything essential, they are hard to discover and can collide with OS-level gestures.
- Do not let a drawer's icon alone carry the burden of discoverability, pair it with a text label, an initial open state, or a first-run help overlay if engagement matters.
- Do not stack multiple sliding panels from different screen edges for different functions (a real example: an account panel sliding down and a settings panel sliding up from the same drawer), this creates exactly the kind of disorienting transition overload to avoid.
- Do not break your own platform's drawer convention partway through an app (sliding a drawer over content in one place and sliding content away to reveal it in another).
- Do not hide most filter or sort options behind a forced single category choice, or bury the filter control behind an obscure icon that disappears on scroll, both defeat the point of offering refinement at all.
- Do not bring desktop terminology or idioms (menu bars, a "Cancel" button on an oven, a "Settings mode" to change a thermostat) onto small or single-purpose devices, the metaphor does not fit the mental model users bring.
- Do not overload one physical control with many unrelated modes on a safety-critical device (the chapter cites BMW's original iDrive knob/joystick covering entertainment, climate, and navigation as an example of this creating real danger).
- Do not assume speech input is automatically less demanding on attention than a physical button in a noisy environment like a car, the tradeoff is genuinely unresolved and needs its own validation.
