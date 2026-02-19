class FileInfo {
  final String name;
  final int size;
  final double modTime;

  FileInfo({required this.name, required this.size, required this.modTime});

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      name: json['name'] as String? ?? '',
      size: _toInt(json['size']),
      modTime: _toDouble(json['mod_time']),
    );
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static double _toDouble(Object? value) {
    if (value is double) {
      final parsed = value;
      return parsed.isFinite ? parsed : 0.0;
    }
    if (value is int) {
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

  String get sizeReadable {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  DateTime get modificationDate =>
      DateTime.fromMillisecondsSinceEpoch((modTime * 1000).toInt());

  @override
  String toString() => 'FileInfo(name: $name, size: $sizeReadable)';
}
