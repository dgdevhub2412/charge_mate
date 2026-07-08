package dgdevhub.charge_mate.charge_mate

import android.app.Activity
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "charge_mate/ringtone_picker"
    private val RINGTONE_PICKER_REQUEST_CODE = 999
    private var pendingResult: MethodChannel.Result? = null
    private var currentRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickRingtone" -> {
                    pendingResult = result
                    val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM or RingtoneManager.TYPE_RINGTONE)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Select Alarm Sound")
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                    }
                    startActivityForResult(intent, RINGTONE_PICKER_REQUEST_CODE)
                }
                "playRingtone" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString != null) {
                        try {
                            currentRingtone?.stop()
                            val uri = Uri.parse(uriString)
                            currentRingtone = RingtoneManager.getRingtone(this, uri)
                            
                            // Set audio attributes to use the ALARM stream
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                val attributes = AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_ALARM)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .build()
                                currentRingtone?.audioAttributes = attributes
                            }
                            
                            // Loop ringtone on Android P (9.0) and above
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                currentRingtone?.isLooping = true
                            }
                            
                            currentRingtone?.play()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PLAY_ERROR", e.message, null)
                        }
                    } else {
                        result.error("BAD_ARGS", "URI is null", null)
                    }
                }
                "stopRingtone" -> {
                    try {
                        currentRingtone?.stop()
                        currentRingtone = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == RINGTONE_PICKER_REQUEST_CODE) {
            val result = pendingResult
            pendingResult = null
            if (result != null) {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    val uri: Uri? = data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                    if (uri != null) {
                        try {
                            val ringtone = RingtoneManager.getRingtone(this, uri)
                            val title = ringtone?.getTitle(this) ?: "System Sound"
                            result.success(mapOf(
                                "uri" to uri.toString(),
                                "title" to title
                            ))
                        } catch (e: Exception) {
                            result.success(mapOf(
                                "uri" to uri.toString(),
                                "title" to "System Sound"
                            ))
                        }
                    } else {
                        result.success(null)
                    }
                } else {
                    result.success(null)
                }
            }
        }
    }
}
