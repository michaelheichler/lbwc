# Platform and Posture

Source: About Face: The Essentials of Interaction Design, 4th Edition (Cooper, Reimann, Cronin, Noessel, 2014), Chapter 9, "Platform and Posture".

## In one line

Before designing any screen detail, decide what hardware/software platform the product lives on and what behavioral stance (posture) it should take, because posture dictates how much of the user's attention the product can claim and how bold, dense, or quiet it should be.

## Core ideas

**Platform is more than hardware.** Platform means the combination of hardware and software that makes the product run, including display size and resolution, input methods, network connectivity, OS, and data capabilities. It is a fuzzy, shorthand concept, not a precise category. Because platform constrains almost everything downstream, technical platform decisions should be made together with interaction design, not locked in before designers are involved. Handing designers a fixed platform choice from management wastes the chance to pick the platform that actually fits the persona's needs and context.

**Posture is a behavioral stance, not a look.** Posture describes how much attention a product expects from the user and how it responds to that attention, similar to how a soldier, a toll collector, and an actor each have a characteristic public stance. This is why visual style (color, boldness, density) is a behavioral decision, not a taste or branding decision. An interface whose look conflicts with its actual purpose feels jarring. Get the posture right first, then let visual design express it, not the other way around.

**Posture is not monolithic across a product.** A single app can shift postures by context. Reading email attentively during a commute versus glancing up an address while running to a meeting are different postures for the same app. Likewise, a word processor is mostly sovereign but individual tools inside it (a table-builder) behave transiently. Define the predominant posture for the whole product, then examine whether specific features or contexts need their own posture treatment.

**Desktop applications fall into three postures: sovereign, transient, daemonic.** Each implies a different interaction style, screen footprint, visual boldness, and design priority. Knowing which one an app is gives you a design anchor. A sovereign app that behaves timidly, or a transient app that behaves densely, will feel wrong to users even if they can't say why.

**Sovereign apps should be built for intermediates, not novices or experts.** Users spend a small fraction of their lifetime relationship with a sovereign app as first-timers, so optimizing for that brief period at the expense of long-term efficiency is a bad trade. WordStar is the book's cautionary tale. It won by serving intermediate users well while ignoring newcomers, then lost the market once a competitor matched that power while also being easier for first-time users. The lesson is that catering to the beginner window over the long-run intermediate experience can cost the product its market.

**Sovereign apps should default to full-screen, dense, richly fed-back, and richly controllable**, because the user commits long continuous sessions to them, has no competing app claiming the screen, and will build deep familiarity that lets them decode small, closely packed controls, subtle status indicators, and demanding fine-motor targets. The reasoning chain is that long attention plus repetition equals earned familiarity, and familiarity is what lets you shrink and pack the interface without becoming unusable.

**Transient apps must be simple, bold, and self-explanatory** because users summon them briefly, infrequently, and won't build lasting familiarity, so every visit is effectively close to a first visit. Instructions belong on the surface, labels should spell out verb-object actions ("Set up user preferences" rather than "Setup"), and the whole function should live in a single window with no supporting dialogs. If you find yourself adding a second window or dialog to a transient app, treat it as a signal the design needs rework.

**Daemonic apps are invisible by design, and all their rare user contact must obey transient design rules**, because a background process (like a heartbeat) that occasionally must be installed, adjusted, or explained needs that occasional contact to be maximally clear. Many users don't even know the daemon exists, so status messages from it must not confuse. This raises the interesting design question of how a normally invisible app should even be summoned when needed (system tray icons, hidden pop-up menus, control panels).

**The web recapitulates and blends desktop postures.** Informational websites, transactional websites, and web applications sit on a spectrum, not in hard categories, and postural analysis applies to each differently.

**Informational sites balance sovereign density against transient learnability.** The deciding factor is expected visit frequency. Content updated often invites repeat, sovereign-leaning use, while content updated rarely invites occasional, transient-leaning use, so orientation, bookmarkability, and remembered preferences matter more there. Mobile access nudges any site toward the transient end because mobile users are multitasking with limited attention.

