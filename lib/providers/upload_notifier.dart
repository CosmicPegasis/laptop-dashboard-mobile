import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../models/file_info.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class UploadNotifierState {
  final UploadState upload;
  final List<FileInfo> availableFiles;
  final Set<String> seenFiles;
  final bool isDownloading;
  final Map<String, double> fileDownloadProgress;
  final bool isActive;
  final List<({String path, String name})> pendingSharedFiles;

  const UploadNotifierState({
    this.upload = const UploadState(),
    this.availableFiles = const [],
    this.seenFiles = const {},
    this.isDownloading = false,
    this.fileDownloadProgress = const {},
    this.isActive = false,
    this.pendingSharedFiles = const [],
  });

  UploadNotifierState copyWith({
    UploadState? upload,
    List<FileInfo>? availableFiles,
    Set<String>? seenFiles,
    bool? isDownloading,
    Map<String, double>? fileDownloadProgress,
    bool? isActive,
    List<({String path, String name})>? pendingSharedFiles,
  }) {
    return UploadNotifierState(
      upload: upload ?? this.upload,
      availableFiles: availableFiles ?? this.availableFiles,
      seenFiles: seenFiles ?? this.seenFiles,
      isDownloading: isDownloading ?? this.isDownloading,
      fileDownloadProgress: fileDownloadProgress ?? this.fileDownloadProgress,
      isActive: isActive ?? this.isActive,
      pendingSharedFiles: pendingSharedFiles ?? this.pendingSharedFiles,
    );
  }
}

class UploadNotifier extends StateNotifier<UploadNotifierState> {
  final StorageService _storageService;
  StreamSubscription? _intentDataStreamSubscription;
  Timer? _filePollTimer;

  ApiService? _apiService;
  int _pollingIntervalSeconds = 5;

  UploadNotifier({StorageService? storageService})
    : _storageService = storageService ?? StorageService(),
      super(const UploadNotifierState());

  UploadState get upload => state.upload;
  List<FileInfo> get availableFiles => state.availableFiles;
  Set<String> get seenFiles => state.seenFiles;
  bool get isDownloading => state.isDownloading;
  Map<String, double> get fileDownloadProgress => state.fileDownloadProgress;
  bool get isActive => state.isActive;
  List<({String path, String name})> get pendingSharedFiles =>
      state.pendingSharedFiles;

  void initialize(String laptopIp) {
    _apiService = ApiService(laptopIp: laptopIp);
    _loadSeenFiles();
    _initSharing();
  }

  void updateApiService(String laptopIp) {
    _apiService = ApiService(laptopIp: laptopIp);
  }

  void setActive(bool active, int pollingIntervalSeconds) {
    _pollingIntervalSeconds = pollingIntervalSeconds;
    if (active) {
      _startFilePolling();
      _refreshFiles();
    } else {
      _stopFilePolling();
    }
    state = state.copyWith(isActive: active);
  }

  Future<void> _loadSeenFiles() async {
    final seen = await _storageService.getSeenFiles();
    state = state.copyWith(seenFiles: seen);
  }

