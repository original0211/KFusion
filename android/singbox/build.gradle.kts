import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.net.URI
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import javax.inject.Inject

plugins {
    id("com.android.library")
}

android {
    namespace = "com.kfusion.singbox"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndkVersion.get()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

// libbox ships no prebuilt AAR: it is bound from the pinned sing-box source
// with sing-box's own build_libbox tool, which needs the SagerNet gomobile
// fork at the version sing-box's Makefile pins for the same tag.
val singBoxVersion = "1.14.4"
val singBoxTarballUrl =
    "https://github.com/SagerNet/sing-box/archive/refs/tags/v$singBoxVersion.tar.gz"
val singBoxTarballSha256 = "0958ccd23b1ea9a141d715d15478b1e040fd04bcca19d8ff5529636b1b753e18"
val sagernetGomobileVersion = "v0.1.13"

val gomobileTargetByPlatform =
    linkedMapOf("android-arm" to "android/arm", "android-arm64" to "android/arm64", "android-x64" to "android/amd64")
val gomobileTargets =
    (rootProject.findProperty("target-platform") as String?)
        ?.split(",")
        ?.map { gomobileTargetByPlatform[it.trim()] ?: throw GradleException("No libbox for Flutter target platform $it") }
        ?: emptyList()

val isWindows = System.getProperty("os.name").startsWith("Windows")

val goExecutablePath =
    providers.provider {
        val name = if (isWindows) "go.exe" else "go"
        val home = System.getProperty("user.home")
        val searchPath =
            System.getenv("PATH").orEmpty().split(File.pathSeparator) +
                listOf("/opt/homebrew/bin", "/usr/local/bin", "/usr/local/go/bin", "$home/go/bin")
        searchPath
            .filter { it.isNotEmpty() }
            .map { File(it, name) }
            .firstOrNull { it.canExecute() }
            ?.path
            ?: throw GradleException("The libbox build needs Go on PATH")
    }

// build_libbox locates gomobile in $GOPATH/bin, so the tools and the module
// cache live in one build-local GOPATH instead of the developer's.
val goWorkPath = layout.buildDirectory.dir("gopath")

abstract class DownloadSingBoxSource : DefaultTask() {
    @get:Inject
    abstract val execOperations: ExecOperations

    @get:Input
    abstract val version: Property<String>

    @get:Input
    abstract val tarballUrl: Property<String>

    @get:Input
    abstract val tarballSha256: Property<String>

    @get:OutputFile
    abstract val tarball: RegularFileProperty

    @get:OutputDirectory
    abstract val sourceDirectory: DirectoryProperty

    @TaskAction
    fun download() {
        val tarballFile = tarball.get().asFile
        if (!tarballFile.isFile || sha256(tarballFile) != tarballSha256.get()) {
            tarballFile.parentFile.mkdirs()
            URI(tarballUrl.get()).toURL().openStream().use { input ->
                tarballFile.outputStream().use { output -> input.copyTo(output) }
            }
            val digest = sha256(tarballFile)
            if (digest != tarballSha256.get()) {
                throw GradleException("sing-box source tarball sha256 mismatch: $digest")
            }
        }
        val target = sourceDirectory.get().asFile
        target.deleteRecursively()
        target.mkdirs()
        execOperations.exec {
            commandLine(
                "tar",
                "xzf",
                tarballFile.path,
                "-C",
                target.path,
                "--strip-components=1",
            )
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

abstract class InstallGomobile : DefaultTask() {
    @get:Inject
    abstract val execOperations: ExecOperations

    @get:Internal
    abstract val goExecutable: Property<String>

    @get:Input
    abstract val gomobileVersion: Property<String>

    @get:Internal
    abstract val goPath: DirectoryProperty

    @get:OutputDirectory
    abstract val binDirectory: DirectoryProperty

    @TaskAction
    fun install() {
        val go = goExecutable.get()
        val bin = binDirectory.get().asFile
        bin.mkdirs()
        val path =
            listOf(File(go).parentFile, bin)
                .joinToString(File.pathSeparator) { it.path } + File.pathSeparator + System.getenv("PATH").orEmpty()
        for (tool in listOf("gomobile", "gobind")) {
            execOperations.exec {
                environment("PATH", path)
                environment("GOPATH", goPath.get().asFile.path)
                environment("GOBIN", bin.path)
                commandLine(go, "install", "github.com/sagernet/gomobile/cmd/$tool@${gomobileVersion.get()}")
            }
        }
    }
}

abstract class BindLibbox : DefaultTask() {
    @get:Inject
    abstract val execOperations: ExecOperations

    @get:Inject
    abstract val fileSystemOperations: FileSystemOperations

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val sources: ConfigurableFileCollection

    @get:Internal
    abstract val sourceDirectory: DirectoryProperty

    @get:Internal
    abstract val goExecutable: Property<String>

    @get:Input
    abstract val goVersion: Property<String>

    @get:Input
    abstract val version: Property<String>

    @get:Input
    abstract val targets: ListProperty<String>

    @get:Internal
    abstract val goPath: DirectoryProperty

    @get:Internal
    abstract val sdkDirectory: DirectoryProperty

    @get:Internal
    abstract val ndkDirectory: DirectoryProperty

    @get:OutputFile
    abstract val aar: RegularFileProperty

    @get:OutputFile
    abstract val classesJar: RegularFileProperty

    @TaskAction
    fun bind() {
        val go = goExecutable.get()
        val work = temporaryDir.resolve("sing-box")
        work.deleteRecursively()
        fileSystemOperations.sync {
            from(sourceDirectory)
            into(work)
        }
        val bin = goPath.get().dir("bin").asFile
        val path =
            listOf(bin, File(System.getProperty("java.home"), "bin"), File(go).parentFile)
                .joinToString(File.pathSeparator) { it.path } + File.pathSeparator + System.getenv("PATH").orEmpty()
        // build_libbox stamps the version from `git describe`, which the
        // tarball lacks; a throwaway repo restores the pinned tag as the stamp.
        for (command in listOf(
            listOf("git", "init", "-q"),
            listOf("git", "config", "user.email", "build@kfusion"),
            listOf("git", "config", "user.name", "KFusion Build"),
            listOf("git", "add", "-A"),
            listOf("git", "commit", "-qm", "sing-box v${version.get()}"),
            listOf("git", "tag", "v${version.get()}"),
        )) {
            execOperations.exec {
                workingDir(work)
                environment("PATH", path)
                commandLine(command)
                isIgnoreExitValue = true
            }
        }
        val args = mutableListOf("run", "./cmd/internal/build_libbox", "-target", "android")
        if (targets.get().isNotEmpty()) {
            args += listOf("-platform", targets.get().joinToString(","))
        }
        execOperations.exec {
            workingDir(work)
            environment("PATH", path)
            environment("GOPATH", goPath.get().asFile.path)
            environment("ANDROID_HOME", sdkDirectory.get().asFile.path)
            environment("ANDROID_NDK_HOME", ndkDirectory.get().asFile.path)
            environment("JAVA_HOME", System.getProperty("java.home"))
            commandLine(listOf(go) + args)
        }
        val built = work.resolve("libbox.aar")
        if (!built.isFile) throw GradleException("build_libbox produced no libbox.aar")
        aar.get().asFile.parentFile.mkdirs()
        classesJar.get().asFile.parentFile.mkdirs()
        built.copyTo(aar.get().asFile, overwrite = true)
        // The app already carries one go.Seq/go.Universe from the :core AAR:
        // a second copy cannot dex, and the fork's Seq differs from the stock
        // one only in an access flag that no generated code path calls.
        ZipFile(aar.get().asFile).use { aarFile ->
            ZipInputStream(aarFile.getInputStream(aarFile.getEntry("classes.jar"))).use { jar ->
                ZipOutputStream(classesJar.get().asFile.outputStream()).use { out ->
                    generateSequence { jar.nextEntry }.forEach { entry ->
                        if (entry.name.startsWith("go/")) return@forEach
                        out.putNextEntry(ZipEntry(entry.name).apply { time = entry.time })
                        out.write(jar.readBytes())
                    }
                }
            }
        }
    }
}

abstract class UnpackSingBoxJniLibs : DefaultTask() {
    @get:Inject
    abstract val archiveOperations: ArchiveOperations

    @get:Inject
    abstract val fileSystemOperations: FileSystemOperations

    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val aar: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun unpack() {
        var found = 0
        fileSystemOperations.sync {
            from(archiveOperations.zipTree(aar)) {
                include("jni/**")
                eachFile {
                    path = path.removePrefix("jni/")
                    if (name == "libgojni.so") {
                        name = "libbox.so"
                    }
                    if (name.endsWith(".so")) found++
                }
                includeEmptyDirs = false
            }
            into(outputDirectory)
        }
        if (found == 0) throw GradleException("libbox AAR has no native libraries")
    }
}

val downloadSingBoxSource =
    tasks.register<DownloadSingBoxSource>("downloadSingBoxSource") {
        version.set(singBoxVersion)
        tarballUrl.set(singBoxTarballUrl)
        tarballSha256.set(singBoxTarballSha256)
        tarball.set(layout.buildDirectory.file("downloads/sing-box-$singBoxVersion.tar.gz"))
        sourceDirectory.set(layout.buildDirectory.dir("singbox-src"))
    }

val installGomobile =
    tasks.register<InstallGomobile>("installGomobile") {
        goExecutable.set(goExecutablePath)
        gomobileVersion.set(sagernetGomobileVersion)
        goPath.set(goWorkPath)
        binDirectory.set(goWorkPath.map { it.dir("bin") })
    }

val bindLibbox =
    tasks.register<BindLibbox>("bindLibbox") {
        dependsOn(downloadSingBoxSource, installGomobile)
        sources.from(downloadSingBoxSource.flatMap { it.sourceDirectory })
        sourceDirectory.set(downloadSingBoxSource.flatMap { it.sourceDirectory })
        goExecutable.set(goExecutablePath)
        goVersion.set(
            goExecutablePath
                .flatMap { go -> providers.exec { commandLine(go, "env", "GOVERSION") }.standardOutput.asText }
                .map { it.trim() },
        )
        version.set(singBoxVersion)
        targets.set(gomobileTargets)
        goPath.set(goWorkPath)
        sdkDirectory.set(androidComponents.sdkComponents.sdkDirectory)
        ndkDirectory.set(androidComponents.sdkComponents.ndkDirectory)
        aar.set(layout.buildDirectory.file("gomobile/libbox.aar"))
        classesJar.set(layout.buildDirectory.file("gomobile/classes.jar"))
    }

androidComponents {
    onVariants { variant ->
        val unpack =
            tasks.register<UnpackSingBoxJniLibs>("unpack${variant.name.replaceFirstChar { it.uppercase() }}SingBoxJniLibs") {
                aar.set(bindLibbox.flatMap { it.aar })
            }
        variant.sources.jniLibs?.addGeneratedSourceDirectory(unpack, UnpackSingBoxJniLibs::outputDirectory)
    }
}

dependencies {
    implementation(files(bindLibbox.flatMap { it.classesJar }))
    implementation(project(":common"))
    implementation(libs.androidx.core)
}
