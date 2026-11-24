package dev.dinnerplanner.dinner_planner

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// The three things the app asks Android for by name (lib/data/updates.dart):
// a folder for a downloaded update, handing that update to Android's own
// installer, and stepping back behind the browser a link came from.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dinner_planner/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "updatesDir" -> {
                    val dir = File(cacheDir, "updates")
                    dir.mkdirs()
                    result.success(dir.absolutePath)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    val file = if (path == null) null else File(path)
                    // Only a file from the app's own updates folder is handed on.
                    if (file == null || !file.isFile || file.parentFile?.canonicalPath != File(cacheDir, "updates").canonicalPath) {
                        result.success(false)
                    } else {
                        try {
                            val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                "stepBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
