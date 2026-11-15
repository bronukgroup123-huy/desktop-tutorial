package ua.mushroomradar.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Віджет «Грибний Радар» на головному екрані: ділянка, рівень сьогодні, найкращий гриб і день.
 * Дані записує застосунок (home_widget) після кожного оновлення прогнозу; тап — відкрити «Прогноз».
 */
class MushroomWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.mushroom_widget).apply {
                setTextViewText(R.id.widget_title, widgetData.getString("title", "Грибний Радар"))
                setTextViewText(R.id.widget_level, widgetData.getString("level", "Відкрийте «Прогноз»"))
                setTextViewText(R.id.widget_species, widgetData.getString("species", ""))
                setTextViewText(R.id.widget_best, widgetData.getString("best", ""))
                setTextViewText(R.id.widget_updated, widgetData.getString("updated", ""))
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
