# Google Sign-In Setup

Sale Buddy uses Google Sign-In plus the Google Drive `appDataFolder` scope to
save and restore the local SQLite database for the signed-in Google account.

## Google Cloud setup

1. Create or open a Google Cloud project.
2. Enable the Google Drive API.
3. Configure the OAuth consent screen.
4. Create an Android OAuth client:
   - Package name: `com.example.flutter_application_1`
   - Debug SHA-1 for this machine:
     `CF:BD:50:02:FE:5B:33:30:4D:A1:D7:05:6D:88:33:A4:2E:91:A5:C0`
5. Create a Web OAuth client and copy its client ID.

## Add test users while the app is in testing

If Google shows `Access blocked: Sale Buddy has not completed the Google
verification process`, the selected Gmail account is not allowed to test this
OAuth app yet.

In Google Cloud Console:

1. Open the Sale Buddy project.
2. Go to Google Auth Platform > Audience.
3. Under Test users, add every Gmail account you will use on test devices.
4. Save the changes, wait a few minutes, then try signing in again.

For public release, complete Google's OAuth verification instead of relying on
test users.

## Production readiness checklist

There is no Google PIN to add to the app. Public login depends on the Google
Cloud OAuth consent screen, OAuth clients, scopes, and app verification status.

Before moving to production:

1. Use a real Android package name instead of the default example package.
2. Create the release Android OAuth client with the production package name and
   the SHA-1 from the release or Google Play app signing certificate.
3. Keep the Web OAuth client ID and pass it with `GOOGLE_WEB_CLIENT_ID` for
   release builds.
4. Keep the requested scope limited to Google Drive app data unless a new
   feature truly needs broader access.
5. Publish a public app home page, privacy policy page, and terms page on a
   domain you own.
6. Verify that domain in Google Search Console and add it to the OAuth consent
   screen authorized domains.
7. Fill in Branding, Audience, Data access, and developer contact details in
   Google Auth Platform.
8. Submit the app for Google OAuth verification if the console requires it.
9. After approval, change the OAuth publishing status from Testing to
   Production so users outside the test list can sign in.

For Google review, prepare:

- App name and app logo.
- Support email and developer contact email.
- Public home page URL.
- Public privacy policy URL.
- Public terms URL.
- Short explanation of why Sale Buddy needs Google Drive app data access.
- A test account or review instructions if Google asks for app access.

A ready-to-fill review packet is available at
`docs/google_review/google_review_packet.md`. Draft public pages are available
in `docs/public_site/`.

Current owner details:

- Support email: `lloydzeddsss@gmail.com`
- Developer contact email: `lloydzedds@gmail.com`
- Planned public domain: `salebuddy.com`

Good production package name examples:

- `com.salebuddy.app` if you own and verify `salebuddy.com`
- `com.salebuddy.sales`
- `com.salebuddy.pos`
- `com.lloydzedds.salebuddy`

To get the production SHA-1 from Google Play, create the app in Play Console,
enable Play App Signing, then open Test and release > Setup > App integrity and
copy the SHA-1 under App signing key certificate. For a local release keystore,
run:

```powershell
keytool -list -v -keystore "C:\path\to\upload-keystore.jks" -alias upload
```

## Add the Web client ID to the app build

For local testing, the app currently includes a development Web client ID in
`AccountSyncService`.

To override it at run time, pass your Web client ID with `--dart-define`:

```powershell
flutter run -d ZD222J7GJC --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Replace `YOUR_WEB_CLIENT_ID` with the Web OAuth client ID ending in
`.apps.googleusercontent.com`.

For release builds, include the same define:

```powershell
flutter build apk --release --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Then open Settings in the app and use `Sign in with Google`.

Without the Google Cloud OAuth clients, Android builds still compile, but
interactive Google sign-in can still fail with a client configuration error.
