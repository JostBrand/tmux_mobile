plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.jostbrandstetter.tmux_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires core library desugaring
        // (java.time backport usage).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "de.jostbrandstetter.tmux_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Stable release signing: the keystore lives on the workspace PVC
    // (/workspaces/.keystore/tmux_mobile-release.jks, password via the
    // KEYSTORE_PASSWORD env var). NEVER use the debug key for releases -
    // it is regenerated per pod (overlay HOME) and Android then refuses
    // updates with "App not updated" (signature mismatch).
    val keystoreFile = file(
        System.getenv("KEYSTORE_PATH") ?: "/workspaces/.keystore/tmux_mobile-release.jks",
    )
    if (keystoreFile.exists()) {
        signingConfigs {
            create("release") {
                storeFile = keystoreFile
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = "tmuxmobile"
                keyPassword = System.getenv("KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
