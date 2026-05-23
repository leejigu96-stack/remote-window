allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// F 드라이브는 외장 USB라 Kotlin incremental cache 가 자주 깨짐
// → D 내장 드라이브로 빌드 산출물 redirect
val sharedBuildRoot = file("D:/remote-window_client_build")
sharedBuildRoot.mkdirs()
rootProject.layout.buildDirectory.set(sharedBuildRoot)

subprojects {
    project.layout.buildDirectory.set(file("$sharedBuildRoot/${project.name}"))
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
