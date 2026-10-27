# New Me app

Flutter app for iPhone.
Web builds exist only for local visual review.

## Checks

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release --dart-define=NEWME_APP_KEY=dev-key-0123456789
```

## Running for review

```sh
flutter run -d chrome --dart-define=NEWME_APP_KEY=dev-key-0123456789 --dart-define=NEWME_SERVER=http://localhost:8080
```

`NEWME_SERVER` overrides the server that onboarding probes on launch (default `https://new-me.npc-server.top`).
The server needs `NEWME_DEV_CORS=true` for the browser build.

## iOS notes

Run `flutter config --no-enable-swift-package-manager` before building for iOS, locally and in CI.
With Swift Package Manager enabled the app launches to a white screen.
The deployment target is 15.0, which `package:health` requires.
