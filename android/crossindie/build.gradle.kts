plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    `maven-publish`
}

android {
    namespace = "com.crossindie.sdk"
    compileSdk = 35

    defaultConfig {
        minSdk = 21
        consumerProguardFiles("consumer-rules.pro")
        buildConfigField("String", "SDK_VERSION", "\"${project.version}\"")
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions { unitTests.isReturnDefaultValues = true }
    publishing {
        singleVariant("release") { withSourcesJar() }
    }
}

kotlin { jvmToolchain(17) }

dependencies {
    // No runtime dependencies: HttpURLConnection + org.json (both in the platform).
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303") // real org.json for JVM unit tests
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                groupId = project.group.toString()
                artifactId = "crossindie"
                version = project.version.toString()
                pom {
                    name.set("CrossIndie Android SDK")
                    description.set("Zero-dependency cross-promotion banner for Android apps.")
                    url.set("https://github.com/Cross-Indie/sdks")
                    licenses { license { name.set("MIT"); url.set("https://opensource.org/licenses/MIT") } }
                }
            }
        }
    }
}
