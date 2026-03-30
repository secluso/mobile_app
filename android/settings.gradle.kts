import groovy.json.JsonSlurper
import org.gradle.api.Action
import java.io.File
import java.util.Base64
import org.gradle.api.Project
import org.gradle.api.plugins.ExtraPropertiesExtension

pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("com.android.application") version "8.7.0" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

fun decodeDartDefines(rawValue: String?): Map<String, String> {
    if (rawValue.isNullOrBlank()) {
        return emptyMap()
    }
    return rawValue
        .split(',')
        .mapNotNull { encoded ->
            if (encoded.isBlank()) {
                return@mapNotNull null
            }
            val normalized = encoded.padEnd((encoded.length + 3) / 4 * 4, '=')
            val decoded = String(Base64.getUrlDecoder().decode(normalized))
            val separator = decoded.indexOf('=')
            if (separator <= 0) {
                return@mapNotNull null
            }
            decoded.substring(0, separator) to decoded.substring(separator + 1)
        }
        .toMap()
}

fun isFdroidBuild(): Boolean {
    if (System.getenv("SECLUSO_FDROID_BUILD") == "1") {
        return true
    }
    val dartDefines =
        decodeDartDefines(
            gradle.startParameter.projectProperties["dart-defines"]
                ?: System.getProperty("dart-defines")
        )
    return dartDefines["SECLUSO_FDROID_BUILD"] == "true"
}

class SeclusoNativePluginLoader(
    private val excludeAndroidPluginNames: Set<String>,
) {
    private var parsedFlutterPluginsDependencies: Map<String, Any>? = null

    fun getPlugins(flutterSourceDirectory: File): List<Map<String, Any>> {
        val meta = dependenciesMetadata(flutterSourceDirectory)
        val pluginsMap = meta["plugins"] as? Map<*, *> ?: return emptyList()
        val androidPluginsUntyped = pluginsMap["android"] as? List<*> ?: return emptyList()

        val nativePlugins = mutableListOf<Map<String, Any>>()
        androidPluginsUntyped.forEach { androidPluginUntyped ->
            val androidPlugin = androidPluginUntyped as? Map<*, *> ?: return@forEach
            val name = androidPlugin["name"] as? String ?: return@forEach
            val isDevDependency = androidPlugin["dev_dependency"] as? Boolean ?: false
            if (isDevDependency) {
                return@forEach
            }
            if (excludeAndroidPluginNames.contains(name)) {
                return@forEach
            }
            val needsBuild = androidPlugin["native_build"] as? Boolean ?: true
            if (needsBuild) {
                @Suppress("UNCHECKED_CAST")
                nativePlugins.add(androidPlugin as Map<String, Any>)
            }
        }
        return nativePlugins.toList()
    }

    fun dependenciesMetadata(flutterSourceDirectory: File): Map<String, Any> {
        if (parsedFlutterPluginsDependencies != null) {
            return parsedFlutterPluginsDependencies!!
        }

        val pluginsDependencyFile =
            File(flutterSourceDirectory, ".flutter-plugins-dependencies")
        val readText = JsonSlurper().parseText(pluginsDependencyFile.readText())
        @Suppress("UNCHECKED_CAST")
        val parsedText = readText as? Map<String, Any>
            ?: error("Parsed JSON is not a Map<String, Any>: $readText")

        if (excludeAndroidPluginNames.isEmpty()) {
            parsedFlutterPluginsDependencies = parsedText
            return parsedText
        }

        val mutableMeta = parsedText.toMutableMap()
        val plugins = (mutableMeta["plugins"] as? Map<*, *>)?.toMutableMap() ?: mutableMapOf()
        val filteredAndroidPlugins =
            ((plugins["android"] as? List<*>) ?: emptyList<Any>()).filterNot { pluginUntyped ->
                val pluginMap = pluginUntyped as? Map<*, *> ?: return@filterNot false
                val name = pluginMap["name"] as? String ?: return@filterNot false
                val isDevDependency = pluginMap["dev_dependency"] as? Boolean ?: false
                isDevDependency || excludeAndroidPluginNames.contains(name)
            }
        plugins["android"] = filteredAndroidPlugins
        mutableMeta["plugins"] = plugins

        val filteredDependencyGraph =
            ((mutableMeta["dependencyGraph"] as? List<*>) ?: emptyList<Any>()).mapNotNull { dependencyUntyped ->
                val dependencyMap =
                    (dependencyUntyped as? Map<*, *>)?.toMutableMap() ?: return@mapNotNull null
                val name = dependencyMap["name"] as? String ?: return@mapNotNull null
                if (name == "integration_test" || excludeAndroidPluginNames.contains(name)) {
                    return@mapNotNull null
                }
                val dependencies =
                    ((dependencyMap["dependencies"] as? List<*>) ?: emptyList<Any>())
                        .filterNot { dependencyName ->
                            dependencyName is String &&
                                (dependencyName == "integration_test" ||
                                    excludeAndroidPluginNames.contains(dependencyName))
                        }
                dependencyMap["dependencies"] = dependencies
                dependencyMap
            }
        mutableMeta["dependencyGraph"] = filteredDependencyGraph

        parsedFlutterPluginsDependencies = mutableMeta
        return mutableMeta
    }
}

open class SeclusoFlutterProjectDefaults {
    val compileSdkVersion: Int = 36
    val ndkVersion: String = "27.0.12077973"
    val minSdkVersion: Int = 23
    val targetSdkVersion: Int = 36
    val versionCode: Int = 1
    val versionName: String = "1.0"
}

val flutterSdkPath = run {
    val properties = java.util.Properties()
    file("local.properties").inputStream().use { properties.load(it) }
    properties.getProperty("flutter.sdk")
        ?: error("flutter.sdk not set in local.properties")
}
val fdroidBuild = isFdroidBuild()
val excludedAndroidPlugins =
    if (fdroidBuild) setOf("firebase_core", "firebase_messaging") else emptySet()
val nativePluginLoader = SeclusoNativePluginLoader(excludedAndroidPlugins)
val flutterProjectDefaults = SeclusoFlutterProjectDefaults()
extra["flutterSdkPath"] = flutterSdkPath
extra["nativePluginLoader"] = nativePluginLoader
gradle.beforeProject(
    object : Action<Project> {
        override fun execute(project: Project) {
            project.extensions.getByType(ExtraPropertiesExtension::class.java).apply {
                set("nativePluginLoader", nativePluginLoader)
                if (!has("flutter")) {
                    set("flutter", flutterProjectDefaults)
                }
            }
        }
    }
)

include(":app")

if (fdroidBuild) {
    logger.lifecycle("Configuring special F-Droid Android build without Firebase Android plugins")
}

nativePluginLoader.getPlugins(settingsDir.parentFile).forEach { androidPlugin ->
    val pluginDirectory = File(androidPlugin["path"] as String, "android")
    check(pluginDirectory.exists()) {
        "Plugin directory does not exist: ${pluginDirectory.absolutePath}"
    }
    val pluginName = androidPlugin["name"] as String
    include(":$pluginName")
    project(":$pluginName").projectDir = pluginDirectory
}
