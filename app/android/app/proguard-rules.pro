# Flutter rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep native methods and FFI
-keepclasseswithmembernames class * {
    native <methods>;
}

# mobile_scanner / MLKit
-keep class com.google.mlkit.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }

# Suppress Play Core warnings for Flutter
-dontwarn com.google.android.play.core.**
