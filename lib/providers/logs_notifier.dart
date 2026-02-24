import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LogsNotifier extends ChangeNotifier {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  static const int _maxLogs = 100;

  List<String> get logs => List.unmodifiable(_logs);
  ScrollController get scrollController => _scrollController;

  void addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    _logs.add('[$timestamp] $message');
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
    notifyListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
