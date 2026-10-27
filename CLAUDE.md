# New Me

Private habit and health scoreboard for two people, iPhone only.
Flutter app in `app/`, Go server in `server/`, design and research in `docs/`.
Read `docs/design.md` before changing behaviour.

## Conventions

- The app follows check-in's conventions (`docs/research/conventions-checkin.md`): Riverpod 3 Notifiers with seeded test seams, dio ApiClient, plain Navigator, dark-only Onyx theme from `app/lib/theme/tokens.dart`, Material icons, system font, radii 10/12/14, haptics on actions, restrained 200ms motion.
- The server follows check-in's conventions: chi router, pgx with hand-written SQL, embedded migrations applied on boot, `NEWME_*` env config, `{"error": msg}` envelope, DB-backed tests through `TESTDB_URL`.
- Scoring lives in `server/internal/score` as pure functions with unit tests; handlers only wire data in and out.
- Every request needs `X-App-Key`; every authenticated request needs a Bearer device token.
- Never edit an applied migration; add a new numbered file.

## Commands

- Server tests: `server/scripts/test.sh` (throwaway Postgres in Docker).
- App checks: `cd app && dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test`.
- App on web for UI review: `cd app && flutter run -d chrome --dart-define=NEWME_APP_KEY=dev-key-0123456789`.

## Release

Merge to `main` runs `release.yml`: tests, version bump from conventional commits, Docker image to GHCR, iOS build to TestFlight.
Watchtower on the server pulls the new image automatically.
