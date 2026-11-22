import java.util.Base64
import java.util.Properties

// The permanent release key (2026-11-13): an update must be signed with the same key as the installed app, or Android
// refuses it and only uninstalling (which deletes the app's data) helps. A release build is never signed with the debug
// key (security review PLAT-3, 2026-11-14). It is signed with the release key when android/key.properties points at
// it, or, with -P unsignedRelease=true, left unsigned for a separate signing step: the GitHub Actions workflow builds
// with no key on disk and signs with apksigner afterwards (SUP-1). With neither, a release build stops. Debug builds
// keep the debug key.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProperties.containsKey("storeFile")
val unsignedRelease = providers.gradleProperty("unsignedRelease").orNull == "true"

// Solace Home (docs/HOME_SERVER.md, owner 2026-11-19): a build made with --dart-define=SOLACE_HOME=true (Flutter hands
// the defines to Gradle base64-encoded in the dart-defines property) merges src/home/AndroidManifest.xml, the internet
// permission, into its release build. Every other build, the default air-gapped one included, never sees that file and
// has no internet permission in release.
// Dart takes the last SOLACE_HOME define when one is given twice, so Gradle does the same (review N-07, 2026-11-19).
val solaceHome = (providers.gradleProperty("dart-defines").orNull ?: "").split(",").mapNotNull {
    runCatching<String> { String(Base64.getDecoder().decode(it.trim()), Charsets.UTF_8) }.getOrNull()
}.lastOrNull { it.startsWith("SOLACE_HOME=") } == "SOLACE_HOME=true"

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.personal.solace"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (reminders) needs library desugaring (its README; the second Android build
        // stopped on it, 2026-11-13)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.personal.solace"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // sherpa-onnx (voice) ships ONNX Runtime 1.28.2 and flutter_onnxruntime (the safety classifier) pulls in 1.28.0;
    // one copy is packaged. Patch releases of the same minor version share one C interface, so both work with either
    // (checked 2026-11-13: the first Android build stopped on the duplicate). The interface is shared but the symbols
    // are versioned: the kept copy is sherpa-onnx's 1.28.2, while flutter_onnxruntime's 1.28.0 Java binding asks for
    // VERS_1.28.0, which made the app crash at start (traffic test 2026-11-14). The task below makes the binding ask for
    // the version that is packaged.
    packaging {
        jniLibs {
            pickFirsts += "lib/*/libonnxruntime.so"
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
        }
    }

    // debug and profile builds already carry the internet permission (Flutter's tools need it); only a Home release
    // build gains it, from its own manifest
    if (solaceHome) {
        sourceSets.getByName("release").manifest.srcFile("src/home/AndroidManifest.xml")
    }
}

// stops a release build that would come out neither signed with the release key nor deliberately unsigned
val releaseSigningCheck = tasks.register("releaseSigningCheck") {
    val signable = hasReleaseKey || unsignedRelease
    doLast {
        if (!signable) {
            throw GradleException(
                "A release build needs the release key (android/key.properties) or -P unsignedRelease=true for a " +
                    "separate signing step; it is never signed with the debug key."
            )
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach { dependsOn(releaseSigningCheck) }

// ONNX Runtime's 1.28.0 Java binding is matched to the 1.28.2 runtime that is packaged (docs/security/
// traffic_test_2026-11-14.md; tools/android/fix_ort_jni_version.py checks every imported symbol first and refuses
// otherwise). Runs on the merged native libraries, before they are stripped and packaged; a build where the pair
// cannot be matched stops here rather than shipping an app that crashes at start. Then every library beside the kept
// runtime is checked as it is (--check), the patched binding included: sherpa-onnx's libraries need VERS_1.28.2, so a
// pickFirst that kept another runtime stops the build too (round 3, R3-5).
tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("NativeLibs")) {
        val script = rootProject.file("../../tools/android/fix_ort_jni_version.py")
        doLast {
            fun matchRuntime(lib: File, runtime: File, checkOnly: Boolean) {
                val cmd = listOf("python3", script.path, lib.path, runtime.path) + if (checkOnly) listOf("--check") else listOf()
                // the script's report goes to the build log (inheritIO would send it to the Gradle daemon's own output)
                val p = ProcessBuilder(cmd).redirectErrorStream(true).start()
                val report = p.inputStream.bufferedReader().readText()
                val rc = p.waitFor()
                report.lines().filter { it.isNotBlank() }.forEach { logger.lifecycle("ONNX Runtime link check: $it") }
                check(rc == 0) { "${lib.path} does not link with the packaged ONNX Runtime ${runtime.path} (exit $rc)" }
            }
            outputs.files.asFileTree.matching { include("**/libonnxruntime.so") }.forEach { runtime ->
                val jni = File(runtime.parentFile, "libonnxruntime4j_jni.so")
                if (jni.exists()) matchRuntime(jni, runtime, checkOnly = false)
                runtime.parentFile.listFiles()!!.filter { it.name.endsWith(".so") && it.name != runtime.name }.sorted()
                    .forEach { matchRuntime(it, runtime, checkOnly = true) }
            }
        }
    }
}

// R8 (release builds) must leave ONNX Runtime's Java classes alone: its native binding finds them by name, and a renamed
// or removed class aborts the app at the safety classifier's first message (proguard-rules.pro, 2026-11-14, L-5). The
// names are the ones libonnxruntime4j_jni.so 1.28.0 looks up (strings in the library); the build stops if R8 renamed
// any ai.onnxruntime class or left one of these out.
val ortClassesUsedByName = listOf("MapInfo", "NodeInfo", "OnnxMap", "OnnxModelMetadata", "OnnxSequence",
    "OnnxSparseTensor", "OnnxTensor", "OnnxValue", "OrtException", "SequenceInfo", "TensorInfo", "ValueInfo")
tasks.configureEach {
    if (name.startsWith("minify") && name.endsWith("WithR8")) {
        doLast {
            val maps = outputs.files.asFileTree.matching { include("**/mapping.txt") }.files
            check(maps.isNotEmpty()) { "$name wrote no mapping.txt, so ONNX Runtime's classes cannot be checked" }
            maps.forEach { m ->
                // R8's own synthetic helpers (names with "$$", such as ...$$ExternalSyntheticLambda0) are not the library's
                val classes = m.readLines().filter { it.startsWith("ai.onnxruntime.") && it.endsWith(":") && "$$" !in it }
                    .map { it.removeSuffix(":").split(" -> ") }
                val renamed = classes.filter { it.size == 2 && it[0] != it[1] }.map { "${it[0]} -> ${it[1]}" }
                val kept = classes.filter { it.size == 2 && it[0] == it[1] }.map { it[0] }.toSet()
                val missing = ortClassesUsedByName.map { "ai.onnxruntime.$it" }.filter { it !in kept }
                check(renamed.isEmpty() && missing.isEmpty()) {
                    "R8 renamed or removed ONNX Runtime classes that its native code finds by name (${m.path}): " +
                        "renamed ${renamed.take(5)}, missing ${missing}; see app/android/app/proguard-rules.pro"
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
