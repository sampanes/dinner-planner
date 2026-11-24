// What the screens watch and call. Every change is shown at once, saved,
// turned into reminders, and then sent to the other phone.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/nudges.dart';
import 'core/plan.dart';
import 'core/shopping.dart';
import 'core/store_order.dart';
import 'core/sync_core.dart';
import 'data/autoplan.dart';
import 'data/products.dart';
import 'data/recipes.dart';
import 'data/relay.dart';
import 'data/session.dart';
import 'data/suggest.dart';
import 'notify/notifier.dart';

/// What a new phone is walked through, in the order a first week brings
/// them up.
enum StartStep { plan, stores, scan, walk, share }

/// Something a tapped reminder, or a link from the kitchen page, asks the
/// screens to do. The model queues them; the home screen carries them out.
sealed class Ask {
  const Ask();
}

/// Switch to a tab, by its place in the bar.
class AskTab extends Ask {
  const AskTab(this.tab);
  final int tab;
}

/// Say what was just done, with a way to take it back.
class AskSay extends Ask {
  const AskSay(this.text, [this.undo]);
  final String text;
  final Future<void> Function()? undo;
}

/// Ask what tonight is instead of the planned dinner.
class AskSkip extends Ask {
  const AskSkip(this.day);
  final String day;
}

/// Show the drafted week for looking over.
class AskDraft extends Ask {
  const AskDraft();
}

/// What a change made in one go says about itself, and how to take it back.
typedef Done = ({String text, Future<void> Function() undo});

/// Where a note from the kitchen page goes: a recipe, and one of its steps
/// (its place in the recipe and its words) unless it is about the whole thing.
typedef NoteTarget = ({String slug, int? place, String? step});

class AppModel extends ChangeNotifier {
  AppModel(this.session, {DateTime Function()? clock, Future<bool> Function(Uri page)? open})
      : _clock = clock ?? DateTime.now,
        _open = open ?? ((page) => launchUrl(page, mode: LaunchMode.externalApplication));

