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

### Flutter App (Desktop + Mobile)
```bash
cd app
flutter run -d macos          # macOS desktop
flutter run -d windows        # Windows desktop
flutter run -d linux          # Linux desktop
flutter run -d chrome         # web (debug only)
flutter run                   # connected mobile device
flutter build apk             # Android release
flutter build ios              # iOS release
flutter build macos            # macOS release
flutter test                   # run tests
```

### Backend
```bash
cd backend
go run .               # run server
go test ./...          # run tests
go vet ./...           # static analysis
```

## Testing
- Backend (Go): use standard `testing` package with table-driven tests
- Client (Flutter): use `flutter_test` package with widget and unit tests
- Run `go vet ./...` before committing backend changes
- Run `flutter analyze` before committing client changes

## Commit Conventions
- Use clear, concise commit messages
- Focus on "why" not "what"
- One logical change per commit

## Code Review Checklist

### Backend (Go)
- [ ] Errors wrapped with context (`%w`)
- [ ] No ignored errors
- [ ] No hardcoded secrets
- [ ] Tests pass
- [ ] `go vet` clean

### Client (Flutter)
- [ ] No hardcoded secrets
- [ ] Tests pass
- [ ] `flutter analyze` clean
- [ ] Responsive layout (desktop + mobile)
