// Renders the screens to PNG files for a person to look over. Skipped
// unless SHOTS_DIR names a folder:
//
//   SHOTS_DIR=/some/folder flutter test test/shots_test.dart
//
// The recipes are the repo's own data file; SHOTS_PHOTOS=1 also downloads
// the photos those recipes point at (otherwise the photo boxes stay blank).

import 'dart:async';
import 'dart:io';

import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:dinner_planner/ui/scan.dart';
import 'package:dinner_planner/ui/shop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ntfy.dart';

final String? shotsDir = Platform.environment['SHOTS_DIR'];
final bool withPhotos = Platform.environment['SHOTS_PHOTOS'] == '1';
final DateTime thursday = DateTime(2026, 11, 19, 16, 30);
final Map<String, Uint8List> photos = {};

Future<void> loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String name) async => ByteData.view((await File('$dir/$name').readAsBytes()).buffer);
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    roboto.addFont(bytes(f));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(bytes('materialicons-regular.otf'))).load();
  await (FontLoader('monospace')..addFont(bytes('roboto-regular.ttf'))).load();
}

/// Serves the downloaded photos to Image.network.
class _PhotoClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _PhotoRequest(photos['$url']);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _PhotoRequest implements HttpClientRequest {
  _PhotoRequest(this.bytes);

  final Uint8List? bytes;

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => _PhotoResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _PhotoResponse extends Stream<List<int>> implements HttpClientResponse {
  _PhotoResponse(this.bytes);

  final Uint8List? bytes;

  @override
  int get statusCode => bytes == null ? 404 : 200;

  @override
  int get contentLength => bytes?.length ?? 0;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable([bytes ?? Uint8List(0)]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  if (photos.isEmpty) return;
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e, onError: (_, _) {});
    }
  });
  await tester.pumpAndSettle();
}

