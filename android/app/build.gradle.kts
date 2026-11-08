import java.util.Properties

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
            // Credentials: android/key.properties (git-ignored), else KEYSTORE_* env vars.
            // No defaults on purpose; with neither, storeFile stays unset and release builds fail.
            val props = java.util.Properties()
            rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { props.load(it) }
            val ksFile = props.getProperty("storeFile")?.let { rootProject.file(it) }
                ?: System.getenv("KEYSTORE_FILE")?.let { file(it) }
            val storePass = props.getProperty("storePassword") ?: System.getenv("KEYSTORE_PASSWORD")
            val alias = props.getProperty("keyAlias") ?: System.getenv("KEY_ALIAS")
            val keyPass = props.getProperty("keyPassword") ?: System.getenv("KEY_PASSWORD")
            if (ksFile != null && ksFile.exists() && storePass != null && alias != null && keyPass != null) {
                storeFile = ksFile
                storePassword = storePass
                keyAlias = alias
                keyPassword = keyPass
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