  final Session session;
  final DateTime Function() _clock;
  final Future<bool> Function(Uri page) _open;
  final List<Ask> _asks = [];

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
    session.notifier.onTap = (tap) => unawaited(handleTap(tap));
    final launched = await session.notifier.launchTap();
    if (launched != null) await handleTap(launched);
  }

  void _ask(Ask ask) {
    _asks.add(ask);
    notifyListeners();
  }

  /// What the screens have been asked to do since the last call.
  List<Ask> takeAsks() {
    final out = List<Ask>.of(_asks);
    _asks.clear();
    return out;
  }

  /// The recipe's step-by-step page, in the browser.
  Future<void> openRecipe(String slug) => _open(kitchenPage(site, slug));

  /// A reminder, or one of its buttons, was tapped.
  Future<void> handleTap(NudgeTap tap) async {
    final ref = tap.ref;
    final today = this.today();
    final slug = ref.slug.isEmpty ? null : ref.slug;
    switch (tap.button) {
      case 'have':
        _ask(const AskTab(0));
        if (ref.day.compareTo(today) >= 0) {
          final done = await haveAll(ref.day);
          if (done != null) _ask(AskSay(done.text, done.undo));
        }
      case 'list':
        _ask(const AskTab(2));
      case 'skip':
        _ask(const AskTab(0));
        if (ref.day == today && plan.off(today) == null) _ask(AskSkip(today));
      case 'use':
        _ask(const AskTab(1));
        final done = await useDraft(draft());
        _ask(done == null ? const AskSay('The week is already planned.') : AskSay(done.text, done.undo));
      case 'change':
        _ask(const AskTab(1));
        _ask(const AskDraft());
      case final button? when rateStars.containsKey(button):
        _ask(const AskTab(0));
        if (slug != null) {
          await rate(slug, rateStars[button]!);
          _ask(AskSay('${session.recipeName(slug)}: ${rateStars[button]} stars. Thanks.'));
        }
      default:
        switch (ref.kind) {
          case 'start' when slug != null && ref.day == today && plan.meal(today) == slug:
            await openRecipe(slug);
          case 'eve' when slug != null && session.facts(ref.day, slug).missing.isNotEmpty:
            _ask(const AskTab(2));
          case 'week':
            _ask(const AskTab(1));
            _ask(const AskDraft());
          default:
            _ask(const AskTab(0));
        }
    }
  }

  /// What a link that opened the app is asking for. The kitchen page's
  /// "Note" button is the only one: `dinnerplanner://open/note?slug=...&step=...`,
  /// where the step is named by its id ([stepId]). Null for anything else. A
  /// step this phone does not know (its recipes are older than the page's)
  /// becomes a note on the whole recipe.
  NoteTarget? noteLink(Uri? link) {
    if (link == null || !(link.path.endsWith('/note') || link.path == 'note' || link.host == 'note')) return null;
    final slug = link.queryParameters['slug'];
    if (slug == null || slug.isEmpty || slug.length > 60) return null;
    final steps = session.recipe(slug)?.steps ?? const <String>[];
    final at = [for (final s in steps) stepId(s)].indexOf(link.queryParameters['step'] ?? '');
    return (slug: slug, place: at < 0 ? null : at, step: at < 0 ? null : steps[at]);
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
    unawaited(session.flushSite(now));
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

  Future<void> _wrote(bool changed, {bool replan = true}) async {
    if (!changed) return;
    notifyListeners();
    await session.saveCore();
    if (replan) await session.replan(now);
    unawaited(sync());
  }

  /// Sets several shared facts in one go and says how to put them back.
  Future<Future<void> Function()> _setAll(Map<String, Object?> values, {bool replan = true}) async {
    final before = {for (final k in values.keys) k: session.core.value(k)};
    var changed = false;
    values.forEach((k, v) => changed = session.core.set(k, v, now) || changed);
    await _wrote(changed, replan: replan);
    return () async {
      var back = false;
      before.forEach((k, v) => back = session.core.set(k, v, now) || back);
      await _wrote(back, replan: replan);
    };
  }

  /// Picking a dinner for a night that was called off puts the night back on.
  Future<void> setMeal(String day, String? slug) {
    var changed = session.core.set(mealKey(day), slug, now);
    if (slug != null) changed = session.core.set(offKey(day), null, now) || changed;
    return _wrote(changed);
  }

  /// The first night after [day], within the fortnight, with no dinner on it.
  String? _nextFree(String day) {
    final from = parseDay(day);
    if (from == null) return null;
    final last = dayText(dayAfter(now, 13));
    for (var i = 1; i < 14; i++) {
      final d = dayText(dayAfter(from, i));
      if (d.compareTo(last) > 0) break;
      if (plan.meal(d) == null && plan.off(d) == null) return d;
    }
    return null;
  }

  /// Where the dinner on [day] would go if that night were called off, or
  /// null when it has nowhere to go (or there is no dinner to move).
  String? movesTo(String day) => plan.meal(day) == null ? null : _nextFree(day);

  /// "Not tonight": nobody cooks on [day] ([why] is a key of [offKinds]). The
  /// dinner that was planned moves to the next free night with everything
  /// that was ticked for it, and with its cook when that night has none.
  Future<Done> skipDinner(String day, String why) async {
    final slug = plan.meal(day);
    final to = movesTo(day);
    final values = <String, Object?>{offKey(day): why, mealKey(day): null, cookKey(day): null};
    if (slug != null && to != null) {
      values[mealKey(to)] = slug;
      final cook = plan.cook(day);
      if (cook != null && plan.cook(to) == null) values[cookKey(to)] = cook;
      for (final i in session.recipe(slug)?.ingredients ?? const <Ingredient>[]) {
        if (_got(i.id, day)) {
          values[gotKey(i.id, to)] = '1';
          values[gotKey(i.id, day)] = null;
        }
      }
    }
    final undo = await _setAll(values);
    final String text;
    if (slug == null) {
      text = '${offKinds[why]} it is.';
    } else if (to == null) {
      text = '${session.recipeName(slug)} is off the plan: the next two weeks are full.';
    } else {
      text = '${session.recipeName(slug)} moved to ${dayLabel(parseDay(to)!, now)}.';
    }
    return (text: text, undo: undo);
  }

  /// The night is back on: someone cooks after all.
  Future<void> cookAfterAll(String day) => _wrote(session.core.set(offKey(day), null, now));

  /// "All here": everything the dinner on [day] still asks for is in the
  /// house. Null when there is no dinner or nothing was missing.
  Future<Done?> haveAll(String day) async {
    final slug = plan.meal(day), recipe = session.recipe(slug);
    if (slug == null || recipe == null) return null;
    final values = <String, Object?>{
      for (final i in recipe.ingredients)
        if (session.needs(i.id, day)) gotKey(i.id, day): '1',
    };
    if (values.isEmpty) return null;
    final undo = await _setAll(values);
    return (text: 'Everything for ${recipe.name} is ticked.', undo: undo);
  }

  /// Dinners for the empty nights of the coming week, for looking over.
  List<DraftNight> draft() => session.draft(now);

  /// How many of the next seven nights have neither a dinner nor a reason
  /// not to cook.
  int get emptyNights {
    var n = 0;
    for (var i = 1; i <= 7; i++) {
      final d = dayText(dayAfter(now, i));
      if (plan.meal(d) == null && plan.off(d) == null) n++;
    }
    return n;
  }

  /// Puts [nights] on the plan, leaving alone any night that has been filled
  /// since they were drafted. Null when nothing was left to do.
  Future<Done?> useDraft(List<DraftNight> nights) async {
    final values = <String, Object?>{};
    var count = 0;
    for (final n in nights) {
      if (plan.meal(n.day) != null || plan.off(n.day) != null) continue;
      values[mealKey(n.day)] = n.slug;
      if (n.cook != null && plan.cook(n.day) == null) values[cookKey(n.day)] = n.cook;
      count++;
    }
    if (count == 0) return null;
    final undo = await _setAll(values);
    return (text: '$count dinner${count == 1 ? '' : 's'} planned. The list has what they need.', undo: undo);
  }

  /// How many stars this phone's owner gives a recipe, 0 for none yet.
  int myStars(String slug) => session.myStars(slug);

  /// True once this phone's owner has said today how [slug] was.
  bool ratedToday(String slug) => session.rated[slug]?.day == today();

  /// Whether dinner time has come, so "how was it?" makes sense.
  bool get afterDinner => now.hour * 60 + now.minute >= times.eat;

  /// This phone's owner says how a dinner was. It goes to the recipe site,
  /// where both people's stars steer what gets suggested.
  Future<void> rate(String slug, int stars) async {
    if (me == null) return;
    await session.rate(slug, stars, now);
    notifyListeners();
    await session.replan(now);
    unawaited(session.flushSite(now));
  }

  Future<void> setCook(String day, String? who) => _wrote(session.core.set(cookKey(day), who, now));

  Future<void> setName(String who, String name) {
    final text = name.trim();
    return _wrote(session.core.set(nameKey(who), text.isEmpty ? null : text, now));
  }

  /// Saves the household's note on a recipe, or on one of its steps when
  /// [step] is that step's text; blank clears it.
  Future<void> setNote(String slug, String text, {String? step}) {
    final t = text.trim();
    if (step == null) {
      return _wrote(session.core.set(noteKey(slug), t.isEmpty ? null : _cut(t, noteMax), now), replan: false);
    }
    return _wrote(session.core.set(stepNoteKey(slug, step), t.isEmpty ? null : '${stepAnchor(step)}\n${_cut(t, stepNoteMax)}', now), replan: false);
  }

  /// Changes a note that is already there, keeping the step it is on; blank
  /// clears it.
  Future<void> changeNote(NoteLine note, String text) {
    final t = text.trim();
    final Object? value = t.isEmpty
        ? null
        : note.step == null
            ? _cut(t, noteMax)
            : '${note.anchor ?? ''}\n${_cut(t, stepNoteMax)}';
    return _wrote(session.core.set(note.key, value, now), replan: false);
  }

  static String _cut(String text, int max) => text.length > max ? text.substring(0, max) : text;

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
    session.siteTopic = null;
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

  /// The first steps already taken. They are read off what the phone holds,
  /// so nothing has to be ticked; what the other phone did counts too.
  Set<StartStep> get startDone {
    final meals = <String>{}, cooks = <String>{};
    var scanned = false, walked = false;
    for (final e in session.core.entries) {
      if (e.value == null) continue;
      final k = e.key;
      if (k.startsWith('meal/')) meals.add(k.substring(5));
      if (k.startsWith('cook/')) cooks.add(k.substring(5));
      if (k.startsWith('code/')) scanned = true;
      if (k.startsWith('pos/')) walked = true;
    }
    return {
      if (meals.any(cooks.contains)) StartStep.plan,
      if (stores.isNotEmpty) StartStep.stores,
      if (scanned) StartStep.scan,
      if (walked) StartStep.walk,
      if (household != null) StartStep.share,
    };
  }

  /// The steps were skipped on this phone.
  bool get startHidden => session.startHidden;

  Future<void> hideStart(bool hidden) async {
    session.startHidden = hidden;
    await session.saveSettings();
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

  /// [pool] ranked as dinners for [day], given what the other days of the
  /// fortnight already hold.
  List<Suggestion> suggestFor(String? day, Iterable<Recipe> pool) {
    final others = <Recipe>[];
    for (var i = 0; i < 14; i++) {
      final d = dayText(dayAfter(now, i));
      if (d != day) {
        if (session.recipe(plan.meal(d)) case final r?) others.add(r);
      }
    }
    return suggest(pool, planned: others, names: {for (final who in people) who: plan.name(who)});
  }

  List<ShopDinner> get _dinners => [
        for (var i = 0; i < 14; i++)
          if (session.recipe(plan.meal(dayText(dayAfter(now, i)))) case final r?)
            ShopDinner(day: dayText(dayAfter(now, i)), slug: r.slug, ingredients: r.ingredients)
      ];

  bool _got(String id, String day) => session.core.value(gotKey(id, day)) == '1';

  /// The things the household buys that no recipe asks for, id -> name.
  Map<String, String> get extras => {
        for (final e in session.core.entries)
          if (e.key.startsWith('extra/') && e.value is String && (e.value as String).isNotEmpty) e.key.substring(6): e.value as String,
      };

  bool _wanted(String id) => session.core.value(wantKey(id)) == '1';

  /// A dinner needs it, and it is wanted for the house besides.
  bool wantedToo(String id) => _wanted(id);

  List<ShopLine> _withExtras(List<ShopLine> lines, bool Function(String id) where) {
    final have = {for (final l in lines) l.id};
    // An extra, or a staple that has run out while no dinner asks for it.
    final names = {
      for (final e in ingredientNames.entries)
        if (staple(e.key)) e.key: e.value,
      ...extras,
    };
    return [
      ...lines,
      for (final e in names.entries)
        if (!have.contains(e.key) && where(e.key)) ShopLine(e.key, e.value, extra: true),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// What is still to buy: what the dinners planned from today on need,
  /// added up, without what is always in the house; and the extras, and the
  /// staples that have run out.
  List<ShopLine> get shopping => _withExtras(shoppingList(_dinners, where: session.needs), _wanted);

  /// What has been ticked as in the house: for those dinners, and the
  /// extras got today.
  List<ShopLine> get shoppingGot => _withExtras(shoppingList(_dinners, where: _got), (id) => !_wanted(id) && _got(id, today()));

  /// Every name a barcode can stand for: the recipes' ingredients and the
  /// household's extras.
  Map<String, String> get itemNames => {...extras, ...ingredientNames};

  /// Puts something no recipe asks for on the list (or, with [want] false,
  /// only remembers it), and returns its id; null when [name] has no letters.
  /// [code], [buy] and [size] are the packet it was scanned from.
  Future<String?> addExtra(String name, {bool want = true, String? code, String? buy, String? size}) async {
    final text = name.trim(), id = slugOf(text);
    if (id.isEmpty) return null;
    var changed = false;
    if (!extras.containsKey(id)) {
      changed = session.core.set(extraKey(id), text.length > 40 ? text.substring(0, 40) : text, now);
    }
    if (want) {
      changed = session.core.set(wantKey(id), '1', now) || changed;
      changed = session.core.set(gotKey(id, today()), null, now) || changed;
    }
    if (code != null) changed = session.core.set(codeKey(code), id, now) || changed;
    if (buy != null && buy.trim().isNotEmpty && this.buy(id) == null) changed = session.core.set(buyKey(id), buy.trim(), now) || changed;
    if (size != null && size.trim().isNotEmpty && this.size(id) == null) changed = session.core.set(sizeKey(id), size.trim(), now) || changed;
    await _wrote(changed, replan: false);
    return id;
  }

  /// Always in the house, so no dinner puts it on the list.
  bool staple(String id) => session.staple(id);

  /// Says whether the household always has [id]. Saying so takes it off the
  /// list; "want" then puts it back the day it runs out.
  Future<Done> setStaple(String id, bool always, {String? name}) async {
    final undo = await _setAll({
      // Saying what the app already assumes is not worth a shared fact.
      haveKey(id): always == usualStaples.contains(id) ? null : (always ? '1' : '0'),
      if (always) wantKey(id): null,
    });
    final label = name ?? itemNames[id] ?? id;
    return (text: always ? '$label: always in the house, so off the list.' : '$label goes on the list when a dinner needs it.', undo: undo);
  }

  /// A staple has run out: on the list until it is bought.
  Future<void> ranOut(String id, bool out) => _wrote(session.core.set(wantKey(id), out ? '1' : null, now));

  /// What the household always has, of the things its recipes use, by name.
  /// [out] is true while one is on the list because it ran out.
  List<({String id, String name, bool out})> get staples {
    final out = [
      for (final e in ingredientNames.entries)
        if (staple(e.key)) (id: e.key, name: e.value, out: _wanted(e.key)),
    ];
    return out..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// True once the household has said so for at least one thing itself.
  bool get staplesTaught => session.core.entries.any((e) => e.key.startsWith('have/') && e.value != null);

  /// Puts a known extra on the list, or takes it off without calling it got.
  Future<void> wantExtra(String id, bool want) => _wrote(session.core.set(wantKey(id), want ? '1' : null, now), replan: false);

  /// The household no longer buys this; its packet details are kept in case.
  Future<void> forgetExtra(String id) {
    var changed = session.core.set(extraKey(id), null, now);
    changed = session.core.set(wantKey(id), null, now) || changed;
    return _wrote(changed, replan: false);
  }

  Future<void> setGot(ShopLine line, bool got) async {
    var changed = false;
    for (final u in line.uses) {
      changed = session.core.set(gotKey(line.id, u.day), got ? '1' : null, now) || changed;
    }
    if (line.extra) {
      changed = session.core.set(wantKey(line.id), got ? null : '1', now) || changed;
      changed = session.core.set(gotKey(line.id, today()), got ? '1' : null, now) || changed;
    } else if (got && _wanted(line.id)) {
      // Wanted for the house as well as for a dinner: one tick covers both.
      changed = session.core.set(wantKey(line.id), null, now) || changed;
    }
    final store = shoppingAt;
    if (got && store != null) {
      // Ticked in a store: this is where it comes on the way round.
      learnWalk(_walk(store), line.id, session.tripLast).forEach((id, place) {
        changed = session.core.set(posKey(store, id), place, now) || changed;
      });
      session.tripLast = line.id;
      session.tripAt = now;
      await session.saveTrip();
    }
    await _wrote(changed, replan: false);
  }

  /// What the household actually buys for an ingredient, or null.
  String? buy(String id) => _text(buyKey(id));

  Future<void> setBuy(String id, String text) {
    final t = text.trim();
    return _wrote(session.core.set(buyKey(id), t.isEmpty ? null : t, now), replan: false);
  }

  /// What one packet holds ("16 oz"), or null.
  String? size(String id) => _text(sizeKey(id));

  String? _text(String key) {
    final v = session.core.value(key);
    return v is String && v.isNotEmpty ? v : null;
  }

  /// How many packets the line takes, when its amounts and the packet size
  /// can be compared.
  int? packs(ShopLine line) {
    final s = size(line.id);
    return s == null ? null : packsNeeded(line.totals, s);
  }

  /// The section an ingredient is in: what the household said, else a guess.
  String section(String id) => session.section(id);

  /// The stores the household shops at, by name.
  List<({String id, String name})> get stores {
    final out = <({String id, String name})>[];
    for (final e in session.core.entries) {
      final v = e.value;
      if (e.key.startsWith('store/') && v is String && v.isNotEmpty) out.add((id: e.key.substring(6), name: v));
    }
    return out..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  String storeName(String store) => _text(storeKey(store)) ?? store;

  Future<void> addStores(Iterable<String> names) {
    var changed = false;
    for (final raw in names) {
      final name = raw.trim(), slug = storeSlug(name);
      if (slug.isEmpty || _text(storeKey(slug)) != null) continue;
      changed = session.core.set(storeKey(slug), name.length > 40 ? name.substring(0, 40) : name, now) || changed;
    }
    return _wrote(changed, replan: false);
  }

  Future<void> removeStore(String store) async {
    if (session.tripStore == store) await shopAt(null);
    await _wrote(session.core.set(storeKey(store), null, now), replan: false);
  }

  /// A note on where an ingredient is in a store ("Aisle 7"), or null.
  String? at(String store, String id) => _text(atKey(store, id));

  /// How long after the last tick this phone still counts as in the store.
  static const Duration tripRests = Duration(hours: 2);

  /// The store this phone's owner is shopping in right now, or null.
  String? get shoppingAt {
    final store = session.tripStore, at = session.tripAt;
    if (store == null || at == null || now.difference(at) > tripRests) return null;
    return _text(storeKey(store)) == null ? null : store;
  }

  /// "I am in this store" (or, with null, "I have left"). While it holds the
  /// list is in that store's order and ticks teach it the order.
  Future<void> shopAt(String? store) async {
    session.tripStore = store;
    session.tripAt = store == null ? null : now;
    session.tripLast = null;
    await session.saveTrip();
    notifyListeners();
  }

  Map<String, double> _walk(String store) {
    final prefix = 'pos/$store/';
    return {
      for (final e in session.core.entries)
        if (e.key.startsWith(prefix) && e.value is num) e.key.substring(prefix.length): (e.value as num).toDouble(),
    };
  }

  /// What is still to buy, by section, in the order of the store this phone
  /// is in (or the usual order when it is in none).
  List<ShopGroup> get shoppingGroups {
    final store = shoppingAt;
    return arrange([for (final l in shopping) if (!l.loose) l], sectionOf: section, walk: store == null ? const {} : _walk(store));
  }

  /// Everything the household records about what it buys for an ingredient,
  /// saved in one go. A null leaves that part as it is; '' clears it.
  Future<void> saveProduct(String id, {String? buy, String? size, String? section, Map<String, String> at = const {}, String? code, bool? always}) {
    var changed = false;
    if (always != null && always != staple(id)) {
      changed = session.core.set(haveKey(id), always == usualStaples.contains(id) ? null : (always ? '1' : '0'), now);
      if (always) changed = session.core.set(wantKey(id), null, now) || changed;
    }
    void put(String key, String? text, {int max = 120}) {
      if (text == null) return;
      final t = text.trim();
      changed = session.core.set(key, t.isEmpty ? null : (t.length > max ? t.substring(0, max) : t), now) || changed;
    }

    put(buyKey(id), buy, max: 200);
    put(sizeKey(id), size, max: 40);
    if (section != null) {
      // Saying what the guess already says is not worth a shared fact.
      changed = session.core.set(sectionKey(id), section.isEmpty || section == guessSection(id) ? null : section, now) || changed;
    }
    at.forEach((store, text) => put(atKey(store, id), text, max: 60));
    // The packet's barcode now means this ingredient, on both phones.
    if (code != null) changed = session.core.set(codeKey(code), id, now) || changed;
    // What is always in the house changes what a reminder calls missing.
    return _wrote(changed, replan: always != null);
  }

  /// The ingredient a barcode was saved for, or null.
  String? ingredientForCode(String code) => _text(codeKey(code));

  /// Every ingredient any recipe uses, id -> name.
  Map<String, String> get ingredientNames => {
        for (final r in recipes)
          for (final i in r.ingredients) i.id: i.name,
      };

  /// What the public lists say a barcode is, or null.
  Future<Product?> lookUp(String code) => lookUpProduct(session.client, code, usdaKey: session.usdaKey);

  String get usdaKey => session.usdaKey;

  Future<void> setUsdaKey(String key) async {
    session.usdaKey = key.trim();
    await session.saveSettings();
    notifyListeners();
  }

  /// The list as plain text, for pasting anywhere.
  String shoppingText() {
    final lines = shopping;
    String label(ShopLine l) => buy(l.id) == null ? l.name : '${buy(l.id)} (${l.name})';
    final loose = [for (final l in lines) if (l.loose) label(l)];
    return [
      for (final l in lines)
        if (!l.loose) '- ${l.extra ? '' : '${l.amountText} '}${label(l)}',
      if (loose.isNotEmpty) 'Check you have: ${loose.join(', ')}',
    ].join('\n');
  }

  Future<bool> allowNotifications() => session.notifier.askPermission();

  Future<void> testReminder() => session.notifier.show(const Notice(
        "You're cooking tonight: Beef Chili",
        'This is what a reminder looks like. Start by 5:15 pm to eat at 6:00 pm. Still to get: sour cream and limes.',
        ref: NudgeRef('test'),
        buttons: [listButton],
      ));

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
