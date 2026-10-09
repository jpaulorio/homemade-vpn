# Brazil Exit - Flutter controller source (starter, not prebuilt APK/IPA)

This is the editable application layer for **AWS EC2 power management**, not a new VPN or a replacement for Tailscale. First sign-in uses Cognito + OAuth code/PKCE; afterward the main screen presents one large circular start/stop button.

## Platform projects

Android and iOS projects are included. The Android Internet permission and AppAuth redirect scheme, and iOS URL scheme are already configured for `brazilexit://oauth`. Run `flutter pub get` from this folder. Requires Flutter, Android tooling for Android, and Xcode plus Apple signing for iOS.

## Run on Android

Replace placeholders using Terraform flutter_config output values:

```bash
flutter run \
 --dart-define=API_BASE_URL=https://YOUR_API_ID.execute-api.sa-east-1.amazonaws.com \
 --dart-define=COGNITO_ISSUER=https://cognito-idp.sa-east-1.amazonaws.com/sa-east-1_YOUR_POOL \
 --dart-define=COGNITO_CLIENT_ID=YOUR_APP_CLIENT
```

Android installable APK, on a trusted development machine:

```bash
flutter build apk --release --dart-define=API_BASE_URL=... --dart-define=COGNITO_ISSUER=... --dart-define=COGNITO_CLIENT_ID=...
```

iOS: run `flutter build ios` on a Mac with Xcode and a valid development team/signing identity; use Xcode deployment or TestFlight for your wife's phone. IPA files cannot be built on a Linux host.

## Security notes

- Do not place AWS access keys, Lambda secrets, Tailscale auth keys, or EC2 IAM credentials in the app.
- The Cognito app client ID and API URL are public configuration, not secrets.
- API Gateway requires a valid Cognito **access token** with an `openid` scope.
- Only admins can create Cognito users because self-sign-up is disabled.
- Platform projects are generated and configured; physical-device authentication and cloud operations still require deployment and signing.
- For true failover on mobiles, a separate native VPN integration (beyond this Flutter controller) would be necessary.

After Terraform apply, run `python3 scripts/configure_app.py` from the repository root, then use `flutter run --dart-define-from-file=config.json` here.