**Transactional sites need both informational sovereignty and transactional transience.** Shoppers research and compare (attention-heavy, sovereign-like), but also bounce between competing sites and want efficient, low-friction transactions (transient-like). The design lesson from Jared Spool's e-commerce study is that users judge page load time by whether they reached their goal, not by the actual clock time, so don't sacrifice goal completion for the sake of fewer or faster page loads.

**Web applications should be designed like desktop apps, not stacks of pages**, once they cross into rich, asynchronous, complex-behavior territory. Treating a sovereign web app as a page-based site forces users into page-reload friction for what should be continuous interaction. The book's analogy is that websites are like elevators, good for getting to a specific floor, but you don't try to do real work inside an elevator.

**Mobile devices demand posture categories the desktop never needed.** Satellite posture (dedicated content viewers synced from cloud or desktop, like e-readers and cameras) devotes nearly all screen space to content display with minimal input. Standalone posture (modern smartphone apps) blends sovereign traits (full-screen, persistent menus and toolbars) with transient traits (large simple controls, self-explanatory, brief sessions), because users bounce between many different apps in short bursts throughout the day. Tablets push toward sovereign posture because their larger screens and locked full-screen OS behavior support it, but 7-inch tablets sit in an awkward in-between zone and should not be designed like oversized phones.

**Public and embedded platforms are biased toward transient posture by context, not by screen size.** A kiosk's large full screen might suggest sovereign posture, but its actual users (first-timers, standing, distracted, brief transactions) push it toward transient design. Give users clear step-by-step orientation ("where am I in my process" rather than "where am I in the system") and easy escape hatches to cancel and restart. Automotive interfaces split by function. Entertainment and settings are transient (simple, large controls, minimal distraction from driving), while navigation leans more sovereign (persists for the whole trip, holds complex live information) but must still render that complexity in a glanceable, transient-style visual hierarchy because driver attention is the scarce resource. Smart appliances default to transient because their users are not tech-focused and want one specific outcome (start the wash cycle), with any ongoing status handled by a quiet daemonic-style indicator, not a rich sovereign display.

## Named patterns and principles

**Sovereign posture**: an application that monopolizes a user's attention for long, continuous stretches (word processors, spreadsheets, email clients). Use when the persona spends deep, repeated sessions in the tool. Works because sustained familiarity lets the interface run dense, quiet, and full-screen without becoming a burden.

**Transient posture**: an application that appears briefly to perform one function, then disappears (Explorer file picker, volume control, most dialog boxes). Use for infrequent, single-purpose interactions that support a sovereign app in the background. Works because without repeated exposure users need every control spelled out, big, and immediately clear.

**Daemonic posture**: an application that runs invisibly, unattended, in the background (printer drivers, network connections, sync services). Use for processes the user should not have to actively manage. Works because most of the time there is no interaction to design, and when interaction does happen it must follow transient rules since the user has no built-up familiarity with it.

**Informational website posture**: content-and-navigation-first sites (Wikipedia, marketing sites) whose central design problem is findability (a term the book credits to Peter Morville), the ease of locating specific information inside the site.

**Transactional website posture**: sites that let users accomplish something beyond browsing (shopping carts, checkout, configurators), blending informational sovereignty with transactional efficiency demands.

**Web application posture**: rich, interactive, asynchronous browser-delivered software (Google Docs, Salesforce, Basecamp) that behaves like desktop software rather than a page stack. It splits further into sovereign web applications (complex full-screen tools) and transient web applications (occasional-use enterprise utilities, where the same tool may be sovereign for one persona and transient for another).

**Satellite posture**: mobile or wearable devices whose job is chiefly to view and lightly navigate content synced from elsewhere (e-readers, cameras, digital audio players, and modern wearables like smartwatches and heads-up displays). Use when the device's core job is display and light control of externally authored content. Works because minimal screen and input real estate rules out deep interaction, so the design should faithfully present synced content rather than try to be a full computer.

