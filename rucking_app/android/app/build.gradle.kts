plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.ruck.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Enable core library desugaring
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.ruck.app"
        // Setting minSdk to 26 as required by health plugin
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Enable core library desugaring for java.time.* APIs
        multiDexEnabled = true

        ndk {
            // Limit bundled ABIs to keep ffmpeg kit extraction time manageable
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }
    
    signingConfigs {
        create("release") {
            // You'll need to create a keystore file with these exact fingerprints
            // MD5: A2:92:06:F9:9F:B0:45:FE:59:40:40:39:03:AC:E0:8F
            // SHA-1: 83:F4:3A:6E:A5:07:C8:8E:A7:C1:95:D0:18:45:E1:34:EA:C7:48:EB
            // SHA-256: 13:F3:46:51:02:EF:5F:00:A0:1F:A4:CA:94:9D:C8:16:65:50:92:89:CD:4C:54:E5:26:B9:BB:ED:95:2B:CC:47
            storeFile = file("../keystore.jks")
            // Try to get password from environment variables first, then fall back to hardcoded values
            val envStorePassword = System.getenv("KEYSTORE_PASSWORD")
            val envKeyPassword = System.getenv("KEY_PASSWORD")
            
            storePassword = envStorePassword ?: "getruckypassword123" // The password you used in create-keystore.sh
            keyAlias = "upload"
            keyPassword = envKeyPassword ?: "getruckypassword123" // The password you used in create-keystore.sh
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Enable automatic debug symbol upload to Google Play Console
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // Required for ffmpeg kit to avoid long startup extraction stalls
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:33.14.0"))

    // Add Firebase Analytics without specifying version (uses BoM)
    implementation("com.google.firebase:firebase-analytics")

    // Add the dependencies for any other desired Firebase products
    // https://firebase.google.com/docs/android/setup#available-libraries
    
    // Core library desugaring for Java 8+ APIs
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // MultiDex support
    implementation("androidx.multidex:multidex:2.0.1")
}
