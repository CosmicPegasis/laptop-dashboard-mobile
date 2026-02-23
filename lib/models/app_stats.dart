import '../utils/type_coerce.dart';

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
      cpu: coerceDouble(json['cpu_usage']),
      ram: coerceDouble(json['ram_usage']),
      temp: coerceDouble(json['cpu_temp']),
      battery: coerceDouble(json['battery_percent']),
      isPlugged: coerceBool(json['is_plugged']),
    );
  }
}
