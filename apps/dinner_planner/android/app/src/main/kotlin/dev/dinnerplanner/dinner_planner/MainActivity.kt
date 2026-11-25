package dev.dinnerplanner.dinner_planner

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// The things the app asks Android for by name (lib/data/updates.dart and
// lib/data/labels.dart): a folder for a downloaded update, handing that
// update to Android's own installer, stepping back behind the browser a link
// came from, having the home-screen widget drawn again, and reading the
// words in a picture of a label. The reading is done on the phone; no
// picture leaves it.
class MainActivity : FlutterActivity() {
    // The one photograph of a label being waited for, if any.
    private var photoAsked: MethodChannel.Result? = null
    private var photoFile: File? = null

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
                "redrawWidget" -> {
                    DinnerWidget.redraw(this)
                    result.success(null)
                }
                "readText" -> {
                    // A camera frame the barcode scanner handed over, as a JPEG.
                    val bytes = call.argument<ByteArray>("picture")
                    val bitmap = if (bytes == null) null else BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    if (bitmap == null) {
                        result.success(emptyList<Map<String, Any>>())
                    } else {
                        readText(InputImage.fromBitmap(bitmap, 0), result)
                    }
                }
                "photoText" -> {
                    if (photoAsked != null) {
                        result.success(null)
                    } else {
                        photoAsked = result
                        // Android refuses to open its camera for an app that
                        // lists the camera permission and has not been given it.
                        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                            takePhoto()
                        } else {
                            requestPermissions(arrayOf(Manifest.permission.CAMERA), ASK_CAMERA)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Answers with the lines of text in the picture, top first, each with the
    // height of its letters: the name of a thing is the tall words.
    private fun readText(image: InputImage, result: MethodChannel.Result, after: () -> Unit = {}) {
        val reader = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        reader.process(image)
            .addOnSuccessListener { text ->
                val lines = text.textBlocks.flatMap { it.lines }.sortedBy { it.boundingBox?.top ?: 0 }
                result.success(lines.map { mapOf("text" to it.text, "height" to (it.boundingBox?.height() ?: 0)) })
            }
            .addOnFailureListener { result.success(emptyList<Map<String, Any>>()) }
            .addOnCompleteListener {
                reader.close()
                after()
            }
    }

    private fun photoDone(lines: Any?) {
        val asked = photoAsked
        photoAsked = null
        photoFile = null
        asked?.success(lines)
    }

    // Opens the phone's own camera for one picture, saved where only this app
    // can read it and deleted once it has been read.
    private fun takePhoto() {
        try {
            val dir = File(cacheDir, "labels")
            dir.mkdirs()
            val file = File(dir, "label.jpg")
            file.delete()
            val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                .putExtra(MediaStore.EXTRA_OUTPUT, uri)
                .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            photoFile = file
            startActivityForResult(intent, TAKE_PHOTO)
        } catch (e: Exception) {
            photoDone(null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != ASK_CAMERA || photoAsked == null) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) takePhoto() else photoDone(null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != TAKE_PHOTO) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val asked = photoAsked
        val file = photoFile
        if (asked == null) return
        if (resultCode != RESULT_OK || file == null || !file.isFile || file.length() == 0L) {
            photoDone(null)
            return
        }
        photoAsked = null
        photoFile = null
        try {
            // Turns the picture upright by what the camera wrote in it.
            readText(InputImage.fromFilePath(this, Uri.fromFile(file)), asked) { file.delete() }
        } catch (e: Exception) {
            file.delete()
            asked.success(emptyList<Map<String, Any>>())
        }
    }

    companion object {
        private const val TAKE_PHOTO = 7301
        private const val ASK_CAMERA = 7302
    }
}
