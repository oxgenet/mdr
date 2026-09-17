import org.gradle.internal.os.OperatingSystem

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

/**
 * ABIs to cross-compile and package. Both by default: `arm64-v8a` for phones,
 * `x86_64` so an emulator can run the instrumented tests.
 *
 * Narrow it with `-PrustAbis=x86_64` when only one is needed. The CI emulator
 * job does exactly that — it installs a single Rust target, so building the
 * other ABI would fail before a test ever ran.
 */
val rustAbis: List<String> =
    (project.findProperty("rustAbis") as String?)
        ?.split(",")
        ?.map { it.trim() }
        ?.filter { it.isNotEmpty() }
        ?: listOf("arm64-v8a", "x86_64")

/** Repository root — the Cargo workspace lives one level above `android/`. */
val repoRoot: File = rootProject.projectDir.parentFile

/**
 * Build `libmdr.so` for each ABI straight into `jniLibs`.
 *
 * The feature set is exactly the one the iOS shell links (`--no-default-features
 * --features svg`): the rendering core plus the shell bindings, no desktop
 * backend. Pass `-PskipRustBuild` to reuse the `.so` files already in place —
 * CI builds them in a separate step, and it keeps Kotlin-only edits fast.
 */
val buildRustCore by tasks.registering(Exec::class) {
    group = "build"
    description = "Cross-compile the Rust rendering core into app/src/main/jniLibs"
    workingDir = repoRoot
    val cargo = if (OperatingSystem.current().isWindows) "cargo.exe" else "cargo"
    val args = mutableListOf(cargo, "ndk")
    rustAbis.forEach { args += listOf("-t", it) }
    args += listOf(
        "-o", file("src/main/jniLibs").absolutePath,
        "build", "--release", "--lib",
        "--no-default-features", "--features", "svg",
    )
    commandLine(args)
    // The Rust sources decide whether this needs to rerun.
    inputs.dir(File(repoRoot, "src"))
    inputs.file(File(repoRoot, "Cargo.toml"))
    outputs.dir(file("src/main/jniLibs"))
    onlyIf { !project.hasProperty("skipRustBuild") }
}

android {
    namespace = "net.oxge.mdr"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "net.oxge.mdr"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "0.4.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += rustAbis }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    // BuildConfig.VERSION_NAME is asserted against the version the Rust core
    // reports, so a stale libmdr.so fails a test instead of shipping.
    buildFeatures { buildConfig = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
        getByName("test").java.srcDirs("src/test/kotlin")
        getByName("androidTest").java.srcDirs("src/androidTest/kotlin")
    }

    testOptions {
        // The JVM unit tests cover pure Kotlin only — anything touching the
        // Rust core has to run on a device, so it lives in androidTest.
        unitTests.isReturnDefaultValues = true
    }
}

tasks.named("preBuild") { dependsOn(buildRustCore) }

dependencies {
    testImplementation("junit:junit:4.13.2")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core-ktx:1.6.1")
}
