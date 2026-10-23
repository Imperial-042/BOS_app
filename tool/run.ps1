# run.ps1 — launch BOS with the Supabase + Google dart-defines applied.
#
# Config comes from tool/run_config.ps1 (gitignored — holds your keys).
# Copy tool/run_config.example.ps1 to tool/run_config.ps1 and fill in your
# values once. Then just run:
#
#   .\tool\run.ps1                 # run on the default/only device
#   .\tool\run.ps1 -Device emulator-5554
#   .\tool\run.ps1 -Release        # build the release APK instead of running
#
# Never commit run_config.ps1 — it is gitignored.

param(
  [string]$Device,
  [switch]$Release
)

# 'Stop' would make PowerShell treat flutter's harmless stderr *warnings*
# (Gradle/Kotlin deprecation notices) as fatal NativeCommandErrors. Keep
# Continue here; flutter's own exit code is what matters.
$ErrorActionPreference = 'Continue'

$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot

$configPath = Join-Path $PSScriptRoot 'run_config.ps1'
if (-not (Test-Path $configPath)) {
  Write-Host "Missing tool\run_config.ps1" -ForegroundColor Red
  Write-Host "Copy tool\run_config.example.ps1 to tool\run_config.ps1 and fill in your values." -ForegroundColor Yellow
  exit 1
}
. $configPath

$defines = @(
  "--dart-define=SUPABASE_URL=$SupabaseUrl",
  "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey",
  "--dart-define=GOOGLE_SERVER_CLIENT_ID=$GoogleServerClientId"
)

if ($GoogleIosClientId) {
  $defines += "--dart-define=GOOGLE_IOS_CLIENT_ID=$GoogleIosClientId"
}

if ($Release) {
  Write-Host "Building release APK..." -ForegroundColor Cyan
  & flutter build apk --release @defines
} else {
  $deviceArg = @()
  if ($Device) { $deviceArg = @('-d', $Device) }
  $target = if ($Device) { $Device } else { 'default device' }
  Write-Host "Running on $target..." -ForegroundColor Cyan
  & flutter run @deviceArg @defines
}

exit $LASTEXITCODE
