import 'package:flutter/material.dart';

import '../app_model.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.model.wake();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
