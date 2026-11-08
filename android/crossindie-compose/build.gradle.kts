plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    `maven-publish`
}

android {
    namespace = "com.crossindie.sdk.compose"
    compileSdk = 35
    defaultConfig { minSdk = 21 }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    publishing {
        singleVariant("release") { withSourcesJar() }
    }
}

kotlin { jvmToolchain(17) }

dependencies {
    api(project(":crossindie"))
    // Only the Compose UI runtime (AndroidView interop); your app's BOM wins.
    implementation(platform("androidx.compose:compose-bom:2025.06.01"))
    implementation("androidx.compose.ui:ui")
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                groupId = project.group.toString()
                artifactId = "crossindie-compose"
                version = project.version.toString()
                pom {
                    name.set("CrossIndie Android SDK - Jetpack Compose")
                    description.set("Compose wrapper for the CrossIndie cross-promotion banner.")
                    url.set("https://github.com/Cross-Indie/sdks")
                    licenses { license { name.set("MIT"); url.set("https://opensource.org/licenses/MIT") } }
                }
            }
        }
    }
}
