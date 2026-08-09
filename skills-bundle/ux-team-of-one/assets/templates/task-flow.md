# Task Flow

<!-- When to use: when you need a complete picture of how the experience unfolds over time, including the transition points where UX most often breaks down. Produces: a boxes-and-arrows flow of one core scenario, with entry/exit points, branches, and annotations. Best drawn on a whiteboard with PMs/engineers; this template captures it in text. (Method 14) -->

**Scenario / task:** {{scenario_name}}
**Author:** {{your_name}}   **Date:** {{date}}
**Approach:** {{top_down_or_bottom_up_or_scenario}} <!-- top-down: start at first screen; bottom-up: start at a "moment of truth" and work outward -->

> Don't boil the ocean — flow one discrete core scenario, not the whole system. Notation can be boxes-and-arrows (interaction + system behavior) or low-fi UI screens; just make sure everyone can read your shapes.

## Starting Point
<!-- What the user encounters first (or the central "moment of truth" if bottom-up). -->
{{starting_point}}

## Steps
<!-- Each step: what the user sees/does, then the system's reaction. Use one block per step. -->

1. **{{step_name}}**
   - User action: {{user_action}}
   - System reaction: {{system_reaction}}
   - Next: {{next_step}}

2. **{{step_name}}**
   - User action: {{user_action}}
   - System reaction: {{system_reaction}}
   - Next: {{next_step}}

<!-- Repeat until you reach a reasonable start-and-end point. -->

## Alternate Entries and Exits
<!-- For each key step: another way someone could arrive here? somewhere else they're likely to go? What if they abandon and return later — or return on a different device? -->
- At {{step}}: alternate entry — {{alt_entry}}; alternate exit — {{alt_exit}}; abandon/return behavior — {{return_behavior}}

## Decision Points and Branches
<!-- Where the user chooses between options, or where role changes (e.g. employee vs. manager) change what they can see/do. How many paths should there be? -->
- **Decision:** {{decision_point}}
  - If {{condition_a}} -> {{path_a}}
  - If {{condition_b}} -> {{path_b}}

## Annotations
<!-- Notes on how transitions should occur and anything not self-evident from the flow itself. -->
- {{annotation}}
