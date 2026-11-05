// `fun` is a Kotlin keyword, so the package segment is escaped. The Android
// applicationId and namespace stay fun.lifeaxis.lazer.
package `fun`.lifeaxis.lazer

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class AndroidUpdateInstaller(private val activity: Activity) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private val directory = File(activity.cacheDir, "updates")

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "installedInfo" -> {
                    val installed = installedInfo()
                    result.success(mapOf(
                        "packageName" to installed.packageName,
                        "versionCode" to versionCode(installed),
                        "versionName" to installed.versionName,
                    ))
                }
                "downloadDirectory" -> {
                    check(directory.isDirectory || directory.mkdirs()) { "无法创建更新目录" }
                    val cutoff = System.currentTimeMillis() - 48L * 60 * 60 * 1000
                    directory.listFiles()?.filter { it.isFile && it.lastModified() < cutoff }
                        ?.forEach { it.delete() }
                    result.success(directory.canonicalPath)
                }
                "canInstall" -> result.success(activity.packageManager.canRequestPackageInstalls())
                "requestInstallPermission" -> {
                    activity.startActivity(Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}"),
                    ))
                    result.success(null)
                }
                "verify", "install" -> executor.execute {
                    try {
                        val archive = verify(call)
                        activity.runOnUiThread {
                            if (activity.isFinishing || activity.isDestroyed) {
                                result.error("activity_closed", "页面已关闭，请重新检查更新", null)
                            } else {
                                try {
                                    if (call.method == "install") openInstaller(archive)
                                    result.success(null)
                                } catch (failure: Exception) {
                                    result.error("install_failed", failure.message, null)
                                }
                            }
                        }
                    } catch (failure: Exception) {
                        activity.runOnUiThread {
                            result.error("verification_failed", failure.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (failure: Exception) {
            result.error("update_failed", failure.message, null)
        }
    }

    private fun verify(call: MethodCall): File {
        val path = requireNotNull(call.argument<String>("path")) { "缺少安装包路径" }
        val expectedSize = requireNotNull(call.argument<Number>("sizeBytes")) { "缺少文件大小" }.toLong()
        val expectedCode = requireNotNull(call.argument<Number>("versionCode")) { "缺少版本号" }.toLong()
        val expectedName = requireNotNull(call.argument<String>("versionName")) { "缺少版本名称" }
        val expectedHash = requireNotNull(call.argument<String>("sha256")) { "缺少校验值" }
        val archive = File(path).canonicalFile
        require(archive.parentFile == directory.canonicalFile && archive.name.endsWith(".apk")) {
            "拒绝安装更新目录以外的文件"
        }
        require(archive.isFile && archive.length() == expectedSize && expectedSize > 0) {
            "安装包大小校验失败"
        }
        val digest = MessageDigest.getInstance("SHA-256")
        archive.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val actualHash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
        require(actualHash == expectedHash && Regex("[a-f0-9]{64}").matches(expectedHash)) {
            "SHA-256 校验失败，已拒绝安装"
        }
        val candidate = requireNotNull(activity.packageManager.getPackageArchiveInfo(
            archive.path,
            signingFlags(),
        )) { "无法读取安装包或验证 APK 签名" }
        val installed = installedInfo()
        require(candidate.packageName == activity.packageName) { "安装包包名不匹配" }
        require(versionCode(candidate) == expectedCode && candidate.versionName == expectedName) {
            "安装包版本与更新清单不一致"
        }
        require(expectedCode > versionCode(installed)) { "此版本并不比已安装版本新" }
        val candidateApplication = requireNotNull(candidate.applicationInfo) { "无法读取安装包应用信息" }
        require(candidateApplication.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            "拒绝安装调试签名构建，请使用正式发布包"
        }
        val currentSigners = signerDigests(installed)
        val candidateSigners = signerDigests(candidate)
        require(currentSigners.isNotEmpty() && currentSigners == candidateSigners) {
            "签名与已安装版本不兼容，已拒绝安装；请联系发布者核对原签名"
        }
        return archive
    }

    private fun installedInfo(): PackageInfo = activity.packageManager.getPackageInfo(
        activity.packageName,
        signingFlags(),
    )

    private fun signingFlags(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        PackageManager.GET_SIGNING_CERTIFICATES
    } else {
        PackageManager.GET_SIGNATURES
    }

    private fun versionCode(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        info.longVersionCode
    } else {
        info.versionCode.toLong()
    }

    private fun signerDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        }?.toSet() ?: emptySet()
    }

    private fun openInstaller(archive: File) {
        check(activity.packageManager.canRequestPackageInstalls()) { "请先允许 Lazer 安装应用更新" }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", archive)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(intent)
    }

    override fun close() {
        executor.shutdownNow()
    }
}