**Standalone posture**: modern smartphone app posture, blending sovereign traits (full-screen, persistent menus and toolbars) with transient traits (large, simple, self-explanatory controls). Use for the general run of phone apps, since users context-switch between many apps in short bursts and never build lasting familiarity with any single one. Works because it matches both the small touch-target constraints and the fragmented, multitasking attention pattern of on-the-go use.

**Ten-foot interface posture**: TV and console UIs navigated from a distance with a D-pad-like remote rather than direct touch or mouse input. Requires an obvious current-focus indicator, since users can't point directly at what they want, they have to know where focus currently sits and where each directional move takes it.

**Findability**: coined by Peter Morville, the ease of locating a specific piece of information within a site. The book names this as the central design metric for informational websites.

## How to apply

- Decide platform and posture explicitly, early, before detailed screen design starts. Treat "what platform, what posture" as a first-class design decision, not something inferred late from whatever page or component you happen to be building.
- Identify which posture (sovereign, transient, daemonic, or one of the web/mobile/embedded variants) the whole product takes, then check whether specific features or contexts need a different posture from the product's default.
- For a sovereign product: default to full-screen or maximized, pack in dense controls and rich status feedback, use a conservative and narrow color palette, support rich input (direct manipulation, keyboard shortcuts, small hit targets), and optimize the primary experience for intermediate users rather than first-time users.
- For a transient product: keep it to a single window and view, use large unambiguous controls with verb-object labels spelled out in full, avoid nested dialogs, remember the user's last window position and settings so the app reopens where it left off, and never make the user manage window placement as a side task.
- For a daemonic component: keep it invisible in normal operation, surface a status icon only if it conveys continuously useful information, and route any needed configuration through a transient-style control panel or menu with maximal clarity, since the user has no ongoing familiarity with it.
- For informational or transactional web content: gauge expected visit frequency and content update cadence to decide how sovereign versus how transient the site should lean, and prioritize navigational clarity and goal completion over minimizing raw page count or load time.
- For a sovereign web application: design it like a desktop app (persistent environment, minimal full-page redraws, dense purpose-built panes) rather than a stack of web pages.
- For mobile: pick satellite posture for content-viewing devices, standalone posture for general-purpose phone apps, and treat tablets (except awkward 7-inch models) as sovereign-capable given their larger screens.
- For kiosks, appliances, and vehicle systems: default toward transient design (large controls, single-screen flows, clear escape hatches, step-in-process orientation rather than system-map orientation) unless the use case is genuinely exploratory (education/entertainment kiosks) or genuinely long-duration and information-dense (in-car navigation), in which case borrow sovereign traits while still keeping the visual hierarchy glanceable.

## Watch out for

- Do not let management or engineering lock in hardware platform decisions before interaction designers weigh in. Platform choices made without design input tend to under-serve the actual persona and context.
- Do not let personal or stakeholder taste dictate an app's visual boldness or density. Posture should decide that, not preference.
- Do not optimize a sovereign application primarily for first-time users at the cost of the intermediate, frequent-user experience. That tradeoff is what killed WordStar's market position.
- Do not add a second window, dialog, or view to what should be a transient application. Treat the impulse to do so as a signal to redesign, not a feature to build.
- Do not clutter daemonic status areas with icons for processes that are almost never relevant. Only show a persistent icon if it carries continuously useful status.
- Do not treat a rich, complex web application as if it were just another set of pages. Forcing full-page interaction patterns onto sovereign-style functionality creates unnecessary friction.
- Do not treat 7-inch tablets as oversized phones. Their aspect ratio and size create their own layout constraints distinct from both phones and larger tablets.
- Do not assume a large screen automatically implies sovereign posture. Kiosk and automotive contexts show that user situation (standing, distracted, driving, first-time) can override screen size in determining the right posture.
- Do not judge transactional web pages purely by load time. Users judge speed by whether they reached their goal, so cutting page count without preserving goal completion can backfire.
