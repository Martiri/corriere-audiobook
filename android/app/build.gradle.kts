import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.franco.corriere_audiobook"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.franco.corriere_audiobook"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            // Environment variables take precedence (used in GitHub Actions CI/CD)
            val envKeystorePath = System.getenv("KEYSTORE_PATH")
            val envStorePass = System.getenv("KEYSTORE_PASSWORD")
            val envKeyAlias = System.getenv("KEY_ALIAS")
            val envKeyPass = System.getenv("KEY_PASSWORD")

            val propKeyPath = keystoreProperties.getProperty("storeFile")
            val propStorePass = keystoreProperties.getProperty("storePassword")
            val propKeyAlias = keystoreProperties.getProperty("keyAlias")
            val propKeyPass = keystoreProperties.getProperty("keyPassword")

            val finalKeystorePath = envKeystorePath 
                ?: propKeyPath 
                ?: "keystore/release-key.jks"

            val keystoreFile = file(finalKeystorePath)
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = envStorePass ?: propStorePass ?: "corriere_audio_pass2026"
                keyAlias = envKeyAlias ?: propKeyAlias ?: "corrierekey"
                keyPassword = envKeyPass ?: propKeyPass ?: "corriere_audio_pass2026"
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (releaseSigning.storeFile?.exists() == true) {
                releaseSigning
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}
