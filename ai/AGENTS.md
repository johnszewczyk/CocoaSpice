# AGENTS

## CRITICAL RULES Rules

### TOKEN POLICY

- Conserve tokens.
- Route first. Read code second.
  - Do not repeat-scan generic build logs.
  - Do not freely use screen-cap mode. Let the human verify.
- Let the human test unless a quick sanity check is enough.
- Request more intelligence and context when helpful.

### BUILD POLICY

- Use boring, simple vanilla features and interfaces
  - no custom systems without request when needed
- Project is clean-room builds only:
  - no compatibility layers, fallbacks, legacy bridges, or patch fixes
  - make new code foundational, suggest redesign when needed
- Fail hard and loud
  - no alternative routes; app works or doesn't

## DOCS POLICY

- Agent operations are guided by constitutional documents.
- Document user-facing behavior in `subsystem-human/` and engineering constraints in `subsystem-agent/`.

### NAMED FILES

- `AGENTS.md` core read-only file of critical rules.
- `project-info.md` project identity, major components, local rules, and task routing.
- `subsystem-human/` protects sparse user-facing feature lists by component.
- `subsystem-agent/` protects engineering notes by ownership and constraint boundary.
- `Docs/` is the human-side folder. Not default intake.

### Subsystem Notes

Projects maintain two explicitly different subsystem note families:

- `subsystem-human/` records sparse, implemented user-facing behavior.
- `subsystem-agent/` records engineering ownership, invariants, lifecycle, concurrency, and failure boundaries.

- Document current state only.
- Do not write changelogs, investigation stories, or maintenance reports.

## Human Subsystem Pattern

- Group by human-facing component or behavior boundary.
- Use plain-language headings such as `Display`, `Selection`, `Playback`, and `Persistence`.
- List only implemented user-facing behavior.
- Update the human note that owns the changed behavior.

## Agent Subsystem Pattern

- Group by engineering ownership or constraint boundary.
- Use focused headings such as `Scope`, `Ownership`, `Invariants`, `Lifecycle`, `Concurrency`, `Failure Boundaries`, and `Files`.
- Document only the current constraints needed to make safe changes.