  void _initSharing() {
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((List<SharedMediaFile> value) {
          if (value.isNotEmpty) _handleSharedFiles(value);
        }, onError: (err) {});

    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) _handleSharedFiles(value);
    });
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    final mapped = files
        .map((f) => (path: f.path, name: f.path.split('/').last))
        .toList();

    final newPending = [...state.pendingSharedFiles, ...mapped];
    state = state.copyWith(pendingSharedFiles: newPending);
  }

  void clearPendingSharedFiles() {
    state = state.copyWith(pendingSharedFiles: const []);
  }

  Future<void> uploadSharedFiles() async {
    if (state.pendingSharedFiles.isEmpty || _apiService == null) return;

    final files = List<({String path, String name})>.from(
      state.pendingSharedFiles,
    );
    state = state.copyWith(pendingSharedFiles: const []);

    for (final file in files) {
      var currentUpload = UploadState(
        isUploading: true,
        fileName: file.name,
        progress: 0.0,
        statusMessage: 'Uploading shared: ${file.name}',
      );
      state = state.copyWith(upload: currentUpload);

      try {
        await _apiService!.uploadFile(
          filePath: file.path,
          fileName: file.name,
          onProgress: (p) {
            currentUpload = currentUpload.copyWith(progress: p);
            state = state.copyWith(upload: currentUpload);
          },
        );
        currentUpload = currentUpload.copyWith(
          isUploading: false,
          progress: 1.0,
          statusMessage: 'Shared upload successful: ${file.name}',
          success: true,
        );
      } catch (e) {
        currentUpload = currentUpload.copyWith(
          isUploading: false,
          statusMessage: 'Upload error: $e',
          success: false,
        );
        break;
      }
      state = state.copyWith(upload: currentUpload);
      if (files.length > 1) await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _startFilePolling() {
    _filePollTimer?.cancel();
    _filePollTimer = Timer.periodic(
      Duration(seconds: _pollingIntervalSeconds),
      (_) => _refreshFiles(),
    );
  }

  void _stopFilePolling() {
    _filePollTimer?.cancel();
    _filePollTimer = null;
  }

  Future<void> _refreshFiles() async {
    if (_apiService == null) return;
    try {
      final files = await _apiService!.listFiles();
      state = state.copyWith(availableFiles: files);
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> pickAndUploadFile() async {
    if (_apiService == null) return;

    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final filePath = file.path;
    if (filePath == null) return;

    var currentUpload = UploadState(
      isUploading: true,
      fileName: file.name,
      progress: 0.0,
    );
    state = state.copyWith(upload: currentUpload);

    try {
      await _apiService!.uploadFile(
        filePath: filePath,
        fileName: file.name,
        onProgress: (p) {
          currentUpload = currentUpload.copyWith(progress: p);
          state = state.copyWith(upload: currentUpload);
        },
      );
      currentUpload = currentUpload.copyWith(
        isUploading: false,
        progress: 1.0,
        statusMessage: 'Upload successful!',
        success: true,
      );
    } catch (e) {
      currentUpload = currentUpload.copyWith(
        isUploading: false,
        statusMessage: 'Upload error: $e',
        success: false,
      );
    }
    state = state.copyWith(upload: currentUpload);
  }

  Future<void> downloadFile(FileInfo file) async {
    if (_apiService == null) return;

    state = state.copyWith(isDownloading: true);
    state = state.copyWith(
      fileDownloadProgress: {...state.fileDownloadProgress, file.name: 0.0},
    );

    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not access Downloads folder');
      }

      final savePath = '${downloadsDir.path}/${file.name}';
      await _apiService!.downloadFile(
        filename: file.name,
        savePath: savePath,
        onProgress: (p) {
          final newProgress = Map<String, double>.from(
            state.fileDownloadProgress,
          );
          newProgress[file.name] = p;
          state = state.copyWith(fileDownloadProgress: newProgress);
        },
      );

      await _storageService.markFileAsSeen(file.name);
      final newSeen = Set<String>.from(state.seenFiles)..add(file.name);
      state = state.copyWith(seenFiles: newSeen);
      final newProgress = Map<String, double>.from(state.fileDownloadProgress);
      newProgress[file.name] = 1.0;
      state = state.copyWith(fileDownloadProgress: newProgress);
    } catch (e) {
      final newProgress = Map<String, double>.from(state.fileDownloadProgress);
      newProgress[file.name] = 0.0;
      state = state.copyWith(fileDownloadProgress: newProgress);
    } finally {
      state = state.copyWith(isDownloading: false);
    }
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    _filePollTimer?.cancel();
    super.dispose();
  }
}

class UploadState {
  final bool isUploading;
  final double progress;
  final String? statusMessage;
  final String? fileName;
  final bool success;

  const UploadState({
    this.isUploading = false,
    this.progress = 0.0,
    this.statusMessage,
    this.fileName,
    this.success = false,
  });

  UploadState copyWith({
    bool? isUploading,
    double? progress,
    String? statusMessage,
    String? fileName,
    bool? success,
  }) {
    return UploadState(
      isUploading: isUploading ?? this.isUploading,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      fileName: fileName ?? this.fileName,
      success: success ?? this.success,
    );
  }
}
