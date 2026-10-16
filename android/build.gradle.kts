allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
}

subprojects {
    // 仅对 :app 强制 androidx 版本。
    // 若对所有子模块生效，compileSdk 仍为 34 的插件模块（如 flutter_local_notifications）
    // 会因 core 1.15.0 的 AAR 元数据要求（需 compileSdk >= 35）而构建失败。
    if (path == ":app") {
        afterEvaluate {
            configurations.all {
                resolutionStrategy {
                    force("androidx.activity:activity:1.9.3")
                    force("androidx.core:core-ktx:1.15.0")
                    force("androidx.core:core:1.15.0")
                }
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // Only redirect build dir for subprojects under the same root (skip pub-cache plugins on different drives)
    if (project.projectDir.path.startsWith(rootProject.projectDir.path)) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
