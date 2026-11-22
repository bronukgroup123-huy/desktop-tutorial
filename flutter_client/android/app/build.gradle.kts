import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties створює лише ручний workflow Android Store Bundle із секретів
// ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD.
// Звичайні тестові APK підписуються публічним app/test-signing.jks (рішення PO 2026-11-14),
// щоб оновлення ставились поверх попередніх. Store workflow передає Gradle-властивість
// requireReleaseSigning=true: без повного справжнього ключа така збірка падає, а не відкочується
// до тестового підпису.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val releasePropertyNames = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val configuredReleaseProperties = releasePropertyNames
    .filter { !keystoreProperties.getProperty(it).isNullOrBlank() }
val hasReleaseKey = configuredReleaseProperties.size == releasePropertyNames.size
val requireReleaseSigningValue = providers.gradleProperty("requireReleaseSigning").orNull
if (requireReleaseSigningValue != null && requireReleaseSigningValue !in setOf("true", "false")) {
    throw GradleException("requireReleaseSigning must be true or false")
}
val requireReleaseSigning = requireReleaseSigningValue == "true"

if (configuredReleaseProperties.isNotEmpty() && !hasReleaseKey) {
    val missing = releasePropertyNames.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    throw GradleException("Incomplete Android release signing configuration: missing ${missing.joinToString()}")
}
if (requireReleaseSigning && !hasReleaseKey) {
    throw GradleException(
        "Store release signing is required, but android/key.properties is missing or incomplete",
    )
}
if (hasReleaseKey && !file(keystoreProperties.getProperty("storeFile")).isFile) {
    throw GradleException("Configured Android release keystore file does not exist")
}

android {
    namespace = "ua.mushroomradar.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications («Час повертатися», батарея — ADR-022) потребує desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Остаточний ID застосунку до першої публікації в Google Play.
        applicationId = "ua.mushroomradar.app"
        // MapLibre Native (офлайн карта, ADR-020) — Android 7.0+.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("testing") {
            storeFile = file("test-signing.jks")
            storePassword = "mushroom-radar-test"
            keyAlias = "mushroom-radar-test"
            keyPassword = "mushroom-radar-test"
        }
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release")
                            else signingConfigs.getByName("testing")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Сповіщення «Почалась хвиля» (ADR-015 §15.8 п.19): Firebase вмикається, лише коли CI поклав
// android/app/google-services.json (секрет GOOGLE_SERVICES_JSON). Без нього збірка як раніше,
// застосунок працює без push.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
