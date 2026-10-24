import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { load(it) }
    }
}

val releaseStoreFile = file("keystore.jks")
val releaseStorePassword = localProperties.getProperty("storePassword")
val releaseKeyAlias = localProperties.getProperty("keyAlias")
val releaseKeyPassword = localProperties.getProperty("keyPassword")
val hasReleaseSigning = releaseStoreFile.exists() &&
    releaseStorePassword != null &&
    releaseKeyAlias != null &&
    releaseKeyPassword != null

android {
    namespace = "com.kfusion.app"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndkVersion.get()

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.kfusion.app"
        minSdk = flutter.minSdkVersion
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            applicationIdSuffix = ".dev"
        }

        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
                applicationIdSuffix = ".dev"
            }

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    sourceSets {
        // Unit tests live under android/tests/ instead of each module's src/test.
        getByName("test").java.setSrcDirs(listOf("../tests/app"))
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

// Packaged APKs must keep their manifest-declared classes; a namespace/class
// mismatch here crashes the app before any UI, and unit tests cannot see it.
val checkReleaseApk by tasks.registering(Exec::class) {
    group = "verification"
    description = "Runs tool/check_apk.py over the packaged release APKs."
    dependsOn("packageRelease")
    val python =
        if (System.getProperty("os.name").lowercase().contains("win")) "python" else "python3"
    commandLine(python, "--version")
    doFirst {
        val apkDir = layout.buildDirectory.dir("outputs/apk/release").get().asFile
        val apks =
            apkDir
                .walkTopDown()
                .filter { it.isFile && it.extension == "apk" }
                .sortedBy { it.path }
                .toList()
        check(apks.isNotEmpty()) {
            "checkReleaseApk: no release APK under ${apkDir.path}; packageRelease must run first"
        }
        commandLine(
            listOf(python, rootProject.file("../tool/check_apk.py").absolutePath) +
                apks.map { it.absolutePath },
        )
    }
}

tasks.named("assembleRelease") { dependsOn(checkReleaseApk) }

dependencies {
    implementation(project(":service"))
    implementation(project(":common"))
    implementation(project(":core"))
    implementation(project(":singbox"))
    implementation(libs.core.splashscreen)
    implementation(libs.gson)
    implementation(libs.smali.dexlib2) {
        exclude(group = "com.google.guava", module = "guava")
    }
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
