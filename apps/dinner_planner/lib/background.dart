// The hourly background sync. Without it a night the other phone hands to
// this one would get no reminder until the app was next opened, and a
// message could expire on the relay before this phone ever read it.

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'data/session.dart';
import 'data/store.dart';
import 'notify/notifier.dart';

const String syncTask = 'dinner-planner-sync';

@pragma('vm:entry-point')
void backgroundMain() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final store = PrefsStore();
    final now = DateTime.now();
    // The open app syncs on its own; two writers would undo each other.
    if (await Session.appIsOpen(store, now)) return true;
    final client = http.Client();
    try {
      final session = Session(store: store, client: client, notifier: LocalNotifier());
      await session.load();
      final report = await session.sync(now);
      await session.announce(report.changes, now);
      await session.replan(now);
    } finally {
      client.close();
    }
    return true;
  });
}

Future<void> startBackgroundSync() async {
  await Workmanager().initialize(backgroundMain);
  await Workmanager().registerPeriodicTask(
    syncTask,
    syncTask,
    frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
