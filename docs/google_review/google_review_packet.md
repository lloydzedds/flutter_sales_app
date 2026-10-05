# Sale Buddy Google OAuth Review Packet

Use this packet when filling Google Auth Platform branding, data access, and
verification forms. Replace every `TODO` before submitting.

## App Identity

- App name: Sale Buddy
- App logo: `assets/branding/sale_buddy_icon.png`
- App category: Business / sales and inventory management
- Android package name: TODO: choose the final production package name
- Current development package name: `com.example.flutter_application_1`
- Production support email: `lloydzeddsss@gmail.com`
- Developer contact email: `lloydzedds@gmail.com`

## Production Package Name

Recommended package name if you own `salebuddy.com`:

```text
com.salebuddy.app
```

Other valid examples:

```text
com.salebuddy.sales
com.salebuddy.pos
com.lloydzedds.salebuddy
```

Use a lowercase reverse-domain style name. Choose it before publishing to
Google Play, because changing the package/application ID later creates a
different Android app in Google Play and on users' devices.

## Public URLs

These URLs must be hosted publicly on a domain you own and can verify in Google
Search Console. Planned domain: `salebuddy.com`, if you can register and verify
it. Replace `https://YOUR_DOMAIN` with the final verified domain.

- Home page URL: `https://YOUR_DOMAIN/`
- Privacy policy URL: `https://YOUR_DOMAIN/privacy-policy.html`
- Terms URL: `https://YOUR_DOMAIN/terms.html`

Draft page files are available in:

- `docs/public_site/index.html`
- `docs/public_site/privacy-policy.html`
- `docs/public_site/terms.html`

## OAuth Scope Requested

Sale Buddy requests:

```text
https://www.googleapis.com/auth/drive.appdata
```

## Short Explanation For Google Review

Sale Buddy is a sales and inventory management app for small shops. Users can
record products, stock, customers, bills, sales, returns, and store details.

The app requests Google Drive app data access only so a signed-in user can save,
restore, download, and delete a private Sale Buddy backup file tied to their
Google account. The backup is stored in Google Drive's hidden app data folder
and is used only by Sale Buddy for account-based backup and restore.

Sale Buddy does not request access to the user's visible Google Drive files,
does not browse or modify the user's regular Drive documents, and does not share
Google user data with third parties. Users can continue without a Google account
and keep data only on their device.

## Longer Explanation For Data Access Form

Sale Buddy uses the Google Drive `appDataFolder` scope to provide optional cloud
backup and restore. When a user signs in with Google, the app stores each Google
account's local Sale Buddy database separately. If the user taps "Save Backup to
Google", Sale Buddy uploads one SQLite backup file named
`sale_buddy_sales.db` to the Google Drive app data folder. If the user taps
"Restore from Google", the app downloads that same backup file and restores the
user's Sale Buddy records on the device.

The app data folder scope is the narrowest Drive permission that supports this
feature. Sale Buddy does not need or request permission to view, list, edit, or
delete the user's normal Google Drive files. The app only reads and writes its
own backup file in its own app data storage.

The user can delete the cloud backup from Accounts and Backup > Manage My Cloud
Data > Delete Cloud Backup. The user can also continue without an account, in
which case data remains local to the device.

## Review Instructions For Google

Use these instructions if Google asks how to test the app.

1. Install and open Sale Buddy.
2. On the welcome screen, review and accept the legal terms.
3. Tap "Sign in or Sign up with Google".
4. Choose a Google account.
5. Complete the store setup screen or tap Skip.
6. Open Accounts > Accounts and Backup.
7. Tap "Save Backup to Google" to create a Google Drive app data backup.
8. Tap "Restore from Google" to restore the latest backup.
9. Tap "Manage My Cloud Data" to view, download, or delete the cloud backup.
10. To test local-only use, reinstall or clear app data, then choose
    "Continue without account" on the welcome screen.

## Test Account

TODO: If Google asks for a test account, provide one of these:

- A Google test user already added in Google Auth Platform > Audience, or
- Instructions telling reviewers to use their own Google account after the app
  is published/verified.

Do not include a real password in this repository.

## Google Cloud Console Values

Use these values in Google Auth Platform.

- App name: Sale Buddy
- User support email: `lloydzeddsss@gmail.com`
- App logo: upload `assets/branding/sale_buddy_icon.png`
- Application home page: TODO: public home page URL
- Application privacy policy: TODO: public privacy policy URL
- Application terms of service: TODO: public terms URL
- Authorized domain: TODO: your verified domain
- Developer contact email: `lloydzedds@gmail.com`
- User type: External
- Publishing status for public launch: Production
- Scope: `https://www.googleapis.com/auth/drive.appdata`

## Release SHA-1 Fingerprint

If you publish through Google Play with Play App Signing, use the SHA-1 from
Google Play Console:

1. Open Google Play Console.
2. Select the Sale Buddy app.
3. Go to Test and release > Setup > App integrity.
4. Open the App signing tab or section.
5. Copy the SHA-1 from App signing key certificate.
6. Use that package name and SHA-1 in the production Android OAuth client in
   Google Cloud Console.

If you are testing a release APK locally before Play signing, use your release
keystore SHA-1:

```powershell
keytool -list -v -keystore "C:\path\to\upload-keystore.jks" -alias upload
```

If you have not created the release/upload keystore yet, create that first.
After Google Play App Signing is enabled, the Play app signing SHA-1 is the one
most users will need for Google sign-in from the Play Store build.

## Items Needed From Owner

Before final submission, the app owner must provide:

- Final production package name.
- Release SHA-1 certificate fingerprint.
- Support email: `lloydzeddsss@gmail.com`.
- Developer contact email: `lloydzedds@gmail.com`.
- Domain name for the public pages, probably `salebuddy.com`.
- Confirmation that the public pages are hosted and reachable without login.
- Confirmation that the domain is verified in Google Search Console.

## Notes

The policy text in `docs/public_site` is a practical draft for app review and
user disclosure. Have it reviewed by a qualified legal professional before
launching publicly.
