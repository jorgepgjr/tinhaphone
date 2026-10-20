import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// O runner de integração pode desinstalar o aplicativo ao terminar.
// Um pacote separado impede que testes apaguem fotos da instalação normal.
val flutterTarget = (project.findProperty("target") as? String).orEmpty().replace('\\', '/')
// flutter test usa um listener temporário como target; sua flag identifica esse caso.
val dartDefines = (project.findProperty("dart-defines") as? String).orEmpty().split(',').map {
    runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrDefault("")
}
val isIntegrationTest = flutterTarget.startsWith("integration_test/") ||
    flutterTarget.contains("/integration_test/") ||
    dartDefines.any { it.startsWith("INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=") }

android {
    namespace = "com.example.tinhaphone"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (isIntegrationTest) "com.example.tinhaphone.integration" else "com.example.tinhaphone"
        manifestPlaceholders["appLabel"] = if (isIntegrationTest) "TinhaKids Testes" else "TinhaKids"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
