import 'package:flutter/material.dart';

class LogCard extends StatelessWidget {
  final List<String> logs;
  final ScrollController scrollController;

  const LogCard({
    super.key,
    required this.logs,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFF1E1E1E),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 250,
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
                      Icon(Icons.terminal, color: Colors.green, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'TERMINAL LOGS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${logs.length} entries',
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
                  controller: scrollController,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        logs[index],
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
