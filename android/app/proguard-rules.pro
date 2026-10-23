-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Google Sign-In (Credential Manager) — keep the play-services pathway used
# by google_sign_in on Android 13 and below so release (R8) builds can still
# resolve credentials.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
  *;
}