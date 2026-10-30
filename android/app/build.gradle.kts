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

val appVersionName = (project.findProperty("APP_VERSION_NAME") as String?) ?: "1.0.6"
val appVersionCode = (project.findProperty("APP_VERSION_CODE") as String?)?.toIntOrNull() ?: 7

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
            // 当存在 key.properties 时使用标准 Release 证书签名；否则回退为 debug 签名用于本地测试构建
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

// 单源前端资产自动同步任务：APK 构建前自动将根目录 preview 与 singwallet_preview.html 同步至 assets
val syncWebAssets = tasks.register("syncWebAssets") {
    group = "build"
    description = "Sync single-source web preview assets into Android main assets."

    val repoRoot = rootDir.parentFile
    val srcHtml = File(repoRoot, "singwallet_preview.html")
    val srcPreviewDir = File(repoRoot, "preview")
    val destAssetsDir = file("src/main/assets")

    inputs.file(srcHtml)
    inputs.dir(srcPreviewDir)
    outputs.file(File(destAssetsDir, "singwallet_preview.html"))
    outputs.dir(File(destAssetsDir, "preview"))

    doLast {
        if (srcHtml.exists()) {
            destAssetsDir.mkdirs()
            srcHtml.copyTo(File(destAssetsDir, "singwallet_preview.html"), overwrite = true)
        }
        if (srcPreviewDir.exists()) {
            val destPreviewDir = File(destAssetsDir, "preview")
            if (destPreviewDir.exists()) {
                destPreviewDir.deleteRecursively()
            }
            srcPreviewDir.copyRecursively(destPreviewDir, overwrite = true)
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
}
