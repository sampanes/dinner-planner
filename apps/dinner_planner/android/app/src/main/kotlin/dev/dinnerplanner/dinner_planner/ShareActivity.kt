package dev.dinnerplanner.dinner_planner

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle

// "Share" from a browser or the HelloFresh app, with Dinner Planner picked.
//
// This is not the app itself: it writes down what was shared, in the one
// settings file the Flutter side also reads, opens the app, and goes. The
// app picks it up when it comes to the front (lib/data/store.dart,
// "takeShared"). Kept apart from MainActivity so that sharing never starts a
// second copy of the app inside the sharing app's window.
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = if (intent?.action == Intent.ACTION_SEND) intent.getStringExtra(Intent.EXTRA_TEXT) else null
        if (!text.isNullOrBlank()) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val line = text.replace("\n", " ").trim().take(600)
            val waiting = prefs.getString("flutter.dp.shared", null)
            prefs.edit().putString("flutter.dp.shared", if (waiting.isNullOrEmpty()) line else waiting + "\n" + line).commit()
        }
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }
}
