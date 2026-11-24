package dev.dinnerplanner.dinner_planner

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Tonight's dinner on the home screen: what it is, who cooks, when to start.
//
// The app writes the words for each of the coming days (lib/core/glance.dart)
// into the one settings file both sides can read; this only picks today's and
// shows them. Android redraws it every half hour, which is what turns
// tomorrow's line into today's after midnight, and the app asks for a redraw
// whenever the plan changes while it is open.
class DinnerWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        // Where the Flutter side's shared_preferences keeps a value written
        // under the name "dp.glance".
        private const val FILE = "FlutterSharedPreferences"
        private const val KEY = "flutter.dp.glance"

        fun redraw(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, DinnerWidget::class.java))
            for (id in ids) manager.updateAppWidget(id, views(context))
        }

        private fun views(context: Context): RemoteViews {
            var title = context.getString(R.string.widget_open)
            var sub = ""
            try {
                val raw = context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString(KEY, null)
                val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                val day = if (raw == null) null else JSONObject(raw).optJSONObject("days")?.optJSONObject(today)
                if (day != null) {
                    title = day.optString("title", title)
                    sub = day.optString("sub", "")
                }
            } catch (e: Exception) {
                // Nothing readable yet: the widget says to open the app.
            }
            val views = RemoteViews(context.packageName, R.layout.dinner_widget)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_sub, sub)
            val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
            )
            return views
        }
    }
}
