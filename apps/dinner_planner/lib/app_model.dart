// What the screens watch and call. Every change is shown at once, saved,
// turned into reminders, and then sent to the other phone.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core/nudges.dart';
import 'core/plan.dart';
import 'core/sync_core.dart';
import 'data/recipes.dart';
import 'data/relay.dart';
import 'data/session.dart';

class AppModel extends ChangeNotifier {
  AppModel(this.session, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Session session;
  final DateTime Function() _clock;

  bool ready = false;
  String? syncError;
  DateTime? lastSync;
  String? recipeError;
  bool loadingRecipes = false;

  bool _syncing = false;
  bool _again = false;
  Timer? _poll;

  DateTime get now => _clock();
  Plan get plan => session.plan;
  String? get me => session.me;
  Household? get household => session.household;
  List<Recipe> get recipes => session.recipes;
  NudgeTimes get times => session.times;
  String get site => session.site;
  int get otherPhones => session.core.peerCount;
  bool get inStep => session.core.inStep(now);

  String today() => dayText(now);

  Future<void> start() async {
    await session.load();
    ready = true;
    notifyListeners();
  }

  /// The app came to the front: pick up anything the background task wrote,
  /// then keep in step while it stays open.
  Future<void> wake() async {
    await session.load();
    await session.beat(now);
    notifyListeners();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      session.beat(now);
      sync();
    });
    final at = session.recipesAt;
    if (session.recipes.isEmpty || at == null || now.difference(at) > const Duration(hours: 6)) {
      unawaited(refreshRecipes());
    }
    await sync();
    await session.replan(now);
  }

  Future<void> sleep() async {
    _poll?.cancel();
    _poll = null;
    await session.rest();
  }

  Future<void> sync() async {
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _again = false;
        final report = await session.sync(now);
        if (session.household != null) {
          syncError = report.error;
          if (report.error == null) lastSync = now;
        }
        if (report.changes.isNotEmpty) {
          await session.announce(report.changes, now);
          await session.replan(now);
        }
        notifyListeners();
      } while (_again);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _wrote(bool changed) async {
    if (!changed) return;
    notifyListeners();
    await session.saveCore();
    await session.replan(now);
    unawaited(sync());
  }

  Future<void> setMeal(String day, String? slug) => _wrote(session.core.set(mealKey(day), slug, now));

  Future<void> setCook(String day, String? who) => _wrote(session.core.set(cookKey(day), who, now));

  Future<void> setName(String who, String name) {
    final text = name.trim();
    return _wrote(session.core.set(nameKey(who), text.isEmpty ? null : text, now));
  }

  Future<void> setMe(String who) async {
    session.me = who;
    await session.saveProfile();
    notifyListeners();
    await session.replan(now);
  }

  Future<void> setTimes(NudgeTimes times) async {
    session.times = times;
    await session.saveSettings();
    notifyListeners();
    await session.replan(now);
  }

  Future<void> setSite(String site) async {
    final text = site.trim();
    if (text.isEmpty || text == session.site) return;
    session.site = text;
    await session.saveSettings();
    await refreshRecipes();
  }

  Future<void> refreshRecipes() async {
    if (loadingRecipes) return;
    loadingRecipes = true;
    notifyListeners();
    try {
      await session.refreshRecipes(now);
      recipeError = null;
      await session.replan(now);
    } on Exception catch (e) {
      recipeError = e.toString();
    } finally {
      loadingRecipes = false;
      notifyListeners();
    }
  }

  Future<void> startHousehold({String server = defaultServer, String? token}) => _useHousehold(Household.create(server: server, token: token));

  /// False when [code] is not a household code.
  Future<bool> joinHousehold(String code) async {
    final h = Household.fromCode(code);
    if (h == null) return false;
    await _useHousehold(h);
    return true;
  }

  Future<void> _useHousehold(Household h) async {
    session.household = h;
    session.core.cursor = 0;
    await session.saveHousehold();
    await session.saveCore();
    notifyListeners();
    await sync();
  }

  Future<void> leaveHousehold() async {
    session.household = null;
    syncError = null;
    lastSync = null;
    await session.saveHousehold();
    notifyListeners();
  }

  /// Puts the recipe site's weekly plan on the days from today that have no
  /// dinner yet. Returns how many days it filled.
  Future<int> fillFromKitchenPlan() async {
    final slugs = await fetchKitchenPlan(session.client, session.site);
    final planned = {for (var i = 0; i < 14; i++) plan.meal(dayText(dayAfter(now, i)))};
    final fresh = [for (final s in slugs) if (!planned.contains(s)) s];
    var filled = 0;
    var changed = false;
    for (var i = 0; i < 14 && filled < fresh.length; i++) {
      final day = dayText(dayAfter(now, i));
      if (plan.meal(day) != null) continue;
      changed = session.core.set(mealKey(day), fresh[filled], now) || changed;
      filled++;
    }
    await _wrote(changed);
    return filled;
  }

  Future<bool> allowNotifications() => session.notifier.askPermission();

  Future<void> testReminder() => session.notifier.show(const Notice("You're cooking tonight", 'This is what a reminder looks like.'));

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
