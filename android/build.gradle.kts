allprojects {
    repositories {
        // The legado fork of htmlunit-core-js is vendored, not published.
        maven {
            url = uri(rootProject.file("../third_party/maven"))
            content { includeModule("org.htmlunit", "htmlunit-core-js") }
        }
        google()
        mavenCentral()
        maven {
            url = uri("https://jitpack.io")
            content { includeGroup("com.github.liuyueyi.quick-chinese-transfer") }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
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
