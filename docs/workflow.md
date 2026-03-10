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

## Implementation Workflow

코드를 구현할 때 다음 절차를 따른다. 매 단계에서 관련 스킬이 있는지 확인한다.

1. 계획 수립
2. 계획 검토
3. 구현
4. 구현이 목적에 부합하는지 검토
5. 잠재적 버그, 크리티컬 이슈, 보안 문제 검토
6. 개선 사항에 문제가 없는지 검토
7. 기존 코드와 통합/재사용 가능 여부 검토
8. 사이드 이펙트 검토
9. 전체 변경 사항 재검토
10. 불필요해진 코드 정리
11. 최종 코드 품질 검토
12. 사용자 흐름에서 문제가 없는지 확인
13. 배포 가능 퀄리티인지 검토
14. 커밋 및 PR 작성

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
