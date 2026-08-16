import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material is supplied out of band through android/key.properties,
// which is gitignored and never committed. See README.md.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) {
        keyPropertiesFile.inputStream().use { load(it) }
    }
}
val releaseSigningAvailable = keyPropertiesFile.exists()

if (releaseSigningAvailable) {
    val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { keyProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "android/key.properties is missing required entries: $missing"
        )
    }
}

android {
    namespace = "com.suchsoftware.evaluetron.commander"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.suchsoftware.evaluetron.commander"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningAvailable) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The debug keystore is never used for a release build. Its key is
            // public knowledge, shared by every Flutter install, so signing with
            // it would let anyone forge an update to a client that holds
            // operator authority over the fleet.
            signingConfig = if (releaseSigningAvailable) {
                signingConfigs.getByName("release")
            } else {
                // Fail closed: an unsigned artifact cannot be installed or
                // shipped by accident, whereas a debug-signed one can.
                logger.warn(
                    "\n[evaluetron-commander] android/key.properties not found. " +
                        "The release build will be UNSIGNED.\n" +
                        "Supply storeFile, storePassword, keyAlias and keyPassword " +
                        "to produce an installable release. See README.md.\n"
                )
                null
            }
        }
    }
}

flutter {
    source = "../.."
}
