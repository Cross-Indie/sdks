pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "crossindie-android"
include(":crossindie")          // View SDK (no dependencies besides the Kotlin stdlib)
include(":crossindie-compose")  // optional Jetpack Compose wrapper
include(":sample")              // demo app (not published)
