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
    final colorScheme = Theme.of(context).colorScheme;
    final isConnected = cpu > 0 || ram > 0 || battery > 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.laptop_mac, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Laptop Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                _ConnectionIndicator(isConnected: isConnected),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _GaugeWidget(
                  label: 'CPU',
                  value: cpu,
                  color: _getColorForValue(cpu),
                ),
                _GaugeWidget(
                  label: 'RAM',
                  value: ram,
                  color: _getColorForValue(ram),
                ),
                _BatteryGauge(value: battery, isPlugged: isPlugged),
              ],
            ),
            const SizedBox(height: 20),
            _TemperatureWidget(temp: temp, color: _getTempColor(temp)),
          ],
        ),
      ),
    );
  }

  Color _getColorForValue(double value) {
    if (value < 50) return Colors.green;
    if (value < 80) return Colors.orange;
    return Colors.red;
  }

  Color _getTempColor(double temp) {
    if (temp < 60) return Colors.green;
    if (temp < 80) return Colors.orange;
    return Colors.red;
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final bool isConnected;

  const _ConnectionIndicator({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade100 : Colors.red.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isConnected ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugeWidget extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _GaugeWidget({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: value / 100,
                strokeWidth: 8,
                backgroundColor: color.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(color),
              ),
              Center(
                child: Text(
                  '${value.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BatteryGauge extends StatelessWidget {
  final double value;
  final bool isPlugged;

  const _BatteryGauge({required this.value, required this.isPlugged});

  @override
  Widget build(BuildContext context) {
    final color = _getBatteryColor(value);
    return Column(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: value / 100,
                strokeWidth: 8,
                backgroundColor: color.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(color),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPlugged
                          ? Icons.battery_charging_full
                          : _getBatteryIcon(value),
                      size: 20,
                      color: color,
                    ),
                    Text(
                      '${value.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isPlugged ? 'Charging' : 'Battery',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Color _getBatteryColor(double value) {
    if (value > 50) return Colors.green;
    if (value > 20) return Colors.orange;
    return Colors.red;
  }

  IconData _getBatteryIcon(double value) {
    if (value > 75) return Icons.battery_full;
    if (value > 50) return Icons.battery_5_bar;
    if (value > 25) return Icons.battery_3_bar;
    if (value > 10) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }
}

class _TemperatureWidget extends StatelessWidget {
  final double temp;
  final Color color;

  const _TemperatureWidget({required this.temp, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.thermostat, color: color, size: 24),
          const SizedBox(width: 8),
          Text(
            'Temperature',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '${temp.toStringAsFixed(1)}°C',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
