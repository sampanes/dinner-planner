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
