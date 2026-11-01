import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyFile = rootProject.file("key.properties")
val releaseKeys = Properties().apply {
    if (releaseKeyFile.isFile) releaseKeyFile.inputStream().use { load(it) }
}
val sourcePreview = providers.gradleProperty("wenkuSourcePreview").orNull == "true"
val profileProbe = providers.gradleProperty("wenkuProfileProbe").orNull == "true"
check(!profileProbe || gradle.startParameter.taskNames.any { it.contains("Profile") || it.contains("Debug") }) {
    "The API 26 runtime override is restricted to independent Profile/Debug probes"
}
val sourceProbe = providers.gradleProperty("wenkuSourceProbe").orNull == "true"
check(!sourceProbe || sourcePreview) { "Source probes are restricted to the independent source preview" }
val readerPreview = providers.gradleProperty("wenkuReaderPreview").orNull == "true" || sourcePreview
val readerWindowProbe = providers.gradleProperty("wenkuReaderWindowProbe").orNull == "true"
check(!readerWindowProbe || readerPreview) { "Reader window checks require an independent preview" }
val readerContentProbe = providers.gradleProperty("wenkuReaderContentProbe").orNull == "true"
check(!readerContentProbe || sourcePreview) { "Reader content checks require the independent source preview" }
val catalogProbe = providers.gradleProperty("wenkuCatalogProbe").orNull == "true"
check(!catalogProbe || readerPreview) { "Account read probes are restricted to the reader preview" }

android {
    namespace = "org.mewx.wenku8_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    // The separately authorized API runtime must remain byte-for-byte intact.
    // AGP otherwise strips its symbols even when jniLibs contains original files.
    packaging.jniLibs.keepDebugSymbols.add("**/libcpp.so")
    // 0.4 has no embedded content provider or its proprietary API runtime.
    packaging.jniLibs.excludes.add("**/libcpp.so")
    packaging.resources.excludes.add("META-INF/INDEX.LIST")

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "org.mewx.wenku8_flutter"
        // Unshrunk HtmlUnit includes MethodHandle branches requiring API 26.
        // The opt-in independent Profile probe can target the connected phone;
        // normal releases retain their existing minimum and R8 configuration.
        minSdk = if (profileProbe) maxOf(flutter.minSdkVersion, 26) else flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["wenkuAppLabel"] = "纸间文库"
        testInstrumentationRunner = "org.mewx.wenku8_flutter.SessionFixtureInstrumentation"
        if (catalogProbe) testInstrumentationRunner = "org.mewx.wenku8_flutter.CatalogReadInstrumentation"
        if (sourceProbe) testInstrumentationRunner = "org.mewx.wenku8_flutter.SourceFixtureInstrumentation"
        if (readerWindowProbe) testInstrumentationRunner = "org.mewx.wenku8_flutter.ReaderWindowInstrumentation"
        if (readerContentProbe) testInstrumentationRunner = "org.mewx.wenku8_flutter.ReaderContentAuditInstrumentation"
        // AGP otherwise builds upstream desktop utilities too, including the
        // DRM tool whose encryption code is intentionally disabled in this app.
        externalNativeBuild.cmake.targets.addAll(listOf("mobi", "wenku_mobi"))
    }
    if (catalogProbe || sourceProbe || readerWindowProbe || readerContentProbe) testBuildType = "release"

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    if (releaseKeyFile.isFile) {
        signingConfigs.create("distribution") {
            keyAlias = releaseKeys.getProperty("keyAlias")
            keyPassword = releaseKeys.getProperty("keyPassword")
            storeFile = rootProject.file(requireNotNull(releaseKeys.getProperty("storeFile")))
            storePassword = releaseKeys.getProperty("storePassword")
        }
    }

    buildTypes {
        getByName("debug") {
            // The integration runner uninstalls its package on completion.
            // Keep rendering probes separate from the user's release data.
            applicationIdSuffix = ".render_probe"
        }
        getByName("profile") {
            applicationIdSuffix = ".profile_probe"
        }
        release {
            proguardFile(file("document-import.pro"))
            proguardFile(file("book-sources.pro"))
            proguardFile(file("htmlunit-core-js.pro"))
            if (catalogProbe) proguardFile(file("catalog-probe.pro"))
            if (sourceProbe) proguardFile(file("source-probe.pro"))
            if (readerWindowProbe) proguardFile(file("reader-window-probe.pro"))
            if (readerPreview) {
                applicationIdSuffix = if (sourcePreview) ".source_preview" else ".reader_preview"
                manifestPlaceholders["wenkuAppLabel"] = if (sourcePreview) "纸间文库 · 书源预览" else "纸间文库 · 阅读预览"
            }
            // Local previews remain install-compatible. Public distributions
            // use an owner's untracked key.properties, never an embedded key.
            signingConfig = signingConfigs.getByName(
                if (releaseKeyFile.isFile && !readerPreview) "distribution" else "debug"
            )
        }
    }

    // Match the embedded API library to the Flutter code actually compiled for
    // this APK. Otherwise a one-ABI build advertises extra, unusable ABIs solely
    // because libcpp.so exists for them. Let Flutter own split-APK filtering.
    val targets = project.findProperty("target-platform")?.toString()
    if (targets != null && project.findProperty("split-per-abi")?.toString()?.toBoolean() != true) {
        val targetAbis = targets.split(",").map { platform ->
            when (platform) {
                "android-arm" -> "armeabi-v7a"
                "android-arm64" -> "arm64-v8a"
                "android-x64" -> "x86_64"
                else -> error("Unsupported Flutter target platform: $platform")
            }
        }
        buildTypes.configureEach {
            ndk.abiFilters.clear()
            ndk.abiFilters.addAll(targetAbis)
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
    // Match the pinned Reading parser: newer JSoup changes selector behavior.
    implementation("org.jsoup:jsoup:1.16.2")
    implementation("org.htmlunit:htmlunit-core-js:5.3.0-legado.4")
    implementation("com.jayway.jsonpath:json-path:3.0.0")
    implementation("com.google.code.gson:gson:2.14.0")
    implementation("cn.wanghaomiao:JsoupXpath:2.5.3")
    implementation("org.apache.commons:commons-text:1.13.1")
    implementation("cn.hutool:hutool-crypto:5.8.22")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.webkit:webkit:1.14.0")
    implementation("com.google.android.material:material:1.14.0")
    implementation("me.zhanghai.android.libarchive:library:1.1.6")
    implementation("com.github.liuyueyi.quick-chinese-transfer:quick-transfer-core:0.2.17")
    implementation("org.commonmark:commonmark:0.30.1")
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
    // Keep the media host classes available to the app's shared-engine wiring.
    implementation("androidx.media:media:1.7.0")
    testImplementation("junit:junit:4.13.2")
}

// Opt-in device fixtures use only self-authored, offline documents and rules.
if (sourceProbe) {
    android.sourceSets.getByName("main").java.srcDir("src/sourceProbe/kotlin")
    android.sourceSets.getByName("main").assets.srcDir("src/sourceProbe/assets")
}
