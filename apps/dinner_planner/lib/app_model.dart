// What the screens watch and call. Every change is shown at once, saved,
// turned into reminders, and then sent to the other phone.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core/nudges.dart';
import 'core/plan.dart';
import 'core/shopping.dart';
import 'core/store_order.dart';
import 'core/sync_core.dart';
import 'data/products.dart';
import 'data/recipes.dart';
import 'data/relay.dart';
import 'data/session.dart';
import 'data/suggest.dart';

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

  Future<void> _wrote(bool changed, {bool replan = true}) async {
    if (!changed) return;
    notifyListeners();
    await session.saveCore();
    if (replan) await session.replan(now);
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

  /// What the dinners planned from today on still need, added up.
  List<ShopLine> get shopping => shoppingList(_dinners, where: (id, day) => !_got(id, day));

  /// What has been ticked as in the house for those dinners.
  List<ShopLine> get shoppingGot => shoppingList(_dinners, where: _got);

  Future<void> setGot(ShopLine line, bool got) async {
    var changed = false;
    for (final u in line.uses) {
      changed = session.core.set(gotKey(line.id, u.day), got ? '1' : null, now) || changed;
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
  String section(String id) {
    final v = session.core.value(sectionKey(id));
    return v is String && sections.containsKey(v) ? v : guessSection(id);
  }

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
  Future<void> saveProduct(String id, {String? buy, String? size, String? section, Map<String, String> at = const {}, String? code}) {
    var changed = false;
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
    return _wrote(changed, replan: false);
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
        if (!l.loose) '- ${l.amountText} ${label(l)}',
      if (loose.isNotEmpty) 'Check you have: ${loose.join(', ')}',
    ].join('\n');
  }

  Future<bool> allowNotifications() => session.notifier.askPermission();

  Future<void> testReminder() => session.notifier.show(const Notice("You're cooking tonight", 'This is what a reminder looks like.'));

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
