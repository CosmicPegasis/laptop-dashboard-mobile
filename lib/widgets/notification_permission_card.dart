import 'package:flutter/material.dart';

class NotificationPermissionCard extends StatelessWidget {
  final VoidCallback onRequestPermission;

  const NotificationPermissionCard({
    super.key,
    required this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notifications are disabled',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enable notifications to keep live laptop status updates in the notification tray.',
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onRequestPermission,
                child: const Text('Enable notifications'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
