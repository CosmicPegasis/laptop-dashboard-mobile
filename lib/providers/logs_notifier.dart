import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class LogsState {
  final List<String> logs;

  const LogsState({this.logs = const []});

  LogsState copyWith({List<String>? logs}) {
    return LogsState(logs: logs ?? this.logs);
  }
}

class LogsNotifier extends StateNotifier<LogsState> {
  final ScrollController scrollController = ScrollController();
  static const int _maxLogs = 100;

  LogsNotifier() : super(const LogsState());

  void addLog(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    final newLog = '[$timestamp] $message';
    final updatedLogs = List<String>.from(state.logs)..add(newLog);
    if (updatedLogs.length > _maxLogs) {
      updatedLogs.removeAt(0);
    }
    state = state.copyWith(logs: updatedLogs);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}
