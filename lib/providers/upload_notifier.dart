import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../models/file_info.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class UploadNotifier extends ChangeNotifier {
  final StorageService _storageService;
  StreamSubscription? _intentDataStreamSubscription;
  Timer? _filePollTimer;

  ApiService? _apiService;
  List<({String path, String name})> _pendingSharedFiles = [];

  UploadState _upload = const UploadState();
  List<FileInfo> _availableFiles = [];
  Set<String> _seenFiles = {};
  bool _isDownloading = false;
  final Map<String, double> _fileDownloadProgress = {};
  bool _isActive = false;
  int _pollingIntervalSeconds = 5;

  UploadNotifier({StorageService? storageService})
    : _storageService = storageService ?? StorageService();

  UploadState get upload => _upload;
  List<FileInfo> get availableFiles => _availableFiles;
  Set<String> get seenFiles => _seenFiles;
  bool get isDownloading => _isDownloading;
  Map<String, double> get fileDownloadProgress => _fileDownloadProgress;
  bool get isActive => _isActive;
  List<({String path, String name})> get pendingSharedFiles =>
      _pendingSharedFiles;

  void initialize(String laptopIp) {
    _apiService = ApiService(laptopIp: laptopIp);
    _loadSeenFiles();
    _initSharing();
  }

  void updateApiService(String laptopIp) {
    _apiService = ApiService(laptopIp: laptopIp);
  }

  void setActive(bool active, int pollingIntervalSeconds) {
    _isActive = active;
    _pollingIntervalSeconds = pollingIntervalSeconds;
    if (active) {
      _startFilePolling();
      _refreshFiles();
    } else {
      _stopFilePolling();
    }
    notifyListeners();
  }

  Future<void> _loadSeenFiles() async {
    _seenFiles = await _storageService.getSeenFiles();
    notifyListeners();
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

    _pendingSharedFiles = [..._pendingSharedFiles, ...mapped];
    notifyListeners();
  }

  void clearPendingSharedFiles() {
    _pendingSharedFiles = [];
    notifyListeners();
  }

  Future<void> uploadSharedFiles() async {
    if (_pendingSharedFiles.isEmpty || _apiService == null) return;

    final files = List<({String path, String name})>.from(_pendingSharedFiles);
    _pendingSharedFiles = [];
    notifyListeners();

    for (final file in files) {
      _upload = UploadState(
        isUploading: true,
        fileName: file.name,
        progress: 0.0,
        statusMessage: 'Uploading shared: ${file.name}',
      );
      notifyListeners();

      try {
        await _apiService!.uploadFile(
          filePath: file.path,
          fileName: file.name,
          onProgress: (p) {
            _upload = _upload.copyWith(progress: p);
            notifyListeners();
          },
        );
        _upload = _upload.copyWith(
          isUploading: false,
          progress: 1.0,
          statusMessage: 'Shared upload successful: ${file.name}',
          success: true,
        );
        if (files.length > 1) await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        _upload = _upload.copyWith(
          isUploading: false,
          statusMessage: 'Upload error: $e',
          success: false,
        );
        break;
      }
      notifyListeners();
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
      _availableFiles = await _apiService!.listFiles();
      notifyListeners();
    } catch (e) {
      // Silently fail - will retry on next poll
    }
  }

  Future<void> pickAndUploadFile() async {
    if (_apiService == null) return;

    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final filePath = file.path;
    if (filePath == null) return;

    _upload = UploadState(
      isUploading: true,
      fileName: file.name,
      progress: 0.0,
    );
    notifyListeners();

    try {
      await _apiService!.uploadFile(
        filePath: filePath,
        fileName: file.name,
        onProgress: (p) {
          _upload = _upload.copyWith(progress: p);
          notifyListeners();
        },
      );
      _upload = _upload.copyWith(
        isUploading: false,
        progress: 1.0,
        statusMessage: 'Upload successful!',
        success: true,
      );
    } catch (e) {
      _upload = _upload.copyWith(
        isUploading: false,
        statusMessage: 'Upload error: $e',
        success: false,
      );
    }
    notifyListeners();
  }

  Future<void> downloadFile(FileInfo file) async {
    if (_apiService == null) return;

    _isDownloading = true;
    _fileDownloadProgress[file.name] = 0.0;
    notifyListeners();

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
          _fileDownloadProgress[file.name] = p;
          notifyListeners();
        },
      );

      await _storageService.markFileAsSeen(file.name);
      _seenFiles.add(file.name);
      _fileDownloadProgress[file.name] = 1.0;
    } catch (e) {
      _fileDownloadProgress[file.name] = 0.0;
    } finally {
      _isDownloading = false;
      notifyListeners();
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
