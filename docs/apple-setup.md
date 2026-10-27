# Apple setup for New Me

This is the one-time sequence that gets the first TestFlight build onto Nick's phone.
Steps marked BROWSER need Nick logged in to Apple in a browser.
Steps marked SCRIPTED run from a terminal through the App Store Connect API.

## Values

- Bundle id: `top.npcserver.newme`
- Apple team: `76S78SUWVM`
- Profile name: `New Me App Store Distribution`
- App Store listing name: `New Me Habits` (App Store names are globally unique; the home screen name stays `New Me` through `CFBundleDisplayName`)

## Order of operations

1. BROWSER: sign in to App Store Connect and accept any pending agreements under Business.
   Builds will not process while an agreement is pending.
2. Reuse the five secrets that check-in already uses (see below).
   No new certificate or API key is needed.
3. SCRIPTED: export the three API key variables locally.
   `export ASC_API_KEY_BASE64=$(base64 -w0 AuthKey_XXXX.p8) ASC_KEY_ID=XXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
4. SCRIPTED: preview the requests with `scripts/asc-setup.sh --dry-run`.
5. SCRIPTED: register the bundle id, enable HealthKit, pick the certificate and create the profile, then store it as a secret.
   `scripts/asc-setup.sh | gh secret set IOS_PROVISIONING_PROFILE_BASE64 --repo NC1107/new-me`
   If several Apple Distribution certificates exist, the script lists them and stops.
   Re-run with `--cert-id ID` and pick the one whose private key is inside `IOS_CERTIFICATE_BASE64`.
   The order inside the script matters: the HealthKit capability must exist before the profile is created.
6. BROWSER: create the app record in App Store Connect under Apps, New App.
   Platform iOS, name `New Me Habits`, primary language English, bundle id `top.npcserver.newme`, any SKU such as `newme`.
   This cannot be scripted.
7. Generate the app key and set the remaining secrets (see the secret list below).
8. Push to `main`.
   The release workflow builds, uploads and waits until App Store Connect reports the build as processed.
9. BROWSER: in App Store Connect open Users and Access and invite Nadia with the Customer Support or App Manager role.
   She accepts the email invitation on her phone or computer.
10. BROWSER: open TestFlight, create an internal group (for example `Household`), enable automatic distribution, and add Nick and Nadia as testers.
    Automatic distribution sends every processed build to the group without a manual step.
11. On both phones install TestFlight, accept the invitation, and install New Me.
12. On both phones open TestFlight, Settings (or the app page) and turn on Automatic Updates.
13. Nick opens the app and joins first, before the TestFlight link is shared with Nadia.

## Optional: new distribution certificate

The shared certificate is preferred.
To create one instead, generate a CSR and key, then let the script submit it:

1. `openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr -subj "/CN=New Me Distribution"`
2. `scripts/asc-setup.sh --create-cert dist.csr --cer-out dist.cer | gh secret set IOS_PROVISIONING_PROFILE_BASE64 --repo NC1107/new-me`
3. `openssl x509 -inform DER -in dist.cer -out dist.pem`
4. `openssl pkcs12 -export -inkey dist.key -in dist.pem -out dist.p12`
5. `base64 -w0 dist.p12 | gh secret set IOS_CERTIFICATE_BASE64 --repo NC1107/new-me`
6. `gh secret set IOS_CERTIFICATE_PASSWORD --repo NC1107/new-me` and enter the export password.

If check-in keeps using the old certificate it still works until that certificate expires.
Updating a shared certificate means updating both repositories.

## Secrets

Five are shared with check-in and hold the same values:

| Secret | Meaning |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Apple Distribution certificate and private key as a base64 `.p12` |
| `IOS_CERTIFICATE_PASSWORD` | Password of that `.p12` |
| `ASC_API_KEY_BASE64` | The App Store Connect `.p8` key, base64 encoded |
| `ASC_KEY_ID` | The key id |
| `ASC_ISSUER_ID` | The issuer id |

Two are specific to New Me:

| Secret | Meaning |
| --- | --- |
| `IOS_PROVISIONING_PROFILE_BASE64` | Output of `scripts/asc-setup.sh` |
| `NEWME_APP_KEY` | Shared client key, must equal `NEWME_APP_KEYS` in the server `.env` |

Generate the app key once and use the same value in both places:

```sh
KEY=$(openssl rand -hex 32)
printf '%s' "$KEY" | gh secret set NEWME_APP_KEY --repo NC1107/new-me
echo "NEWME_APP_KEYS=$KEY"   # paste into the server .env, then restart the server
```

The web review build uses a different key, so a leaked web bundle does not expose the one inside the IPA.

Setting the five shared secrets from the check-in values:

```sh
gh secret set IOS_CERTIFICATE_BASE64 --repo NC1107/new-me < cert.p12.base64
gh secret set IOS_CERTIFICATE_PASSWORD --repo NC1107/new-me
gh secret set ASC_API_KEY_BASE64 --repo NC1107/new-me < asc-key.base64
gh secret set ASC_KEY_ID --repo NC1107/new-me
gh secret set ASC_ISSUER_ID --repo NC1107/new-me
```

GitHub never reveals a stored secret, so keep the originals (the `.p12`, its password and the `.p8`) in a password manager.

## Server image

The release workflow pushes `ghcr.io/nc1107/new-me` with the `VERSION` build argument, which the Dockerfile writes into the binary so `/api/health` reports the release version.
After the first push, make the GHCR package public or give watchtower a token with `read:packages`, and record which choice was made.

## Maintenance calendar

- Twice a month (the 1st and 15th, 06:17 UTC) the release workflow rebuilds the latest tag and uploads a fresh TestFlight build.
  TestFlight builds expire after 90 days, so this keeps the newest one well inside the window.
  A failed run opens a GitHub issue titled `Release failed: <run>`.
- Each year renew the Apple Developer Program membership and the Apple Distribution certificate (valid one year), then update the two certificate secrets in both repositories and re-run `scripts/asc-setup.sh` so the profile is rebuilt against the new certificate.
- Each April Apple raises the minimum Xcode version for uploads.
  The workflow selects the newest Xcode on the runner image, so check the `macos-15` image and bump the runner or Flutter pin if the upload is rejected.
- When the App Store Connect API key is rotated, update `ASC_API_KEY_BASE64`, `ASC_KEY_ID` and `ASC_ISSUER_ID` in both repositories.
- Rotating `NEWME_APP_KEY` means changing the server `.env`, updating the secret, shipping a new build, and reinstalling on both phones.
