# New Me

New Me is a private iPhone app for two people that turns daily habits and Apple Health data into a shared score.
The Go server stores the data and computes scores, and the Flutter app is the only client.

## Layout

- `app/` - Flutter client (iOS, plus a web build for local visual review only).
- `server/` - Go API server backed by Postgres.
- `docs/` - design and research notes.

The full design lives in [docs/design.md](docs/design.md).

## Server tests

Run `server/scripts/test.sh`.
It starts a throwaway Postgres in Docker and runs the Go test suite against it.

## Running the app on web

From `app/`, run `flutter run -d chrome` (or `flutter run -d web-server`).
Use a phone-width window for UI review.

## Deploy

Merging to `main` builds the image `ghcr.io/nc1107/new-me` and uploads a TestFlight build.
Watchtower on the server pulls the new image automatically.

## License

MIT, see [LICENSE](LICENSE).
