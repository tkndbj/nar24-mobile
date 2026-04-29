-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ── Firebase App Check + Play Integrity ──────────────────────────────────
# R8 in release builds strips/renames the provider classes that the
# Firebase App Check SDK looks up reflectively at runtime. Without these
# keeps, the native SDK reports "No AppCheckProvider installed" and
# Firestore returns PERMISSION_DENIED once enforcement is on.
-keep class com.google.firebase.appcheck.** { *; }
-keep interface com.google.firebase.appcheck.** { *; }
-keep class com.google.android.play.core.integrity.** { *; }
-keep class com.google.android.play.integrity.** { *; }
-dontwarn com.google.firebase.appcheck.**
-dontwarn com.google.android.play.core.integrity.**
-dontwarn com.google.android.play.integrity.**