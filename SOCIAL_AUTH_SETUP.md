# Social Authentication Setup Guide (Mobile Only)

This guide walks you through setting up Apple Sign-In and Google Sign-In for your WC2026 Predict mobile app.

## Prerequisites

- Access to [Apple Developer Account](https://developer.apple.com) (for Apple Sign-In)
- Access to [Google Cloud Console](https://console.cloud.google.com) (for Google Sign-In)
- Access to [Supabase Dashboard](https://app.supabase.com) for your project

## Table of Contents
1. [Apple Sign-In Setup](#apple-sign-in-setup)
2. [Google Sign-In Setup](#google-sign-in-setup)
3. [Supabase Configuration](#supabase-configuration)
4. [Environment Variables](#environment-variables)
5. [Testing](#testing)

---

## Apple Sign-In Setup

### 1. Apple Developer Portal Configuration

1. **Sign in** to [Apple Developer Portal](https://developer.apple.com/account)

2. **Navigate to Certificates, Identifiers & Profiles** → **Identifiers**

3. **Find your app identifier** (`com.dlovric.wcpredict2026`) or create it if it doesn't exist:
   - Click the **+** button
   - Select **App IDs** and click **Continue**
   - Select **App** and click **Continue**
   - Enter Description: `WC2026 Predict`
   - Enter Bundle ID: `com.dlovric.wcpredict2026`
   - **Important**: Scroll down and check **Sign In with Apple** capability
   - Click **Continue** then **Register**

4. **Configure Sign In with Apple**:
   - Click on your app identifier (`com.dlovric.wcpredict2026`)
   - Next to **Sign In with Apple**, click **Configure**
   - Enable it as a **Primary App ID**
   - Click **Save**

5. **Create a Service ID** (for Supabase backend):
   - Go back to **Identifiers** and click **+**
   - Select **Services IDs** and click **Continue**
   - Enter Description: `WC2026 Predict Auth`
   - Enter Identifier: `com.dlovric.wcpredict2026.auth`
   - Click **Continue** then **Register**

6. **Configure the Service ID**:
   - Click on the Service ID you just created
   - Check **Sign In with Apple**
   - Click **Configure**
   - Primary App ID: Select `com.dlovric.wcpredict2026`
   - Domains and Subdomains: Add your Supabase project domain (e.g., `yourproject.supabase.co`)
   - Return URLs: Add `https://yourproject.supabase.co/auth/v1/callback`
   - Click **Next** then **Done** then **Save**

7. **Create a Sign In with Apple Key**:
   - Go to **Keys** and click **+**
   - Enter Key Name: `WC2026 Sign In Key`
   - Check **Sign In with Apple**
   - Click **Configure** next to Sign In with Apple
   - Select your Primary App ID: `com.dlovric.wcpredict2026`
   - Click **Save**, then **Continue**, then **Register**
   - **Download the key file** (you'll need this `.p8` file for Supabase)
   - Note down the **Key ID** shown on the screen

8. **Note your Team ID**:
   - You can find this in the top right corner of the developer portal
   - Or go to **Membership** in the sidebar

### Required Information from Apple:
- **Team ID**: (10-character ID, e.g., `ABC123DEF4`)
- **Service ID**: `com.dlovric.wcpredict2026.auth`
- **Key ID**: (10-character ID from the key you created)
- **Private Key**: (Contents of the downloaded `.p8` file)

---

## Google Sign-In Setup

### 1. Google Cloud Console Configuration

1. **Sign in** to [Google Cloud Console](https://console.cloud.google.com)

2. **Create or select a project** for your app

3. **Configure OAuth Consent Screen**:
   - Go to **APIs & Services** → **OAuth consent screen**
   - Choose **External** user type
   - Click **Create**
   - Fill in the required information:
     - App name: `WC2026 Predict`
     - User support email: Your email
     - App logo: Upload your app icon if desired
     - Developer contact: Your email
   - Click **Save and Continue**
   - **Scopes**: Add `email` and `profile` scopes
   - Click **Save and Continue** through remaining steps

4. **Create OAuth 2.0 Client IDs**:

   **For iOS:**
   - Go to **APIs & Services** → **Credentials**
   - Click **+ Create Credentials** → **OAuth client ID**
   - Application type: **iOS**
   - Name: `WC2026 iOS Client`
   - Bundle ID: `com.dlovric.wcpredict2026`
   - App Store ID (optional): Leave blank for now
   - Team ID (optional): Leave blank for now
   - Click **Create**
   - Note down the **iOS Client ID**

   **For Android:**
   - Click **+ Create Credentials** → **OAuth client ID**
   - Application type: **Android**
   - Name: `WC2026 Android Client`
   - Package name: `com.dlovric.wcpredict2026`
   - SHA-1 certificate fingerprint: 
     ```bash
     # For debug key (development):
     keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
     
     # Copy the SHA-1 fingerprint and paste it
     ```
   - Click **Create**
   - Note down the **Android Client ID**

   **For Server/Backend (Required for mobile apps):**
   - Click **+ Create Credentials** → **OAuth client ID**
   - Application type: **Web application**
   - Name: `WC2026 Server Client`
   - Authorized JavaScript origins:
     - `https://yourproject.supabase.co`
   - Authorized redirect URIs:
     - `https://yourproject.supabase.co/auth/v1/callback`
   - Click **Create**
   - Note down the **Client ID** and **Client Secret** (you'll need both for Supabase)

### Required Information from Google:
- **Web/Server Client ID**: (for Flutter app and Supabase)
- **Web/Server Client Secret**: (for Supabase configuration)
- **iOS Client ID**: (for iOS configuration)
- **Reversed iOS Client ID**: Reverse the iOS client ID for URL scheme
  - Example: If iOS Client ID is `123456789-abc.apps.googleusercontent.com`
  - Reversed would be: `com.googleusercontent.apps.123456789-abc`

---

## Supabase Configuration

### 1. Configure Apple Provider

1. **Sign in** to your [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Go to **Authentication** → **Providers**
4. Find **Apple** and click **Enable**
5. Fill in the configuration:
   - **Client ID (Services ID)**: `com.dlovric.wcpredict2026.auth`
   - **Secret Key**: Paste the entire content of your downloaded `.p8` file
   - **Team ID**: Your 10-character Apple Team ID
   - **Key ID**: The Key ID from Apple Developer Portal
6. Click **Save**

### 2. Configure Google Provider

1. In **Authentication** → **Providers**
2. Find **Google** and click **Enable**
3. Fill in the configuration:
   - **Client ID**: Your Web/Server Client ID from Google Cloud Console
   - **Client Secret**: Your Web/Server Client Secret from Google Cloud Console
   - **Authorized Client IDs**: Add both your iOS and Android Client IDs (optional, for extra security)
4. Click **Save**

### 3. Update Redirect URLs

1. Go to **Authentication** → **URL Configuration**
2. Add to **Redirect URLs**:
   - `com.dlovric.wcpredict2026://` (iOS + Android)

---

## Environment Variables

Update your `.env` file with the OAuth credentials:

```bash
# Existing Supabase config
SUPABASE_URL=https://yourproject.supabase.co
SUPABASE_ANON_KEY=your-anon-key

# Google Sign-In (Web/Server Client ID is used in the Flutter app)
GOOGLE_SERVER_CLIENT_ID=123456789-abc.apps.googleusercontent.com  # Web/Server Client ID
IOS_REVERSED_CLIENT_ID=com.googleusercontent.apps.123456789-def   # Reversed iOS Client ID
```

### Update iOS Configuration

Replace the placeholder in `ios/Runner/Info.plist`:

Find this line:
```xml
<string>com.googleusercontent.apps.REPLACE_WITH_REVERSED_IOS_CLIENT_ID</string>
```

Replace with your actual reversed iOS client ID:
```xml
<string>com.googleusercontent.apps.123456789-def</string>
```

---

## Testing

### iOS Testing

1. **Clean and rebuild**:
   ```bash
   flutter clean
   cd ios && pod install && cd ..
   ./run.sh
   ```

2. **Test on real device** (Apple Sign-In requires a real device, won't work in simulator)

3. **Verify in Xcode**: 
   - Open `ios/Runner.xcworkspace` in Xcode
   - Check that "Sign in with Apple" capability is enabled
   - Ensure your development team is selected

### Android Testing

1. **Clean and rebuild**:
   ```bash
   flutter clean
   ./run.sh
   ```

2. **For release builds**, you'll need to:
   - Create a release keystore
   - Generate SHA-1 for the release key:
     ```bash
     keytool -list -v -keystore path/to/release.keystore -alias your-alias
     ```
   - Add the release SHA-1 fingerprint to Google Cloud Console
   - Update `android/key.properties` with your keystore details

### Common Issues and Solutions

**Apple Sign-In Issues:**
- **"Sign in with Apple isn't available"** → You're testing on a simulator; use a real device
- **"Invalid client"** → Check Service ID configuration in Apple Developer Portal
- **"The operation couldn't be completed"** → Ensure Bundle ID matches exactly
- **No response after authentication** → Check redirect URLs in Supabase

**Google Sign-In Issues:**
- **"Developer error (code 10)"** → SHA-1 fingerprint mismatch:
  - Get your current debug SHA-1: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`
  - Add it to Google Cloud Console
- **"Invalid client ID"** → You're using the wrong client ID; use the Web/Server Client ID in Flutter
- **"Sign in failed (12500)"** → OAuth consent screen not properly configured
- **iOS: Google Sign-In not working** → Ensure reversed client ID is correctly set in Info.plist

**Supabase Issues:**
- **"Provider not enabled"** → Enable the provider in Supabase Dashboard
- **"Invalid callback"** → Add redirect URLs in Supabase URL Configuration
- **"User already exists"** → User previously signed in with different provider; handle account linking

---

## Production Checklist

Before releasing to production:

### iOS
- [ ] Test Apple Sign-In on a real device
- [ ] Verify Bundle ID matches exactly in Apple Developer Portal
- [ ] Test with TestFlight build

### Android
- [ ] Add production SHA-1 fingerprint to Google Console
- [ ] Test with release build
- [ ] Verify package name matches exactly

### Google OAuth
- [ ] Move OAuth consent screen from "Testing" to "Production"
- [ ] Add production SHA-1 fingerprints for all release variants
- [ ] Test on multiple Android devices

### General
- [ ] Test the full auth flow: sign in, sign out, and app restart
- [ ] Handle edge cases: network errors, cancelled sign-in
- [ ] Verify user profile is created with display name
- [ ] Test deep linking back to app after authentication

---

## Security Notes

- Never commit API keys or secrets to version control
- Use environment variables for sensitive configuration
- The Web/Server Client ID is safe to include in your app (it's public)
- Keep your Google Client Secret secure (only used in Supabase)
- Keep your Apple private key (.p8 file) secure

---

## Support

If you encounter issues:

1. **Check logs:**
   - Flutter: `flutter logs`
   - Xcode: View console output during run
   - Android Studio: Logcat output

2. **Verify configuration:**
   - All IDs and keys match exactly (no extra spaces)
   - Bundle IDs and package names are correct
   - SHA-1 fingerprints are from the correct keystore

3. **Resources:**
   - [Supabase Auth Documentation](https://supabase.com/docs/guides/auth/social-login/auth-apple)
   - [Apple Sign-In Documentation](https://developer.apple.com/sign-in-with-apple/)
   - [Google Sign-In Flutter Plugin](https://pub.dev/packages/google_sign_in)