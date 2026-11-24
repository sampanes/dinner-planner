import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_model.dart';
import 'background.dart';
import 'data/session.dart';
import 'data/store.dart';
import 'notify/notifier.dart';
import 'ui/home.dart';
import 'ui/note_page.dart';
import 'ui/timer_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifier = LocalNotifier();
  await notifier.init();
  final model = AppModel(Session(store: PrefsStore(), client: http.Client(), notifier: notifier));
  await model.start();
  unawaited(startBackgroundSync());
  runApp(DinnerApp(model: model));
}

class DinnerApp extends StatelessWidget {
  const DinnerApp({super.key, required this.model});

  final AppModel model;

  static const Color _seed = Color(0xFFB4532A);

  /// The page a link opens, or null when the link is not one of ours. Android
  /// hands over the whole link when it starts the app
  /// (`dinnerplanner://open/note?slug=...`) and Flutter passes on only its
  /// path and query (`/note?slug=...`) when the app is already running.
  Route<void>? _linked(String? name) {
    final link = Uri.tryParse(name ?? '');
    final target = model.noteLink(link);
    if (target != null) return MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => NotePage(model: model, target: target));
    // A timer the kitchen page hands over: taken, said, and back to the page.
    final timer = model.timerLink(link);
    return timer == null ? null : MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => TimerPage(model: model, ask: timer));
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
          useMaterial3: true,
        );
    Route<void> home() => MaterialPageRoute<void>(settings: const RouteSettings(name: '/'), builder: (_) => HomeScreen(model: model));
    return MaterialApp(
      title: 'Dinner Planner',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      // The home screen always sits underneath, whatever opened the app.
      onGenerateInitialRoutes: (initial) => [home(), ?_linked(initial)],
      onGenerateRoute: (settings) => settings.name == '/' ? home() : _linked(settings.name),
      // A link that is not ours opens nothing: a page that closes itself.
      onUnknownRoute: (_) => MaterialPageRoute<void>(builder: (_) => const _Gone()),
    );
  }
}

class _Gone extends StatefulWidget {
  const _Gone();

  @override
  State<_Gone> createState() => _GoneState();
}

class _GoneState extends State<_Gone> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
