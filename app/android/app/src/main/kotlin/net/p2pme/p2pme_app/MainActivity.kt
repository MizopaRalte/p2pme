package net.p2pme.p2pme_app

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import android.os.Environment
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "net.p2pme/background_sync"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        val serviceIntent = Intent(this, P2PmeSyncService::class.java)
                        ContextCompat.startForegroundService(this, serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "stopService" -> {
                    try {
                        val serviceIntent = Intent(this, P2PmeSyncService::class.java).apply {
                            action = P2PmeSyncService.ACTION_STOP_SERVICE
                        }
                        startService(serviceIntent)
                        stopService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_FAILED", e.message, null)
                    }
                }
                "isServiceRunning" -> {
                    result.success(P2PmeSyncService.isRunning)
                }
                "isBatteryOptimizationIgnored" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        powerManager.isIgnoringBatteryOptimizations(packageName)
                    } else {
                        true
                    }
                    result.success(isIgnoring)
                }
                "getStorageSpace" -> {
                    try {
                        val path = Environment.getDataDirectory()
                        val stat = StatFs(path.path)
                        val blockSize = stat.blockSizeLong
                        val availableBlocks = stat.availableBlocksLong
                        val totalBlocks = stat.blockCountLong
                        val map = mapOf(
                            "free_bytes" to (availableBlocks * blockSize),
                            "total_bytes" to (totalBlocks * blockSize)
                        )
                        result.success(map)
                    } catch (e: Exception) {
                        result.success(mapOf("free_bytes" to 0L, "total_bytes" to 0L))
                    }
                }
                "getDeviceName" -> {
                    try {
                        var name: String? = null
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                            name = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
                        }
                        if (name.isNullOrBlank()) {
                            val manufacturer = Build.MANUFACTURER.replaceFirstChar {
                                if (it.isLowerCase()) it.titlecase(Locale.ROOT) else it.toString()
                            }
                            name = "$manufacturer ${Build.MODEL}"
                        }
                        result.success(name)
                    } catch (e: Exception) {
                        result.success("${Build.MANUFACTURER} ${Build.MODEL}")
                    }
                }
                "requestIgnoreBatteryOptimization" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "isAllFilesAccessGranted" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        result.success(Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }
                "requestAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("PERMISSION_ERROR", e2.message, null)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                "getBatteryStatus" -> {
                    try {
                        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                        val statusIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                        val status = statusIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
                        result.success(mapOf("level" to level, "isCharging" to isCharging))
                    } catch (e: Exception) {
                        result.success(mapOf("level" to 100, "isCharging" to true))
                    }
                }
                "getAppVersion" -> {
                    try {
                        val pInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        val vCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            (pInfo.longVersionCode % 1000).toInt()
                        } else {
                            @Suppress("DEPRECATION")
                            (pInfo.versionCode % 1000)
                        }
                        result.success(mapOf(
                            "versionName" to (pInfo.versionName ?: "1.0.3"),
                            "versionCode" to vCode
                        ))
                    } catch (e: Exception) {
                        result.error("VERSION_ERROR", e.message, null)
                    }
                }
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val file = File(filePath)
                        if (file.exists()) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                                val manageIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                    data = Uri.parse("package:$packageName")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(manageIntent)
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            try {
                                val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
                                } else {
                                    Uri.fromFile(file)
                                }
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(apkUri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_ERROR", e.message, null)
                            }
                        } else {
                            result.error("FILE_NOT_FOUND", "File not found: $filePath", null)
                        }
                    } else {
                        result.error("INVALID_PATH", "filePath is required", null)
                    }
                }
                "openBrowserUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_URL", "url is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
