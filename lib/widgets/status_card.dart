import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants.dart';
import '../providers/riverpod_providers.dart';

class StatusCard extends ConsumerWidget {
  const StatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final String plugStatus = stats.isPlugged ? ' (Charging)' : '';
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(
        horizontal: kHorizontalPadding,
        vertical: 10,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Laptop Status',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: kVerticalPadding),
            _StatusRow(label: 'CPU', value: '${stats.cpu.toStringAsFixed(1)}%'),
            const SizedBox(height: kSmallSpacing),
            _StatusRow(label: 'RAM', value: '${stats.ram.toStringAsFixed(1)}%'),
            const SizedBox(height: kSmallSpacing),
            _StatusRow(
              label: 'Temp',
              value: '${stats.temp.toStringAsFixed(1)}°C',
            ),
            const SizedBox(height: kSmallSpacing),
            _StatusRow(
              label: 'Battery',
              value: '${stats.battery.toStringAsFixed(0)}%$plugStatus',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
