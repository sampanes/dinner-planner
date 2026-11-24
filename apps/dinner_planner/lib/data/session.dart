// One loaded copy of everything the phone remembers, and the sync cycle
// that the open app and the hourly background task both run.

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/nudges.dart';
import '../core/pantry.dart';
import '../core/plan.dart';
import '../core/shopping.dart';
import '../core/store_order.dart';
import '../core/sync_core.dart';
import '../notify/notifier.dart';
import 'autoplan.dart';
import 'recipes.dart';
import 'relay.dart';
import 'store.dart';
import 'updates.dart';

/// The recipe site the app reads until Settings names another.
const String defaultSite = 'https://sampanes.github.io/dinner-planner';

const String _coreKey = 'dp.core';
const String _householdKey = 'dp.household';
const String _profileKey = 'dp.profile';
const String _settingsKey = 'dp.settings';
const String _recipesKey = 'dp.recipes';
const String _beatKey = 'dp.openBeat';
const String _tripKey = 'dp.trip';
const String _ratesKey = 'dp.rates';
const String _weekAskKey = 'dp.weekAsk';
const String _shopAskKey = 'dp.shopAsk';
const String _timersKey = 'dp.timers';
const String _updateKey = 'dp.update';

/// `ver/<device>` is the version of the app a phone runs, so that each can
/// say when the other is behind.
String versionKey(String dev) => 'ver/$dev';

/// How often the phone asks whether there is a newer version.
const Duration updateCheckEvery = Duration(hours: 12);

/// A timer started on the recipe page and handed to the phone to ring.
typedef KitchenTimer = ({int id, String label, DateTime end, String slug});

/// Goes up when the phone starts keeping more of each recipe, so a list saved
/// by an older version is fetched again instead of waiting to go stale.
const int _recipeFields = 4;

/// A rating not yet seen in the site's data is sent again this often (the
/// relay keeps a message about twelve hours, the site's job runs hourly)...
const Duration _siteResend = Duration(hours: 4);

