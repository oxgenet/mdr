// Versions are pinned so the Android build does not silently move under the
// Rust core it links. Bump them deliberately, the way Cargo.toml is bumped.
plugins {
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
