# Repository Guidelines

## Project Structure & Module Organization
- `rucking_app/`: Flutter client app (`lib/`, `assets/`, platform folders, tests in `test/`).
- `RuckTracker/`: Flask API and services (`app.py`, `api/`, `models/`, `migrations/`, `templates/`, `static/`).
- Root Python utilities and SQL: maintenance scripts (`*.py`) and database/sql helpers (`*.sql`).
- Config: `.env` files (do not commit secrets), `Procfile`, Sentry config.

## Do Not Modify Without Approval
- Location tracking is critical. Do not change logic without explicit maintainer approval.
- Affected files: 
  - `rucking_app/lib/core/services/location_service.dart`
  - `rucking_app/lib/core/services/background_location_service.dart`
  - `rucking_app/lib/features/ruck_session/presentation/bloc/managers/location_tracking_manager.dart`
  - Related native platform-channel code (Android/iOS) that affects GPS/background behavior.


## Build, Test, and Development Commands
- Flutter setup: `cd rucking_app && flutter pub get`
- Run Flutter app: `flutter run` (use a real device for GPS features).
- Flutter tests: `flutter test`; analyze/format: `flutter analyze` and `dart format .`
- Python env: `python -m venv .venv && source .venv/bin/activate`
- Install deps (repo-wide): `pip install -r requirements.txt`
- Run API (dev): `FLASK_APP=RuckTracker.app:app FLASK_ENV=development \
  SESSION_SECRET=dev REDIS_URL=redis://localhost:6379 \
  DATABASE_URL=postgresql+psycopg2://user:pass@localhost:5432/db flask run`
- Run API (gunicorn): `gunicorn -c RuckTracker/gunicorn_config.py RuckTracker.app:app`

## Coding Style & Naming Conventions
- Python: PEP8, 4-space indents, `snake_case` functions, `PascalCase` classes, module files `snake_case.py`. Keep endpoints small, validate inputs, log errors.
- Dart: Use `dart format` and `flutter analyze`; files `lower_snake_case.dart`, classes `UpperCamelCase`, private members with leading `_`.
- Config: Never hardcode secrets; read from env via `python-dotenv`/Flutter `--dart-define` when needed.

## Testing Guidelines
- Flutter: place tests in `rucking_app/test/` with `*_test.dart`. Mock platform/services; keep fast and deterministic.
- API: prefer `pytest` if available; otherwise lightweight script or `unittest`. Name tests `test_*.py` near code or under `RuckTracker/`.
- Coverage: focus on API routes, data validation, auth, and any critical calculations (distance, calories, stats).

## Commit & Pull Request Guidelines
- Commits: imperative mood, scoped and small. Use clear tags when warranted (e.g., `SECURITY:`, `CRITICAL:`) consistent with history.
- PRs: include summary, reasoning, linked issue, screenshots for UI/API example payloads, and local test results. Note env vars/config changes and any migration steps.

## Security & Configuration Tips
- Required API env: `SESSION_SECRET`, `DATABASE_URL`; optional: `SENTRY_DSN`. Keep `.env` local; never commit secrets. Rate limits can be relaxed with `DISABLE_RATE_LIMITING=true` for load tests.
