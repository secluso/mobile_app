plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val requiredKeystoreKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val missingKeystoreKeys = requiredKeystoreKeys.filter { key ->
    keystoreProperties.getProperty(key).isNullOrBlank()
}
val hasValidKeystore = keystorePropertiesFile.exists() && missingKeystoreKeys.isEmpty()
if (!hasValidKeystore) {
    val missingParts = if (keystorePropertiesFile.exists()) {
        "missing keys: ${missingKeystoreKeys.joinToString(", ")}"
    } else {
        "missing key.properties"
    }
    logger.warn("Android release signing disabled ($missingParts). Debug builds will still work.")
}

gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.name.contains("Release", ignoreCase = true) }
    if (wantsRelease && !hasValidKeystore) {
        val missingParts = if (keystorePropertiesFile.exists()) {
            "missing keys: ${missingKeystoreKeys.joinToString(", ")}"
        } else {
            "missing key.properties"
        }
        throw org.gradle.api.GradleException(
            "Release build requires signing config ($missingParts). " +
                "Create key.properties with storeFile, storePassword, keyAlias, keyPassword."
        )
    }
}

android {
    namespace = "com.secluso.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.secluso.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasValidKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (hasValidKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        } 
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.firebase:firebase-messaging:24.1.1")
    implementation("androidx.media3:media3-exoplayer:1.7.1")
    implementation("androidx.media3:media3-ui:1.7.1")
}
