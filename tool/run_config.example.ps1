# tool/run_config.example.ps1 — template for tool/run_config.ps1.
#
# Copy this file to tool/run_config.ps1 and fill in your real values.
# run_config.ps1 is gitignored; this example is safe to commit.
#
# The publishable (anon) key is designed for client use — RLS is the real
# security boundary. The service-role key must NEVER be put here.

$SupabaseUrl = 'https://YOUR-PROJECT-REF.supabase.co'
$SupabaseAnonKey = 'sb_publishable_YOUR_KEY'

# Google OAuth Web application client ID (ends in .apps.googleusercontent.com)
$GoogleServerClientId = 'YOUR-WEB-CLIENT-ID.apps.googleusercontent.com'

# Only needed for iOS/macOS builds; leave empty on Android-only work.
$GoogleIosClientId = ''
