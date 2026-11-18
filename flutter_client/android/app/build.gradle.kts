import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Підпис релізу: android/key.properties створює CI із секретів
// ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD.
// Без них — ТЕСТОВИЙ ключ app/test-signing.jks (рішення PO 2026-11-14): він у репозиторії,
// тож усі тестові APK мають однаковий підпис і ставляться поверх попередніх (раніше CI щоразу
// створював новий debug-ключ — «пакет недійсний»). Ключ публічний: для Google Play — лише
// справжній ключ із секретів.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

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
