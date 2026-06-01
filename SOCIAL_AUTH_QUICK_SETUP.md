# Quick Setup Checklist for Social Authentication

## What's Already Done ✅

- Flutter code implemented for Apple and Google Sign-In
- iOS entitlements configured for Apple Sign-In
- Google Sign-In URL scheme placeholder added to Info.plist
- Dependencies installed and configured
- Build scripts updated to inject credentials

## What You Need to Do 📋

### 1. Apple Sign-In (iOS Only)

**Apple Developer Portal:**
1. Add "Sign In with Apple" capability to your App ID (`com.dlovric.wcpredict2026`)
2. Create a Service ID (`com.dlovric.wcpredict2026.auth`)
3. Create a Sign In with Apple Key and download the .p8 file
4. Note your Team ID and Key ID

**Supabase Dashboard:**
1. Enable Apple provider
2. Add Service ID, Team ID, Key ID, and paste the .p8 file content

### 2. Google Sign-In

**Google Cloud Console:**
1. Create OAuth consent screen
2. Create 3 OAuth Client IDs:
   - iOS Client (Bundle ID: `com.dlovric.wcpredict2026`)
   - Android Client (Package: `com.dlovric.wcpredict2026`, add debug SHA-1)
   - Web Client (for server verification)
3. Note the Web Client ID and Secret

**Supabase Dashboard:**
1. Enable Google provider
2. Add Web Client ID and Secret

**Your .env file:**
```bash
GOOGLE_SERVER_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
IOS_REVERSED_CLIENT_ID=com.googleusercontent.apps.your-ios-client-id
```

**iOS Info.plist:**
Replace `REPLACE_WITH_REVERSED_IOS_CLIENT_ID` with your actual reversed iOS client ID

### 3. Supabase Redirect URLs

Add these to Authentication → URL Configuration:
- `com.dlovric.wcpredict2026://` (iOS + Android)

## Testing

### iOS
- Must use real device (Apple Sign-In won't work in simulator)
- Run: `cd ios && pod install && cd .. && ./run.sh`

### Android
- Can use emulator or device
- Run: `./run.sh`

## Common Issues

- **Apple Sign-In not available**: Use real iOS device, not simulator
- **Google Sign-In error 10**: Add your debug SHA-1 to Google Console
- **Google Sign-In iOS not working**: Check reversed client ID in Info.plist

## Full Details

See `SOCIAL_AUTH_SETUP.md` for complete step-by-step instructions with screenshots references.