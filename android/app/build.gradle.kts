import java.util.Properties
import java.io.FileInputStream
import java.io.File

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// 铁律 1: 持久化 Release 签名配置加载
// 保证后续每次打包 APK 签名完全一致，避免签名不匹配导致覆盖安装失败或数据清空
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val isReleaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
val allowDebugSigning = (project.findProperty("ALLOW_DEBUG_SIGNING") as String?)
    ?.equals("true", ignoreCase = true) == true
if (isReleaseTaskRequested && !keystorePropertiesFile.exists() && !allowDebugSigning) {
    throw GradleException(
        "Release build blocked: missing android/key.properties. " +
            "Provide release keystore config or pass -PALLOW_DEBUG_SIGNING=true for local testing."
    )
}

val appVersionName = (project.findProperty("APP_VERSION_NAME") as String?) ?: "1.0.8"
val appVersionCode = (project.findProperty("APP_VERSION_CODE") as String?)?.toIntOrNull() ?: 9

android {
    namespace = "com.singwallet.app"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 铁律 1: 永久锁定 Application ID / Package Name 为 com.singwallet.app
        // 严禁更改包名，确保应用覆盖安装升级时历史账单与 SQLite 数据库 100% 无损保留
        applicationId = "com.singwallet.app"
        minSdk = 24
        targetSdk = 35
        versionCode = appVersionCode
        versionName = appVersionName
    }

    packaging {
        jniLibs {
            // 确保 ML Kit 等原生 .so 以未压缩页对齐方式打包，满足 Android 15/16 16KB Page Size 要求
            useLegacyPackaging = false
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { path ->
                val f = file(path as String)
                if (f.exists()) f else rootProject.file(path)
            }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            ndk {
                // 仅打包主流 64 位真机架构，剔除 x86/x86_64 模拟器与旧 32 位冗余 .so（立减 ~28.6 MB 包体积）
                abiFilters += listOf("arm64-v8a")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// 单源前端资产自动同步任务：APK 构建前自动将根目录 web/ 资产同步至 assets，并清理已删除旧文件
val syncWebAssets = tasks.register("syncWebAssets") {
    group = "build"
    description = "Sync single-source web assets into Android main assets."

    val repoRoot = rootDir.parentFile
    val srcWebDir = File(repoRoot, "web")
    val destAssetsDir = file("src/main/assets")

    inputs.dir(srcWebDir)
    outputs.dir(destAssetsDir)

    doLast {
        if (srcWebDir.exists()) {
            destAssetsDir.mkdirs()
            File(destAssetsDir, "singwallet_preview.html").delete()
            File(destAssetsDir, "preview").deleteRecursively()
            srcWebDir.copyRecursively(destAssetsDir, overwrite = true)

            // 清理 destAssetsDir 中已不在 srcWebDir 里的陈旧文件（如已移除的 js/tailwindcss.min.js）
            val validRelPaths = srcWebDir.walkTopDown()
                .filter { it.isFile }
                .map { it.relativeTo(srcWebDir).invariantSeparatorsPath }
                .toHashSet()

            destAssetsDir.walkTopDown()
                .filter { it.isFile }
                .forEach { destFile ->
                    val rel = destFile.relativeTo(destAssetsDir).invariantSeparatorsPath
                    if (rel !in validRelPaths) {
                        destFile.delete()
                    }
                }

            destAssetsDir.walkBottomUp()
                .filter { it.isDirectory && it != destAssetsDir && (it.listFiles()?.isEmpty() == true) }
                .forEach { it.delete() }
        }
    }
}

tasks.named("preBuild") {
    dependsOn(syncWebAssets)
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.webkit:webkit:1.12.0")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    testImplementation("junit:junit:4.13.2")
}
