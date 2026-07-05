# pocket_pilot

Flutter personal-finance app (budgets, categories, transaction tracking, Gemini-assisted
categorization) with a Node backend in `server/`. Dart SDK ^3.8.1. See `DEVELOPMENT.md`
for environment details and `dart_defines.example.json` for required defines.

## Commands
- Run app: `flutter run --dart-define-from-file=dart_defines.json`
- App test / lint / format: `flutter test` · `flutter analyze` · `dart format .`
- Backend (in `server/`): `npm ci` · `npm run typecheck` · `npm test`

## CI (path-filtered — don't add required checks to branch protection)
- `ci.yml`: backend typecheck+tests on `server/**` PRs
- `frontend.yml`: Flutter analyze/test gate on `lib/**` etc.
- `backend.yml`: GHCR build + VM deploy on push

## Dual-Agent Workflow
This repo follows the global Claude+Codex standard (~/.claude/CLAUDE.md, ~/.codex/AGENTS.md).
- Tickets: `.agents/tickets/T-xxx-<slug>.md` (template: `_template.md`). Done tickets → `.agents/tickets/done/`.
- Branches: `claude/T-xxx-slug` | `codex/T-xxx-slug`. Commits: `claude:` / `codex:` prefix.
- All merges to main via squash PR. Codex worktrees live in `.worktrees/` (gitignored).
- Test: `flutter test` (+ `npm test` in server/) · Lint: `flutter analyze` · Format: `dart format .`
