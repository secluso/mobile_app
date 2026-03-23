plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val requiredKeystoreKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val allowUnsignedRelease =
    providers.environmentVariable("SECLUSO_ALLOW_UNSIGNED_RELEASE").orNull == "1"
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
    val releaseBehavior = if (allowUnsignedRelease) {
        "Unsigned release builds are enabled for verification."
    } else {
        "Debug builds will still work."
    }
    logger.warn("Android release signing disabled ($missingParts). $releaseBehavior")
}

gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.name.contains("Release", ignoreCase = true) }
    if (wantsRelease && !hasValidKeystore && !allowUnsignedRelease) {
        val missingParts = if (keystorePropertiesFile.exists()) {
            "missing keys: ${missingKeystoreKeys.joinToString(", ")}"
        } else {
            "missing key.properties"
        }
        throw org.gradle.api.GradleException(
            "Release build requires signing config ($missingParts). " +
                "Create key.properties with storeFile, storePassword, keyAlias, keyPassword, " +
                "or set SECLUSO_ALLOW_UNSIGNED_RELEASE=1 for a verification-only unsigned build."
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
        // Device Farm runs the screenshot pass through Android instrumentation, so we need a real instrumentation
        // runner here instead of relying on Flutter's normal app entry only
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets {
        getByName("androidTest") {
            assets.srcDir(project.file("../../tool"))
        }
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
    // Keep these AndroidX test libs on versions that work nicely with the rest
    // of the Flutter / Gradle stack already in this app. 
    //
    // In practice, we only need these:
    // - runner: actually launches the instrumentation process on Device Farm
    // - ext:junit: normal JUnit4 
    // - core: small Android test utilities
    // - uiautomator: gives us device-level screenshots and app launching
    androidTestImplementation("androidx.test:runner:1.2.0")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test:core:1.5.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}
