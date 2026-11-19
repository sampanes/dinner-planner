import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_model.dart';
import 'background.dart';
import 'data/session.dart';
import 'data/store.dart';
import 'notify/notifier.dart';
import 'ui/home.dart';

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

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'Dinner Planner',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomeScreen(model: model),
    );
  }
}
