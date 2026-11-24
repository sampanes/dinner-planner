import 'package:flutter/material.dart';

import '../app_model.dart';
import 'parts.dart';
import 'settings.dart';
import 'shop.dart';
import 'tonight.dart';
import 'week.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.model.addListener(_asked);
    widget.model.wake();
    // A reminder that started the app has already asked for something.
    WidgetsBinding.instance.addPostFrameCallback((_) => _asked());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.model.removeListener(_asked);
    widget.model.sleep();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.model.wake();
    } else if (state == AppLifecycleState.paused) {
      widget.model.sleep();
    }
  }

  /// Carries out what a tapped reminder asked for, one thing after another:
  /// the right tab first, then the sheet or the message on top of it.
  Future<void> _asked() async {
    if (_busy || !mounted) return;
    _busy = true;
    try {
      while (mounted) {
        final asks = widget.model.takeAsks();
        if (asks.isEmpty || !mounted) break;
        // Whatever was open belongs to what the person was doing before.
        Navigator.of(context).popUntil((route) => route.isFirst);
        for (final ask in asks) {
          if (!mounted) return;
          switch (ask) {
            case AskTab(:final tab):
              setState(() => _tab = tab);
            case AskSay(:final text, :final undo):
              say(ScaffoldMessenger.of(context), text, undo);
            case AskSkip(:final day):
              await showSkip(context, widget.model, day);
            case AskDraft():
              await showDraft(context, widget.model);
          }
        }
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: [
              TonightScreen(model: model, onOpen: (tab) => setState(() => _tab = tab)),
              WeekScreen(model: model),
              ShopScreen(model: model, onOpenWeek: () => setState(() => _tab = 1)),
              SettingsScreen(model: model),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant), label: 'Tonight'),
            NavigationDestination(icon: Icon(Icons.calendar_view_week_outlined), selectedIcon: Icon(Icons.calendar_view_week), label: 'Week'),
            NavigationDestination(icon: Icon(Icons.shopping_basket_outlined), selectedIcon: Icon(Icons.shopping_basket), label: 'Shop'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
