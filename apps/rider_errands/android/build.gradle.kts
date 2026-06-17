allprojects {
    repositories {
        google()
        mavenCentral()
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
    // Force every Android sub-module (incl. transitive plugins) to compile against SDK 36.
    // Registered here (before evaluationDependsOn) so afterEvaluate runs in time.
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            androidExt.javaClass.methods
                .firstOrNull { it.name == "compileSdkVersion" && it.parameterCount == 1 && it.parameterTypes[0].name == "int" }
                ?.invoke(androidExt, 36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
