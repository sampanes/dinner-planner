import 'dart:async';

import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/nudges.dart';

/// A timer started on the recipe page lands here for a moment: the phone
/// takes it over, says so, and steps back behind the recipe. From then on it
/// rings when it is done, whatever the screen is doing.
class TimerPage extends StatefulWidget {
  const TimerPage({super.key, required this.model, required this.ask});

  final AppModel model;
  final TimerAsk ask;

  /// How long the page stays up before the recipe is back in front.
  static const Duration shown = Duration(milliseconds: 1100);

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  Timer? _leave;

  @override
  void initState() {
    super.initState();
    widget.model.setTimer(widget.ask);
    _leave = Timer(TimerPage.shown, _back);
  }

  @override
  void dispose() {
    _leave?.cancel();
    super.dispose();
  }

  void _back() {
    _leave?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.model.installer.stepBack();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = widget.ask.end;
    return Scaffold(
      body: SafeArea(
        child: InkWell(
          onTap: _back,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(end == null ? Icons.timer_off_outlined : Icons.timer_outlined, size: 72, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    end == null ? 'Timer stopped' : 'Rings at ${clockText(end.hour * 60 + end.minute)}',
                    key: const ValueKey('timer-said'),
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(widget.ask.label, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                  if (end != null) ...[
                    const SizedBox(height: 16),
                    Text('It rings even with the screen off. Going back to the recipe.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
