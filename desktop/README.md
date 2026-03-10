# SimSync Desktop

Flutter desktop prototype for SimSync.

## GitHub OAuth Setup

1. Create a GitHub OAuth App.
2. Set the callback URL to `http://127.0.0.1/callback`.
3. Run the app with `--dart-define` values for the OAuth credentials.

```bash
cd desktop
flutter run -d macos \
  --dart-define=SIMSYNC_GITHUB_CLIENT_ID=your_client_id \
  --dart-define=SIMSYNC_GITHUB_CLIENT_SECRET=your_client_secret
```

The desktop app opens the system browser for GitHub login, receives the callback on a loopback URL, and stores the session locally until logout or the 24-hour expiry time.
