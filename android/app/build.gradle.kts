plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import groovy.json.JsonSlurper
import java.util.Properties
import java.io.FileInputStream
import org.gradle.jvm.tasks.Jar

fun androidDevDependencyPluginNames(flutterProjectDir: File): Set<String> {
    val pluginsFile = flutterProjectDir.resolve(".flutter-plugins-dependencies")
    if (!pluginsFile.exists()) {
        return emptySet()
    }

    val parsed = JsonSlurper().parseText(pluginsFile.readText()) as? Map<*, *> ?: return emptySet()
    val plugins = (parsed["plugins"] as? Map<*, *>) ?: return emptySet()
    val androidPlugins = plugins["android"] as? List<*> ?: return emptySet()

    return androidPlugins.mapNotNull { plugin ->
        val pluginMap = plugin as? Map<*, *> ?: return@mapNotNull null
        val isDevDependency = pluginMap["dev_dependency"] as? Boolean ?: false
        if (isDevDependency) pluginMap["name"] as? String else null
    }.toSet()
}

fun stripReleaseOnlyDevPluginsFromRegistrant(
    projectLogger: org.gradle.api.logging.Logger,
    appProjectDir: File,
    flutterProjectDir: File,
) {
    val devPluginNames = androidDevDependencyPluginNames(flutterProjectDir)
    if (devPluginNames.isEmpty()) {
        return
    }

    val registrantFile = appProjectDir.resolve("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
    if (!registrantFile.exists()) {
        return
    }

    var content = registrantFile.readText()
    var changed = false
    for (pluginName in devPluginNames) {
        val pattern = Regex(
            """(?ms)^\s*try \{\R\s*flutterEngine\.getPlugins\(\)\.add\(new .*?\);\R\s*\} catch \(Exception e\) \{\R\s*Log\.e\(TAG, "Error registering plugin ${Regex.escape(pluginName)}, .*?\);\R\s*\}\R?"""
        )
        val updated = content.replace(pattern, "")
        if (updated != content) {
            changed = true
            content = updated
        }
    }

    if (changed) {
        registrantFile.writeText(content)
        projectLogger.lifecycle(
            "Stripped release-only dev dependency plugins from GeneratedPluginRegistrant: " +
                devPluginNames.joinToString(", ")
        )
    }
}

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
    compileSdk = 36
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
        minSdk = 23
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

tasks.matching { it.name == "compileReleaseJavaWithJavac" }.configureEach {
    doFirst {
        stripReleaseOnlyDevPluginsFromRegistrant(
            projectLogger = logger,
            appProjectDir = projectDir,
            flutterProjectDir = rootProject.projectDir.parentFile,
        )
    }
}

tasks.withType<Jar>().configureEach {
    if (name.startsWith("packJniLibsflutterBuild")) {
        isPreserveFileTimestamps = false
        isReproducibleFileOrder = true
    }
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
