plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services") // Firebase 플러그인
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.sharedalbumapp"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        applicationId = "com.example.sharedalbumapp"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ✅ 공용 debug.keystore 연결
    signingConfigs {
        create("teamDebug") {
            // 프로젝트 루트/keys/debug-team.keystore
            storeFile = file("../../keys/debug-team.keystore")
            storePassword = "android"
            keyAlias = "AndroidDebugKey"
            keyPassword = "android"
        }
        // release 서명키는 나중에 별도로 설정 (공유 금지)
        // create("releaseConfig") { ... }
    }

    buildTypes {
        // ✅ 디버그 빌드는 공용 debug.keystore 사용
        getByName("debug") {
            signingConfig = signingConfigs.getByName("teamDebug")
            // 필요시 디버그용 난독화/압축 비활성화 유지(기본)
            isMinifyEnabled = false
        }

        // ✅ 릴리즈는 일단 서명 미지정(나중에 release 키로 설정)
        getByName("release") {
            isMinifyEnabled = true
            // signingConfig = signingConfigs.getByName("releaseConfig") // 준비되면 사용
        }
    }

    packaging {
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}"
                    pickFirsts += setOf("**/libc++_shared.so")
         }
    }
}

flutter { source = "../.." }

dependencies {
    implementation("com.google.mediapipe:tasks-vision:0.10.+")
}
