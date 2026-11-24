// The words for the home-screen widget, and the recipes asked for from the
// phone.
//
// The widget is drawn by Android, not by the app, so the app writes down what
// each of the coming days should say and the widget (DinnerWidget.kt) shows
// today's. Writing a week ahead is what lets it move on at midnight without
// the app being opened.

import 'dart:convert';

import 'nudges.dart';
import 'plan.dart';
import 'sync_core.dart';

/// What the widget says about one day.
typedef Glance = ({String title, String sub});

/// The widget's two lines for the dinner on [day], as [me] reads them.
Glance glanceFor(String day, {required Plan plan, required String? me, required NudgeTimes times, required String Function(String slug) recipeName, required int? Function(String slug) minutes}) {
  final off = plan.off(day);
  if (off != null) return (title: offKinds[off]!, sub: 'Nobody cooks tonight');
  final slug = plan.meal(day), cook = plan.cook(day);
  final who = cook == null ? null : (cook == me ? 'You cook' : '${plan.name(cook)} cooks');
  if (slug == null) return (title: 'Nothing planned', sub: who ?? 'Tap to pick a dinner');
  final start = 'start by ${clockText(startMinutes(times, minutes(slug)))}';
  return (title: recipeName(slug), sub: who == null ? 'Nobody is down to cook · $start' : '$who · $start');
}

/// What the app hands the widget: the two lines for each of the next [days]
/// days, as the JSON DinnerWidget.kt reads.
String glanceJson(DateTime now, Glance Function(String day) glance, {int days = 8}) => jsonEncode({
      'days': {
        for (var i = 0; i < days; i++)
          dayText(dayAfter(now, i)): {'title': glance(dayText(dayAfter(now, i))).title, 'sub': glance(dayText(dayAfter(now, i))).sub},
      },
    });

/// `ask/<id>` is a recipe someone asked for from a phone: the link they
/// shared into the app. It waits there, on both phones, until the recipe has
/// been added at a computer (scripts/house_notes.py lists and clears them).
String askKey(String id) => 'ask/$id';

final RegExp _link = RegExp(r'https?://[^\s<>"]+');

/// The link in something shared into the app, without the tracking a share
/// sheet tends to hang on it; null when there is none.
String? sharedLink(String text) {
  final m = _link.firstMatch(text);
  if (m == null) return null;
  final uri = Uri.tryParse(m.group(0)!.replaceFirst(RegExp(r'[.,)\]]+$'), ''));
  if (uri == null || uri.host.isEmpty) return null;
  final clean = uri.replace(queryParameters: {
    for (final e in uri.queryParameters.entries)
      if (!e.key.startsWith('utm_') && e.key != 'fbclid' && e.key != 'gclid') e.key: e.value,
  }).toString().replaceFirst(RegExp(r'\?$'), '');
  return clean.length > 380 ? null : clean;
}

/// A short, stable name for a link (FNV-1a, as for a step), so that sharing
/// the same recipe twice asks for it once.
String askId(String link) => stepId(link.toLowerCase());

/// A link as a person reads it: "hellofresh.com/recipes/firecracker-meatballs".
String linkLabel(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null || uri.host.isEmpty) return link;
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return '${uri.host.replaceFirst(RegExp(r'^www\.'), '')}$path';
}
