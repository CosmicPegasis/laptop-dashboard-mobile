import 'package:flutter/material.dart';

class StatusCard extends StatelessWidget {
  final double cpu;
  final double ram;
  final double temp;
  final double battery;
  final bool isPlugged;

  const StatusCard({
    super.key,
    required this.cpu,
    required this.ram,
    required this.temp,
    required this.battery,
    required this.isPlugged,
  });

  @override
  Widget build(BuildContext context) {
    final String plugStatus = isPlugged ? ' (Charging)' : '';
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Laptop Status',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _StatusRow(label: 'CPU', value: '${cpu.toStringAsFixed(1)}%'),
            const SizedBox(height: 8),
            _StatusRow(label: 'RAM', value: '${ram.toStringAsFixed(1)}%'),
            const SizedBox(height: 8),
            _StatusRow(label: 'Temp', value: '${temp.toStringAsFixed(1)}°C'),
            const SizedBox(height: 8),
            _StatusRow(
              label: 'Battery',
              value: '${battery.toStringAsFixed(0)}%$plugStatus',
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
