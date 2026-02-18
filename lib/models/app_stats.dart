class AppStats {
  final double cpu;
  final double ram;
  final double temp;
  final double battery;
  final bool isPlugged;

  AppStats({
    required this.cpu,
    required this.ram,
    required this.temp,
    required this.battery,
    required this.isPlugged,
  });

  factory AppStats.fromJson(Map<String, dynamic> json) {
    return AppStats(
      cpu: _toDouble(json['cpu_usage']),
      ram: _toDouble(json['ram_usage']),
      temp: _toDouble(json['cpu_temp']),
      battery: _toDouble(json['battery_percent']),
      isPlugged: _toBool(json['is_plugged']),
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      final parsed = value.toDouble();
      return parsed.isFinite ? parsed : 0.0;
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed.isFinite) {
        return parsed;
      }
    }
    return 0.0;
  }

  static bool _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }
}