Future<void> shoot(WidgetTester tester, String name) async {
  await settle(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$shotsDir/$name.png')));
}

void main() {
  final ntfy = FakeNtfy()..recipesJson = File('../../data/runtime/recipes.runtime.json').readAsStringSync();

  setUpAll(() async {
    // This runs even when every test below is skipped.
    if (shotsDir == null) return;
    autoUpdateGoldenFiles = true;
    await loadFonts();
    if (!withPhotos) return;
    // Outside the test zone, where real network calls are allowed.
    HttpOverrides.global = null;
    final wanted = <String>{};
    final model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()));
    await model.start();
    await model.refreshRecipes();
    for (final r in model.recipes) {
      if (_cast.contains(r.slug) && r.image != null) wanted.add(r.image!);
      if (r.thumb != null) wanted.add(r.thumb!);
    }
    final client = HttpClient();
    await Future.wait([
      for (final url in wanted)
        () async {
          try {
            final res = await (await client.getUrl(Uri.parse(url))).close();
            if (res.statusCode == 200) photos[url] = await consolidateHttpClientResponseBytes(res);
          } on Exception {
            // A missing photo is drawn as the blank box.
          }
        }()
    ]);
    client.close();
  });

  Future<AppModel> start(WidgetTester tester, {Brightness brightness = Brightness.light}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    // Tests draw shadows as hard black outlines unless told otherwise.
    debugDisableShadows = false;
    if (photos.isNotEmpty) debugNetworkImageHttpClientProvider = _PhotoClient.new;
    final model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
    await model.start();
    await tester.pumpWidget(DinnerApp(model: model));
    await tester.pumpAndSettle();
    return model;
  }

  /// Stops the app's timers and puts the debug switches back, which the test
  /// framework checks before the test body returns.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDisableShadows = true;
    debugNetworkImageHttpClientProvider = null;
  }

  Future<void> fillWeek(AppModel model, {required String me}) async {
    await model.setMe(me);
    await model.setName('blue', 'Sam');
    await model.setName('pink', 'Alex');
    const cooks = ['blue', 'pink', 'pink', 'blue', null, 'pink', 'blue'];
    for (var i = 0; i < _cast.length; i++) {
      final day = '2026-11-${19 + i}';
      await model.setMeal(day, _cast[i]);
      await model.setCook(day, cooks[i]);
    }
  }

  testWidgets('shots', (tester) async {
    var model = await start(tester);
    await shoot(tester, '01-first-run');

    await fillWeek(model, me: 'blue');
    await shoot(tester, '02-tonight-my-night');

    await tester.tap(find.byKey(const ValueKey('pick-tonight')));
    await shoot(tester, '03-pick-dinner');
    await tester.enterText(find.byType(TextField), 'shrimp');
    await shoot(tester, '04-pick-dinner-search');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Week'));
    await shoot(tester, '05-week');

    await tester.tap(find.text('Settings'));
    await shoot(tester, '06-settings');
    await model.startHousehold();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
    await shoot(tester, '07-settings-sharing');

    await tester.tap(find.text('Tonight'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('needs-tonight')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('needs-tonight')));
    await shoot(tester, '08-what-it-needs');
    await finish(tester);
  }, skip: shotsDir == null);

  testWidgets('shots: shopping', (tester) async {
    final model = await start(tester);
    await fillWeek(model, me: 'blue');
    await tester.tap(find.text('Shop'));
    await shoot(tester, '11-shop');

    await tester.tap(find.byKey(const ValueKey('store-add')));
    await tester.pumpAndSettle();
    for (final store in ['kroger', 'costco']) {
      await tester.tap(find.byKey(ValueKey('store-idea-$store')));
    }
    await shoot(tester, '12-shop-add-stores');
    await tester.tap(find.byKey(const ValueKey('store-save')));
    await tester.pumpAndSettle();

    await model.saveProduct('butter', buy: 'Salted, the four-stick box', size: '16 oz');
    await model.saveProduct('cheddar-cheese', buy: 'Sharp, shredded', size: '8 oz', at: {'kroger': 'Aisle 14'});
    await model.saveProduct('carrot', size: '2 lb');
    await model.saveProduct('ground-beef', buy: 'Store brand 88/12', size: '1 lb');
    await shoot(tester, '13-shop-what-you-buy');

    // A trip: the first things into the cart, then put back so the order shows.
    await tester.tap(find.byKey(const ValueKey('store-kroger')));
    await tester.pumpAndSettle();
    for (final id in ['ground-beef', 'shrimp', 'cheddar-cheese', 'butter', 'sour-cream', 'carrot', 'broccoli', 'celery']) {
      await model.setGot(model.shopping.firstWhere((l) => l.id == id), true);
    }
    for (final l in model.shoppingGot) {
      if (l.id != 'celery' && l.id != 'broccoli') await model.setGot(l, false);
    }
    await shoot(tester, '14-shop-in-a-store');

    await tester.tap(find.byKey(const ValueKey('shop-edit-cheddar-cheese')));
    await shoot(tester, '15-shop-product');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final list = find.descendant(of: find.byType(ShopScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('got-celery')), 400, scrollable: list);
    await tester.drag(list, const Offset(0, -400));
    await shoot(tester, '16-shop-check-and-got');
    await finish(tester);
  }, skip: shotsDir == null);

  testWidgets('shots: scanning a packet', (tester) async {
    final model = await start(tester);
    await fillWeek(model, me: 'blue');
    // The camera cannot be drawn here: a gray box stands where its picture goes.
    final real = buildCamera;
    late ValueChanged<String> camera;
    buildCamera = (context, onCode) {
      camera = onCode;
      return const ColoredBox(color: Color(0xFF2B2B2B), child: Center(child: Icon(Icons.photo_camera_outlined, size: 72, color: Colors.white24)));
    };
    addTearDown(() => buildCamera = real);
    ntfy.openFoodFacts['012345000019'] = {'product_name': 'Sour Cream', 'brands': 'Meadow Farm', 'quantity': '16 oz'};
    ntfy.openFoodFacts['012345000033'] = {'product_name': 'Ground Coffee', 'brands': 'Bean Barn', 'quantity': '12 oz'};
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shop-scan')));
    await shoot(tester, '23-scan-camera-stays-open');
    camera('012345000019');
    await shoot(tester, '17-scan-which-ingredient');
    await tester.tap(find.byKey(const ValueKey('match-sour-cream')));
    await shoot(tester, '18-scan-filled-in');
    await tester.tap(find.byKey(const ValueKey('shop-buy-save')));
    await shoot(tester, '24-scan-got-and-next');

    await tester.tap(find.byKey(const ValueKey('scan-type')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('scan-number')), '0 12345 00003 3');
    await shoot(tester, '25-scan-type-the-number');
    await tester.tap(find.byKey(const ValueKey('scan-number-use')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('match-extra')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('extra-name')), 'Coffee');
    await shoot(tester, '26-scan-not-for-a-recipe');
    await tester.tap(find.byKey(const ValueKey('extra-want')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scan-done')));
    await tester.pumpAndSettle();

    await model.addExtra('Milk');
    await model.addExtra('Paper towels');
    await model.setGot(model.shopping.firstWhere((l) => l.id == 'paper-towels'), true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shop-add')));
    await shoot(tester, '28-shop-add-something');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byType(ShopScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('shop-coffee')), 300, scrollable: list);
    await tester.drag(list, const Offset(0, -260));
    await shoot(tester, '27-shop-with-extras');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('got-sour-cream')), 400, scrollable: list);
    await shoot(tester, '19-scan-ticked');
    await finish(tester);
  }, skip: shotsDir == null);

  testWidgets('shots: start here', (tester) async {
    final model = await start(tester);
    await model.setMe('blue');
    await model.setName('blue', 'Sam');
    await model.setName('pink', 'Alex');
    await shoot(tester, '20-start-here');

    await model.setMeal('2026-11-20', _cast[1]);
    await model.setCook('2026-11-20', 'blue');
    await model.setMeal('2026-11-21', _cast[3]);
    await model.addStores(['Costco', 'Kroger']);
    await shoot(tester, '21-start-here-under-way');

    await model.setMeal('2026-11-19', _cast[0]);
    await model.setCook('2026-11-19', 'blue');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
    await shoot(tester, '22-start-here-on-a-cooking-night');
    await finish(tester);
  }, skip: shotsDir == null);

  testWidgets('shots: the other phone, dark', (tester) async {
    final model = await start(tester, brightness: Brightness.dark);
    await fillWeek(model, me: 'pink');
    await shoot(tester, '09-tonight-their-night-dark');
    await tester.tap(find.text('Week'));
    await shoot(tester, '10-week-dark');
    await finish(tester);
  }, skip: shotsDir == null);
}

const List<String> _cast = [
  'firecracker-meatballs',
  'garlic-butter-shrimp-scampi',
  'one-pan-cantina-shrimp-fajitas',
  'beef-black-bean-chili',
  'mozzarella-herb-chicken',
  'italian-sausage-rigatoni',
  'pub-style-shepherd-s-pie',
];
