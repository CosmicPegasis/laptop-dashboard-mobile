import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants.dart';
import '../providers/riverpod_providers.dart';
import '../widgets/status_card.dart';
import '../widgets/log_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(height: kLargeSpacing),
            const StatusCard(),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: kHorizontalPadding,
                vertical: 10,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: Builder(
                  builder: (context) {
                    final stats = ref.watch(statsProvider);
                    return ElevatedButton.icon(
                      onPressed: stats.isSleeping
                          ? null
                          : () => _showSleepConfirmation(context, ref),
                      icon: stats.isSleeping
                          ? SizedBox(
                              width: kStatusIconSize,
                              height: kStatusIconSize,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.power_settings_new),
                      label: Text(
                        stats.isSleeping ? 'Suspending...' : 'Sleep Laptop',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade100,
                        foregroundColor: Colors.orange.shade900,
                      ),
                    );
                  },
                ),
              ),
            ),
            const LogCard(),
            const SizedBox(height: kLargeSpacing),
          ],
        ),
      ),
    );
  }

  void _showSleepConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sleep Laptop?'),
        content: const Text(
          'Are you sure you want to put your laptop to sleep?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(statsProvider.notifier).sleepLaptop();
              ref.read(logsProvider.notifier).addLog('Laptop going to sleep');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Sleep', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
