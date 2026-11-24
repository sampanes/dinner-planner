import 'package:flutter/material.dart';

import '../app_model.dart';

/// "A new version is ready": one button fetches it and hands it to Android,
/// which asks before installing. Shown on Tonight and in Settings.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = theme.colorScheme.onSurfaceVariant;
    final progress = model.updateProgress;
    final error = model.updateError;
    return Card.outlined(
      key: const ValueKey('update-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.system_update_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Version ${model.newestVersion ?? ''} is ready', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        progress != null ? 'Fetching it: ${(progress * 100).round()}%' : 'Everything on this phone is kept. Android asks once more before it goes in.',
                        key: const ValueKey('update-said'),
                        style: theme.textTheme.bodySmall?.copyWith(color: faded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(key: const ValueKey('update-go'), onPressed: progress != null ? null : model.update, child: const Text('Update')),
              ],
            ),
            if (progress != null) Padding(padding: const EdgeInsets.only(top: 10), child: LinearProgressIndicator(value: progress)),
            if (error != null && progress == null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(error, key: const ValueKey('update-error'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
          ],
        ),
      ),
    );
  }
}
