plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.ievaluateapp_final"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications 22 (its own module enables
        // desugaring and pulls desugar_jdk_libs 2.1.4; the app module must
        // match or the build fails on java.time usage).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.ievaluateapp_final"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // ── Release keystore ──────────────────────────────────────────────
            // Defaults to the local keystore/release.jks created during setup.
            // Override with environment variables for CI/CD:
            //   KEYSTORE_FILE     – path to your .jks / .keystore file
            //   KEYSTORE_PASSWORD – store password
            //   KEY_ALIAS         – key alias
            //   KEY_PASSWORD      – key password
            val ksFile = System.getenv("KEYSTORE_FILE") ?: "keystore/release.jks"
            if (file(ksFile).exists()) {
                storeFile = file(ksFile)
                storePassword = System.getenv("KEYSTORE_PASSWORD") ?: "ievaluate2026"
                keyAlias = System.getenv("KEY_ALIAS") ?: "ievaluate"
                keyPassword = System.getenv("KEY_PASSWORD") ?: "ievaluate2026"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Use release keystore when available; fall back to debug for local dev.
            val releaseSigning = signingConfigs.findByName("release")
            signingConfig = if (releaseSigning?.storeFile != null) {
                releaseSigning
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
