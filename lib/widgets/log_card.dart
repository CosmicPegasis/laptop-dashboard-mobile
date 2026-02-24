import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/logs_notifier.dart';

class LogCard extends StatelessWidget {
  const LogCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LogsNotifier>(
      builder: (context, logsNotifier, _) {
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                        '${logsNotifier.logs.length} entries',
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
                      controller: logsNotifier.scrollController,
                      itemCount: logsNotifier.logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            logsNotifier.logs[index],
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
      },
    );
  }
}
