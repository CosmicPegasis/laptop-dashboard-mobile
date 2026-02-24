import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants.dart';
import '../providers/riverpod_providers.dart';

class LogCard extends ConsumerWidget {
  const LogCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(logsProvider);
    final notifier = ref.read(logsProvider.notifier);
    return Card(
      elevation: 8,
      margin: const EdgeInsets.symmetric(
        horizontal: kHorizontalPadding,
        vertical: 10,
      ),
      color: kTerminalBg,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: kLogCardHeight,
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.terminal,
                        color: Colors.green,
                        size: kFontSizeSmall,
                      ),
                      SizedBox(width: kSmallSpacing),
                      Text(
                        'TERMINAL LOGS',
                        style: TextStyle(
                          fontSize: kFontSizeSmall,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${state.logs.length} entries',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.green,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                child: ListView.builder(
                  controller: notifier.scrollController,
                  itemCount: state.logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        state.logs[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFFD4D4D4),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
