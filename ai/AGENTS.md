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
- Agents document new features and maps to code in "subsystem" docs.

### NAMED FILES

- `AGENTS.md` core read-only file of critical rules.
- `project-info.md` project identity, major components, local rules, and task routing.
- `subsystem-human/` protects sparse user-facing feature lists by component.
- `subsystem-agent/` protects engineering notes by ownership and constraint boundary.
- `Docs/` is the human-side folder. Not default intake.

### Subsytem Notes

The subsystem folder details the app's code, divided into components, in human language as lists of features and critical behavior/engineering facts only.

- Document current state only.
- Not changelogs, history, or maintenance reports..

## Subsystem Pattern

- Group by human-facing component or behavior boundary.
- List implemented features before engineering notes.
- Document only non-standard behavior.
- Update the subsystem doc that owns changed behavior.
