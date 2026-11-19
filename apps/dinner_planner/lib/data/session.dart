// One loaded copy of everything the phone remembers, and the sync cycle
// that the open app and the hourly background task both run.

import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/nudges.dart';
import '../core/plan.dart';
import '../core/sync_core.dart';
import '../notify/notifier.dart';
import 'recipes.dart';
import 'relay.dart';
import 'store.dart';

/// The recipe site the app reads until Settings names another.
const String defaultSite = 'https://sampanes.github.io/dinner-planner';

const String _coreKey = 'dp.core';
const String _householdKey = 'dp.household';
const String _profileKey = 'dp.profile';
const String _settingsKey = 'dp.settings';
const String _recipesKey = 'dp.recipes';
const String _beatKey = 'dp.openBeat';
const String _tripKey = 'dp.trip';

class SyncReport {
  const SyncReport({this.changes = const [], this.error});

  final List<Change> changes;
  final String? error;
}

class Session {
  Session({required this.store, required this.client, required this.notifier}) : relay = Relay(client);

  final Store store;
  final http.Client client;
  final Notifier notifier;
  final Relay relay;

  late SyncCore core;
  Household? household;

  /// Which of the two people owns this phone.
  String? me;
  String site = defaultSite;
  NudgeTimes times = const NudgeTimes();

  /// A key for the USDA's food list, when the owner has one. Kept on this
  /// phone only; without it barcode lookups share the public demo key.
  String usdaKey = '';

  List<Recipe> recipes = const [];
  DateTime? recipesAt;

  /// The store this phone's owner said they are in, when they said so or
  /// last ticked a line there, and the line they ticked last.
  String? tripStore;
  DateTime? tripAt;
  String? tripLast;

  Plan get plan => Plan(core);

  Recipe? recipe(String? slug) {
    if (slug == null) return null;
    for (final r in recipes) {
      if (r.slug == slug) return r;
    }
    return null;
  }

  /// A recipe's name, or a readable form of its id when the list is not loaded.
  String recipeName(String slug) => recipe(slug)?.name ?? slug.replaceAll('-', ' ');

  Future<void> load() async {
    final rawCore = await store.readJson(_coreKey);
    if (rawCore is Map && rawCore['dev'] is String) {
      core = SyncCore.fromJson(rawCore.cast<String, Object?>());
    } else {
      final r = Random.secure();
      core = SyncCore([for (var i = 0; i < 4; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join());
      await saveCore();
    }
    household = Household.fromJson(await store.readJson(_householdKey));
    final profile = await store.readJson(_profileKey);
    final who = profile is Map ? profile['me'] : null;
    me = people.contains(who) ? who as String : null;
    final settings = await store.readJson(_settingsKey);
    if (settings is Map) {
      final s = settings['site'];
      if (s is String && s.isNotEmpty) site = s;
      times = NudgeTimes.fromJson(settings['times']);
      final k = settings['usdaKey'];
      usdaKey = k is String ? k : '';
    }
    final trip = await store.readJson(_tripKey);
    final tripWhere = trip is Map ? trip['store'] : null, tripWhen = trip is Map ? trip['at'] : null, tripWhat = trip is Map ? trip['last'] : null;
    tripStore = tripWhere is String && tripWhen is int ? tripWhere : null;
    tripAt = tripStore == null ? null : DateTime.fromMillisecondsSinceEpoch(tripWhen as int);
    tripLast = tripStore != null && tripWhat is String ? tripWhat : null;
    final cached = await store.readJson(_recipesKey);
    if (cached is Map) {
      recipes = [
        if (cached['list'] is List)
          for (final item in cached['list'] as List) ?Recipe.fromJson(item)
      ];
      final at = cached['at'];
      recipesAt = at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null;
    }
  }

  Future<void> saveCore() => store.writeJson(_coreKey, core.toJson());

  Future<void> saveHousehold() => store.writeJson(_householdKey, household?.toJson());

  Future<void> saveProfile() => store.writeJson(_profileKey, {'me': me});

  Future<void> saveTrip() => store.writeJson(_tripKey, tripStore == null ? null : {'store': tripStore, 'at': tripAt?.millisecondsSinceEpoch, 'last': tripLast});

  Future<void> saveSettings() => store.writeJson(_settingsKey, {'site': site, 'times': times.toJson(), 'usdaKey': usdaKey});

  Future<void> refreshRecipes(DateTime now) async {
    recipes = await fetchRecipes(client, site);
    recipesAt = now;
    await store.writeJson(_recipesKey, {'at': now.millisecondsSinceEpoch, 'list': [for (final r in recipes) r.toJson()]});
  }

  /// Reads what the other phones said, then says what this one owes. The
  /// state is saved before returning.
  Future<SyncReport> sync(DateTime now) async {
    final h = household;
    if (h == null) return const SyncReport();
    final changes = <Change>[];
    String? error;
    try {
      // Step back a little: a relay can take a moment to show a message it
      // has accepted, so one stamped earlier may appear after a later one.
      // Messages already taken are skipped by id.
      final messages = await relay.poll(h, core.cursor == 0 ? 0 : core.cursor - 30);
      for (final m in messages) {
        if (m.time > core.cursor) core.cursor = m.time;
        if (!core.firstSight(m.id)) continue;
        changes.addAll(core.receive(m.payload, now));
      }
      for (final out in core.outbox(now)) {
        final line = headline(out.entries, plan, recipeName, now);
        final ok = await relay.publish(h, title: line.title, body: line.body, payload: out.payload, quiet: out.entries.isEmpty);
        if (!ok) {
          error = 'The relay refused a message.';
          break;
        }
        core.markSent(out, now);
      }
    } on Exception catch (e) {
      error = e.toString();
    }
    await saveCore();
    return SyncReport(changes: changes, error: error);
  }

  /// Rebuilds the reminders from the plan as it stands.
  Future<void> replan(DateTime now) async {
    final who = me;
    await notifier.schedule(who == null ? const [] : planNudges(me: who, now: now, times: times, plan: plan, recipeName: recipeName));
  }

  /// Raises a notification for each change from another phone that concerns
  /// this phone's owner.
  Future<void> announce(List<Change> changes, DateTime now) async {
    for (final n in noticesFor(changes, me: me, myDev: core.dev, now: now, plan: plan, recipeName: recipeName)) {
      await notifier.show(n);
    }
  }

  /// The open app says "I am running" so the background task leaves the
  /// state alone.
  Future<void> beat(DateTime now) => store.write(_beatKey, '${now.millisecondsSinceEpoch}');

  Future<void> rest() => store.write(_beatKey, null);

  static Future<bool> appIsOpen(Store store, DateTime now) async {
    final at = int.tryParse(await store.read(_beatKey) ?? '');
    return at != null && now.millisecondsSinceEpoch - at < const Duration(seconds: 90).inMilliseconds;
  }
}
