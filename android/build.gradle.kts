plugins {
    id("com.android.application") version "8.13.2" apply false
    id("com.android.library") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.10" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.10" apply false
}

// JitPack (https://jitpack.io) builds this folder from the sdks repo root
// (see ../jitpack.yml) and sets VERSION to the git tag. Coordinates are
// com.github.Cross-Indie.sdks:<module>:<tag>.
allprojects {
    group = "com.github.Cross-Indie.sdks"
    version = System.getenv("VERSION")?.takeIf { it.isNotBlank() } ?: "1.2.0"
}
