plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.delamate.chat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.delamate.chat"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Inject our custom Application class via manifest placeholder.
        manifestPlaceholders["applicationName"] = "com.delamate.chat.DelamateApplication"
    }

    buildTypes {
        debug {
            // Debug builds are always larger; use release for distribution.
            isMinifyEnabled = false
        }
        release {
            // ── APK size: enable R8 code shrinking + resource shrinking ──────
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Signing with debug keys for now; replace with release keystore.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // ── APK size: compress native libs (saves ~5-15 MB) ─────────────────────
    // Android 6.0+ can load compressed .so files directly.
    packaging {
        jniLibs {
            useLegacyPackaging = false   // store libs uncompressed → smaller install
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
