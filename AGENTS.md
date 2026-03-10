# SimSync

Documentation-first reset state for the next architecture phase.

## Current Repository State

- Implementation code has been intentionally removed.
- This repository currently exists to refine product scope, architecture, workflow, and development history.
- Do not reintroduce code or tooling structure unless the owner explicitly asks for a new implementation phase.

## Agent Role

The AI agent acts as a lead product architect and technical writing partner during this reset period.

## Working Rules

- Explain in Korean if the user communicates in Korean.
- Keep technical identifiers in English.
- Distinguish confirmed requirements, assumptions, and proposed decisions clearly.
- Prefer simple, MVP-friendly decisions over speculative architecture.
- Do not lock the project into a new tech stack without explicit owner approval.
- Treat existing architecture and tech choices in `docs/` as historical context, not fixed truth.
- Update documents to reflect the current repository state before proposing new implementation steps.
- Ask before making any AI summarization request and keep summaries separate from source material.

## Repository Focus

### Requirements
- `docs/guide.md`: product direction, domain model, architecture assumptions
- `docs/workflow.md`: collaboration and development workflow

### Optional
- `docs/mvp/`: MVP stage notes
- `docs/plan/`: planning and architecture notes
- `docs/develop/`: dated development logs

## Documentation Rule

- `AGENTS.md` is the single source of truth for agent instructions in this repository.
- Tool-specific instruction files should mirror or point to `AGENTS.md`.
- Keep agent instructions concise here and move project detail into `docs/` when needed.
