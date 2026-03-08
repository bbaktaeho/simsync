# SimSync

Personal markdown-based note and work log application with calendar-oriented daily notes, multi-device sync, and AI-powered summaries.

## Build & Run

### Desktop (Wails)
```bash
cd desktop
wails dev          # development with hot reload
wails build        # production build
open build/bin/simsync.app  # run (macOS)
```

### Backend
```bash
cd backend
go run .
```

## Tech Stack
- Language: Go 1.26.1 (entire stack)
- Backend: Go standard library (minimal external dependencies)
- Database: PostgreSQL 18+
- Desktop: Wails
- Mobile: Flutter + Go (notecore via gomobile bind)
- Frontend: Vanilla TypeScript + Vite

## Project Structure
```
simsync/
├── backend/       # Go API server
├── desktop/       # Wails desktop app
├── mobile/        # Flutter + Go (notecore via gomobile bind) app
└── docs/          # Project documentation
    ├── guide.md
    ├── workflow.md
    └── plan/      # Planning documents
```

## Code Style
- Go: Follow Go standard library conventions. Use `gofmt`.
- Error handling: Always wrap errors with context using `fmt.Errorf("context: %w", err)`. Never ignore errors.
- Naming: English for all code identifiers, API paths, struct names, schema names.
- Comments: Only where logic is not self-evident. Doc comments on exported types and functions.
- Frontend: TypeScript strict mode. No unnecessary abstractions.

## Rules
- Do not change the tech stack without explicit owner approval.
- Prefer Go standard library over external packages. State caveats when a dependency is necessary.
- Store AI summaries separately from original notes.
- Require explicit user consent before any AI summarization request.
- Record source device for note mutations and sync events.
- Keep architecture simple and MVP-friendly. Avoid over-engineering.
- Explain in Korean if the user communicates in Korean.
- Use English for code.

## Documentation
- [Project Guide](docs/guide.md) — architecture, domain model, tech decisions
- [Development Workflow](docs/workflow.md) — branch strategy, PR process, testing
- [Planning Documents](docs/plan/) — dated planning and design docs
