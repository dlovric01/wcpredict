# Apple Sign-In Key Setup

You're currently at the "Register a New Key" page. Follow these steps:

## On This Screen:

1. **Key Name**: Enter `WC2026 Sign In Key` (or any memorable name)

2. **Check the checkbox**: ✅ **Sign in with Apple**
   - This is the most important step!
   - You must check this box to enable Sign in with Apple capability

3. Click **Continue** button (top right)

## Next Screen:

After clicking Continue, you'll see:

1. A configuration screen for Sign in with Apple
2. You'll need to select your Primary App ID: `com.dlovric.wcpredict2026`
3. Click **Save**

## Final Screen:

1. Click **Continue** again
2. Click **Register**
3. **IMPORTANT**: Download the key file immediately!
   - You'll get a `.p8` file
   - This can only be downloaded once
   - Save it securely

## Information to Note:

After downloading, note down:
- **Key ID**: Shown on the screen (10-character string like "ABC123XYZ9")
- **Team ID**: Your Apple Developer Team ID (visible in top right of portal)
- **Key File**: The `.p8` file you downloaded

## For Supabase:

You'll need to add these to Supabase Dashboard:
1. Go to Authentication → Providers → Apple
2. Enable Apple provider
3. Fill in:
   - **Service ID**: `com.dlovric.wcpredict2026.auth` (you'll create this next)
   - **Team ID**: Your 10-character team ID
   - **Key ID**: The ID shown after key creation
   - **Secret Key**: Open the `.p8` file in a text editor and paste the entire content

## Next Steps:

After creating this key, you still need to:
1. Create a Service ID for the auth callback
2. Configure your App ID to have Sign in with Apple capability

Need help with the next steps? Let me know once you've downloaded the key!