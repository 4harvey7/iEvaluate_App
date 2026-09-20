# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google / Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Supabase / PostgREST
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# UCrop
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# Core Desugaring
-keep class j$.** { *; }
-dontwarn j$.**

# Keep Native method names and signatures for JNI
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve line numbers and source attributes for symbolication
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable
