# SimSync Development Workflow

## Branch Strategy
- `main` — stable, deployable code
- `feat/<name>` — feature branches
- `fix/<name>` — bug fix branches

## Development Flow
1. Create a feature branch from `main`
2. Develop and test locally
3. Open a PR with summary and test plan
4. Review and merge to `main`

## Build Commands

### Desktop
```bash
cd desktop
wails dev              # dev mode with hot reload
wails build            # production build
```

### Backend
```bash
cd backend
go run .               # run server
go test ./...          # run tests
go vet ./...           # static analysis
```

## Testing
- Go: use standard `testing` package with table-driven tests
- Run `go vet ./...` before committing
- Frontend: manual testing during prototype phase

## Commit Conventions
- Use clear, concise commit messages
- Focus on "why" not "what"
- One logical change per commit

## Code Review Checklist
- [ ] Errors wrapped with context (`%w`)
- [ ] No ignored errors
- [ ] No hardcoded secrets
- [ ] Tests pass
- [ ] `go vet` clean
