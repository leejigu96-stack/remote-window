pluginManagement {
    val flutterSdkPath =
        run {
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
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

// ★모든 안드로이드 모듈 compileSdk 36 강제 (AGP9 가 일부 플러그인 34 컴파일을 거부 →
//   flutter_plugin_android_lifecycle 36 요구와 충돌). settings 의 gradle.afterProject 로
//   등록하면 각 프로젝트 평가 ★직후 적용돼 "already evaluated" 타이밍 문제 없음.
gradle.afterProject {
    val ext = extensions.findByName("android")
    if (ext != null) {
        val ms = ext.javaClass.methods
        val m = ms.firstOrNull {
            it.name == "compileSdkVersion" && it.parameterCount == 1 &&
                it.parameterTypes[0] == Int::class.javaPrimitiveType
        } ?: ms.firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
        m?.invoke(ext, 36)
    }
}
