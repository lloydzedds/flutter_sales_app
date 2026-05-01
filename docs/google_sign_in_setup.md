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

## Run with the Web client ID

```powershell
flutter run -d ZD222J7GJC --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Without the Google Cloud OAuth clients, Android builds still compile, but
interactive Google sign-in can fail with a client configuration error.
