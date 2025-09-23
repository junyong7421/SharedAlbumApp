import com.android.build.gradle.LibraryExtension
import javax.xml.parsers.DocumentBuilderFactory

plugins {
    id("com.android.application") version "8.7.3" apply false // ✅ 버전 맞추기
    id("com.google.gms.google-services") version "4.3.15" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 🔁 빌드 디렉토리 커스텀 설정
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    plugins.withId("com.android.library") {
        val ext = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?: return@withId

        if (ext.namespace.isNullOrEmpty()) {
            val manifestFile = file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                val doc = javax.xml.parsers.DocumentBuilderFactory.newInstance()
                    .newDocumentBuilder()
                    .parse(manifestFile)
                val pkg = doc.documentElement.getAttribute("package")
                if (!pkg.isNullOrEmpty()) {
                    ext.namespace = pkg
                    println("Applied namespace '$pkg' to project '$name'")
                }
            }
        }
    }
}