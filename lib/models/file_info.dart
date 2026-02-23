import '../utils/type_coerce.dart';

class FileInfo {
  final String name;
  final int size;
  final double modTime;

  FileInfo({required this.name, required this.size, required this.modTime});

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      name: json['name'] as String? ?? '',
      size: coerceInt(json['size']),
      modTime: coerceDouble(json['mod_time']),
    );
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
