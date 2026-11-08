plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.crossindie.sample"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.crossindie.sample"
        minSdk = 21
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        // ./gradlew :sample:installDebug -PciAppId=<uuid> [-PapiBase=http://10.0.2.2:8010]
        resValue("string", "ci_app_id", (project.findProperty("ciAppId") ?: "YOUR_APP_ID").toString())
        buildConfigField("String", "API_BASE", "\"${project.findProperty("apiBase") ?: "https://api.crossindie.com"}\"")
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":crossindie-compose"))
    implementation(platform("androidx.compose:compose-bom:2025.06.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
}