/// ...and given up on after this many times, about three days.
const int _siteSends = 18;

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

  /// The owner waved the "start here" steps away on this phone.
  bool startHidden = false;

  /// Timers started on the recipe page are rung by this phone too.
  bool ringTimers = true;

  List<Recipe> recipes = const [];
  DateTime? recipesAt;

  /// The store this phone's owner said they are in, when they said so or
  /// last ticked a line there, and the line they ticked last.
  String? tripStore;
  DateTime? tripAt;
  String? tripLast;

  /// How this phone's owner rated a dinner, and on which day: recipe -> answer.
  final Map<String, ({String day, int stars})> rated = {};

  /// Ratings and "we cooked this" on their way to the recipe site, in the
  /// form its own pages send them.
  final List<Map<String, Object?>> siteQueue = [];

  /// Where those go; read from the site once per run.
  String? siteTopic;

  /// The kitchen timers still running.
  final List<KitchenTimer> timers = [];

  /// The newest version GitHub has, when it was last asked, and the version
  /// this phone has already been told about.
  Release? newest;
  DateTime? newestAt;
  String? newestTold;

  /// True when a newer version than this one is waiting.
  bool get updateReady => newest != null && compareVersions(newest!.version, appVersion) > 0;

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

  /// The section an ingredient is in: what the household said, else a guess.
  String section(String id) {
    final v = core.value(sectionKey(id));
    return v is String && sections.containsKey(v) ? v : guessSection(id);
  }

  /// Always in the house, so no dinner puts it on the list.
  bool staple(String id) => isStaple(id, core.value(haveKey(id)));

  /// A staple that has run out, or an extra that is wanted.
  bool wanted(String id) => core.value(wantKey(id)) == '1';

  /// Whether a dinner on [day] is still without [id]: not ticked for it,
  /// and not something the house always has.
  bool needs(String id, String day) => core.value(gotKey(id, day)) != '1' && (!staple(id) || wanted(id));

  /// What the house holds, as far as the app has been told.
  Pantry pantry(DateTime now) => Pantry(core: core, section: section, staple: staple, dinners: pantryDinners(plan, now, (slug) => recipe(slug)?.ingredients), now: now);

  /// Not ticked for the dinner on [day], but bought lately and probably
  /// still there.
  bool likely(String id, String day, Pantry pantry) => needs(id, day) && !staple(id) && pantry.has(id, day);

  /// What a reminder says about the dinner on [day].
  DinnerFacts facts(String day, String slug, Pantry pantry) {
    final r = recipe(slug);
    if (r == null) return DinnerFacts(name: recipeName(slug));
    final thaw = <String>[], missing = <String>[], check = <String>[], seen = <String>{};
    for (final i in r.ingredients) {
      if (!seen.add(i.id)) continue;
      if (section(i.id) == 'meat') thaw.add(i.name);
      if (likely(i.id, day, pantry)) {
        check.add(i.name);
      } else if (needs(i.id, day)) {
        missing.add(i.name);
      }
    }
    return DinnerFacts(name: r.name, minutes: r.minutes, thaw: thaw, missing: missing, check: check);
  }

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
      startHidden = settings['startHidden'] == true;
      ringTimers = settings['ringTimers'] != false;
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
      recipesAt = at is int && cached['v'] == _recipeFields ? DateTime.fromMillisecondsSinceEpoch(at) : null;
    }
    final rates = await store.readJson(_ratesKey);
    rated.clear();
    siteQueue.clear();
    if (rates is Map) {
      final on = rates['on'];
      if (on is Map) {
        on.forEach((slug, v) {
          if (slug is String && v is List && v.length == 2 && v[0] is String && v[1] is int) rated[slug] = (day: v[0] as String, stars: v[1] as int);
        });
      }
      final queue = rates['queue'];
      if (queue is List) {
        siteQueue.addAll([for (final e in queue) if (e is Map && e['k'] is String && e['slug'] is String) e.cast<String, Object?>()]);
      }
    }
    final kept = await store.readJson(_timersKey);
    timers.clear();
    if (kept is List) {
      for (final t in kept) {
        if (t is Map && t['id'] is int && t['label'] is String && t['end'] is int) {
          timers.add((id: t['id'] as int, label: t['label'] as String, end: DateTime.fromMillisecondsSinceEpoch(t['end'] as int), slug: t['slug'] is String ? t['slug'] as String : ''));
        }
      }
    }
    final update = await store.readJson(_updateKey);
    newest = update is Map ? Release.fromJson(update['release']) : null;
    final asked = update is Map ? update['at'] : null, told = update is Map ? update['told'] : null;
    newestAt = asked is int ? DateTime.fromMillisecondsSinceEpoch(asked) : null;
    newestTold = told is String ? told : null;
  }

  Future<void> saveTimers() => store.writeJson(_timersKey, [for (final t in timers) {'id': t.id, 'label': t.label, 'end': t.end.millisecondsSinceEpoch, 'slug': t.slug}]);

  Future<void> _saveUpdate() => store.writeJson(_updateKey, {'release': newest?.toJson(), 'at': newestAt?.millisecondsSinceEpoch, 'told': newestTold});

  /// Says which version this phone runs, where the other phone can read it.
  /// True when that was news.
  bool noteVersion(DateTime now) => core.set(versionKey(core.dev), appVersion, now);

  /// The oldest version another phone of the household says it runs. '' when
  /// one of them has never said, which only a version before 0.10 does; null
  /// when there is no other phone.
  String? get otherVersion {
    String? oldest;
    for (final dev in core.phones) {
      final v = core.value(versionKey(dev));
      if (v is! String || v.isEmpty) return '';
      if (oldest == null || compareVersions(v, oldest) < 0) oldest = v;
    }
    return oldest;
  }

  /// Asks GitHub for the newest version, at most every [updateCheckEvery]
  /// unless [force]. True when a version newer than this one was found that
  /// the phone had not been told about before.
  Future<bool> checkUpdate(DateTime now, {bool force = false}) async {
    final last = newestAt;
    if (!force && last != null && now.difference(last).abs() < updateCheckEvery) return false;
    try {
      final found = await fetchNewest(client, site);
      if (found == null) return false;
      newest = found;
    } on Exception {
      return false;
    }
    newestAt = now;
    final fresh = updateReady && newestTold != newest!.version;
    if (fresh) newestTold = newest!.version;
    await _saveUpdate();
    return fresh;
  }

  Future<void> saveCore() => store.writeJson(_coreKey, core.toJson());

  Future<void> saveHousehold() => store.writeJson(_householdKey, household?.toJson());

  Future<void> saveProfile() => store.writeJson(_profileKey, {'me': me});

  Future<void> saveTrip() => store.writeJson(_tripKey, tripStore == null ? null : {'store': tripStore, 'at': tripAt?.millisecondsSinceEpoch, 'last': tripLast});

  Future<void> saveSettings() => store.writeJson(_settingsKey, {'site': site, 'times': times.toJson(), 'usdaKey': usdaKey, if (startHidden) 'startHidden': true, if (!ringTimers) 'ringTimers': false});

  Future<void> saveRates() => store.writeJson(_ratesKey, {
        'on': {for (final e in rated.entries) e.key: [e.value.day, e.value.stars]},
        'queue': siteQueue,
      });

  Future<void> refreshRecipes(DateTime now) async {
    recipes = await fetchRecipes(client, site);
    recipesAt = now;
    await store.writeJson(_recipesKey, {'at': now.millisecondsSinceEpoch, 'v': _recipeFields, 'list': [for (final r in recipes) r.toJson()]});
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
        final ok = await relay.publish(h, title: line.title, body: line.body, payload: out.payload, quiet: out.entries.every((e) => e.key.startsWith('ver/')));
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

  /// The dinners a tap on "Use these" would put on the plan.
  List<DraftNight> draft(DateTime now) => draftWeek(now: now, plan: plan, recipes: recipes, names: {for (final who in people) who: plan.name(who)});

  /// Rebuilds the reminders from the plan as it stands.
  Future<void> replan(DateTime now) async {
    final who = me;
    if (who == null) {
      await notifier.schedule(const []);
      return;
    }
    final house = pantry(now);
    final nudges = planNudges(me: who, now: now, times: times, plan: plan, facts: (day, slug) => facts(day, slug, house), rated: (day, slug) => rated[slug]?.day == day);
    final week = await _weekOffer(now);
    if (week != null) nudges.add(week);
    final shop = await _shopOffer(now, house);
    if (shop != null) nudges.add(shop);
    final before = timers.length;
    timers.removeWhere((t) => !t.end.isAfter(now));
    if (timers.length != before) await saveTimers();
    nudges.addAll([for (final t in timers) timerNudge(t.id, t.end, t.label, slug: t.slug)]);
    nudges.sort((a, b) => a.when.compareTo(b.when));
    await notifier.schedule(nudges);
  }

  /// What the dinners from tomorrow through seven days on still need bought:
  /// the things, how many dinners, and the first day one is needed.
  ({List<String> things, int dinners, DateTime? first}) toBuy(DateTime now, Pantry house) {
    final things = <String, String>{};
    var dinners = 0;
    DateTime? first;
    for (var i = 1; i <= 7; i++) {
      final date = dayAfter(now, i), day = dayText(date);
      final r = recipe(plan.meal(day));
      if (r == null) continue;
      var some = false;
      for (final x in r.ingredients) {
        if (needs(x.id, day) && !likely(x.id, day, house)) {
          things[x.id] = x.name;
          some = true;
        }
      }
      if (some) {
        dinners++;
        first ??= date;
      }
    }
    return (things: things.values.toList(), dinners: dinners, first: first);
  }

  /// "There is shopping to do", the morning after there is some, and then
  /// every few days while there still is. Tonight's dinner is left to the
  /// cook's own reminders.
  Future<Nudge?> _shopOffer(DateTime now, Pantry house) async {
    final buy = toBuy(now, house);
    final first = buy.first;
    if (first == null) return null;
    final kept = int.tryParse(await store.read(_shopAskKey) ?? '');
    final last = kept == null ? null : DateTime.fromMillisecondsSinceEpoch(kept);
    final when = shopAskTime(now: now, morning: times.morning, lastAsk: last);
    if (when != last) await store.write(_shopAskKey, '${when.millisecondsSinceEpoch}');
    return shopNudge(when, things: buy.things, dinners: buy.dinners, first: first);
  }

  /// The offer of a new week, when the plan is about to run out. When it was
  /// last made is kept, so it comes every few days and not every evening.
  Future<Nudge?> _weekOffer(DateTime now) async {
    if (recipes.isEmpty || !planRunsOut(plan, now)) return null;
    final nights = draft(now);
    if (nights.isEmpty) return null;
    final kept = int.tryParse(await store.read(_weekAskKey) ?? '');
    final last = kept == null ? null : DateTime.fromMillisecondsSinceEpoch(kept);
    final when = weekAskTime(now: now, evening: times.evening, lastAsk: last);
    if (when != last) await store.write(_weekAskKey, '${when.millisecondsSinceEpoch}');
    return weekNudge(when, [for (final n in nights) (date: n.date, name: recipeName(n.slug))]);
  }

  /// Raises a notification for each change from another phone that concerns
  /// this phone's owner.
  Future<void> announce(List<Change> changes, DateTime now) async {
    for (final n in noticesFor(changes, me: me, myDev: core.dev, now: now, plan: plan, recipeName: recipeName)) {
      await notifier.show(n);
    }
  }

  /// How many stars this phone's owner gives [slug]: what they said here most
  /// recently, else what the recipe site has.
  int myStars(String slug) {
    final who = me;
    if (who == null) return 0;
    final said = rated[slug];
    if (said != null) return said.stars;
    final r = recipe(slug);
    return r == null ? 0 : (who == 'pink' ? r.pink : r.blue);
  }

  /// Records how this phone's owner found a dinner and queues it for the
  /// recipe site, with "we cooked this" the first time that day.
  Future<void> rate(String slug, int stars, DateTime now) async {
    final who = me;
    if (who == null) return;
    final day = dayText(now);
    final at = stamp(now).replaceFirst(RegExp(r'\.\d{3}Z$'), 'Z');
    final r = Random();
    String id() => '${now.millisecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 30).toRadixString(36)}';
    final firstToday = rated[slug]?.day != day;
    siteQueue.removeWhere((e) => e['k'] == 'rate' && e['slug'] == slug && e['who'] == who);
    siteQueue.add({'k': 'rate', 'slug': slug, 'who': who, 'stars': stars.clamp(1, 5), 'id': id(), 'at': at});
    if (firstToday) siteQueue.add({'k': 'cooked', 'slug': slug, 'id': id(), 'at': at});
    rated[slug] = (day: day, stars: stars.clamp(1, 5));
    // Answers older than a week have done their work.
    final cutoff = dayText(dayAfter(now, -7));
    rated.removeWhere((_, v) => v.day.compareTo(cutoff) < 0);
    await saveRates();
  }

  bool _landed(Map<String, Object?> e) {
    final sends = e['sends'] is int ? e['sends'] as int : 0;
    if (e['k'] == 'cooked') return sends >= 3;
    if (sends >= _siteSends) return true;
    final r = recipe(e['slug'] as String);
    final shown = r == null ? null : (e['who'] == 'pink' ? r.pink : r.blue);
    return sends > 0 && shown == e['stars'];
  }

  /// Sends what is queued for the recipe site, the same way its own pages do:
  /// a message on the site's topic, which its hourly job folds into the
  /// recipes. Only the recipe, "pink" or "blue" and the stars go out; the
  /// topic is public, so the household's names stay here.
  Future<void> flushSite(DateTime now) => _flushing ??= _flushSite(now).whenComplete(() => _flushing = null);

  /// One send at a time: two at once would each send what the other is sending.
  Future<void>? _flushing;

  Future<void> _flushSite(DateTime now) async {
    final before = siteQueue.length;
    siteQueue.removeWhere(_landed);
    var changed = siteQueue.length != before;
    try {
      if (siteQueue.isNotEmpty) siteTopic ??= await fetchSiteTopic(client, site);
      final topic = siteTopic;
      if (topic != null) {
        for (final e in siteQueue) {
          final sentAt = e['sentAt'];
          if (sentAt is int && now.millisecondsSinceEpoch - sentAt < _siteResend.inMilliseconds) continue;
          final payload = {...e}
            ..remove('sentAt')
            ..remove('sends');
          final who = e['who'], stars = e['stars'];
          final title = e['k'] == 'rate' ? '${who == 'pink' ? 'Pink' : 'Blue'}: $stars star${stars == 1 ? '' : 's'}' : 'Cooked tonight';
          final uri = Uri.https('ntfy.sh', '/$topic', {'title': title, 'tags': 'plate_with_cutlery'});
          final res = await client
              .post(uri, headers: {'Content-Type': 'text/plain; charset=utf-8'}, body: utf8.encode('${recipeName(e['slug'] as String)}\n\ndp1 ${jsonEncode(payload)}'))
              .timeout(const Duration(seconds: 20));
          if (res.statusCode != 200) break;
          e['sentAt'] = now.millisecondsSinceEpoch;
          e['sends'] = (e['sends'] is int ? e['sends'] as int : 0) + 1;
          changed = true;
        }
      }
    } on Exception {
      // Offline: what is queued goes out the next time round.
    }
    if (changed) await saveRates();
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
