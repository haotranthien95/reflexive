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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Compile `file_picker`'s Kotlin sources. Without this the RELEASE BUILD DOES
// NOT LINK: :app:compileReleaseJavaWithJavac fails with `cannot find symbol
// FilePickerPlugin` from the Flutter-generated GeneratedPluginRegistrant.
//
// Why it is needed, and why only for this one subproject: this app builds on
// AGP 9.0.1 (settings.gradle.kts) with `android.builtInKotlin=false`
// (gradle.properties). file_picker 11.0.3's own android/build.gradle branches on
// the AGP version and, under AGP 9+, deliberately skips applying
// `org.jetbrains.kotlin.android` because it expects AGP's Built-in Kotlin to
// compile it instead. Its Android implementation is Kotlin-only, so with
// Built-in Kotlin off nothing compiles it at all. Every OTHER Kotlin plugin here
// (audioplayers, package_info_plus, …) applies KGP unconditionally and builds
// fine, so the gap is file_picker's alone — which is why this is scoped by name
// rather than fixed globally.
//
// **Flipping `android.builtInKotlin=true` instead does not work and was tried:**
// it fixes file_picker and then breaks every plugin that applies KGP explicitly,
// starting at `:audioplayers_android` with "'kotlin-android' plugin requires one
// of the Android Gradle plugins". The two halves of the plugin ecosystem
// currently want opposite settings; this narrows the exception to the one plugin
// on the far side of it.
//
// **Reversal trigger — the same one pubspec.yaml already names:** delete this
// block when `file_picker` 12.x leaves beta and the win32 overrides go with it.
// A 12.x on AGP 9 is expected to be Built-in-Kotlin-native, at which point this
// forces a KGP application that the plugin no longer wants.
subprojects {
    if (name == "file_picker") {
        plugins.withId("com.android.library") {
            apply(plugin = "org.jetbrains.kotlin.android")
            // file_picker sets Java source/target compatibility to 17 but only
            // sets the matching Kotlin jvmTarget on its non-AGP9 branch — the
            // branch we have just re-entered from the outside. Without this the
            // build fails on inconsistent JVM-target compatibility (Java 17 vs
            // Kotlin's default) rather than on the missing symbol.
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>("kotlin") {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
