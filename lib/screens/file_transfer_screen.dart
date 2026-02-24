import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/file_info.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';

// ---------------------------------------------------------------------------
// Value object bundling all upload-related state.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// FileTransferScreen
// ---------------------------------------------------------------------------
class FileTransferScreen extends StatefulWidget {
  final String laptopIp;
  final ApiService apiService;
  final StorageService storageService;
  final NotificationService notificationService;
  final List<({String path, String name})>? pendingSharedFiles;
  final VoidCallback? onPendingHandled;
  final bool isActive;
  final int filePollingIntervalSeconds;

  const FileTransferScreen({
    super.key,
    required this.laptopIp,
    required this.apiService,
    required this.storageService,
    required this.notificationService,
    this.pendingSharedFiles,
    this.onPendingHandled,
    this.isActive = false,
    this.filePollingIntervalSeconds = 5,
  });

  @override
  State<FileTransferScreen> createState() => FileTransferScreenState();
}

class FileTransferScreenState extends State<FileTransferScreen> with TickerProviderStateMixin {
  // Upload
  UploadState _upload = const UploadState();

  // Download
  List<FileInfo> _availableFiles = [];
  Set<String> _seenFiles = {};
  bool _isDownloading = false;
  final Map<String, double> _fileDownloadProgress = {};

  Timer? _filePollTimer;

  @override
  void initState() {
    super.initState();
    _loadSeenFiles();
    if (widget.isActive) _startFilePolling();
  }

  @override
  void didUpdateWidget(FileTransferScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle pending shared files
    if (widget.pendingSharedFiles != oldWidget.pendingSharedFiles &&
        widget.pendingSharedFiles?.isNotEmpty == true) {
      _uploadSharedFiles(widget.pendingSharedFiles!);
      widget.onPendingHandled?.call();
    }

    // Handle isActive change
    if (widget.isActive && !oldWidget.isActive) {
      _startFilePolling();
      _refreshFiles();
    } else if (!widget.isActive && oldWidget.isActive) {
      _stopFilePolling();
    }
  }

  Future<void> _loadSeenFiles() async {
    final seen = await widget.storageService.getSeenFiles();
    if (mounted) setState(() => _seenFiles = seen);
  }


  Future<void> pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final filePath = file.path;
    if (filePath == null) return;

    setState(() {
      _upload = UploadState(
        isUploading: true,
        fileName: file.name,
        progress: 0.0,
      );
    });

    try {
      await widget.apiService.uploadFile(
        filePath: filePath,
        fileName: file.name,
        onProgress: (p) => setState(() => _upload = _upload.copyWith(progress: p)),
      );
      setState(() {
        _upload = _upload.copyWith(
          isUploading: false,
          progress: 1.0,
          statusMessage: 'Upload successful!',
          success: true,
        );
      });
    } catch (e) {
      setState(() {
        _upload = _upload.copyWith(
          isUploading: false,
          statusMessage: 'Upload error: $e',
          success: false,
        );
      });
    }
  }

  Future<void> uploadSharedFiles(List<({String path, String name})> files) async {
    for (final file in files) {
      setState(() {
        _upload = UploadState(
          isUploading: true,
          fileName: file.name,
          progress: 0.0,
          statusMessage: 'Uploading shared: ${file.name}',
        );
      });

      try {
        await widget.apiService.uploadFile(
          filePath: file.path,
          fileName: file.name,
          onProgress: (p) => setState(() => _upload = _upload.copyWith(progress: p)),
        );
        setState(() {
          _upload = _upload.copyWith(
            isUploading: false,
            progress: 1.0,
            statusMessage: 'Shared upload successful: ${file.name}',
            success: true,
          );
        });
        if (files.length > 1) await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        setState(() {
          _upload = _upload.copyWith(
            isUploading: false,
            statusMessage: 'Upload error: $e',
            success: false,
          );
        });
        break;
      }
    }
  }

  Future<void> _downloadFile(FileInfo file) async {
    setState(() {
      _isDownloading = true;
      _fileDownloadProgress[file.name] = 0.0;
    });

    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not access Downloads folder');
      }

      final savePath = '${downloadsDir.path}/${file.name}';
      await widget.apiService.downloadFile(
        filename: file.name,
        savePath: savePath,
        onProgress: (p) =>
            setState(() => _fileDownloadProgress[file.name] = p),
      );

      await widget.storageService.markFileAsSeen(file.name);
      setState(() {
        _seenFiles.add(file.name);
        _fileDownloadProgress[file.name] = 1.0;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUploadSection(context),
            const Divider(height: 40, thickness: 1),
            _buildDownloadSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Send File to Laptop',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Uploads to ~/Downloads/phone_transfers/ on ${widget.laptopIp}',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _upload.isUploading ? null : pickAndUploadFile,
            icon: _upload.isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label:
                Text(_upload.isUploading ? 'Uploading...' : 'Pick & Upload File'),
          ),
        ),
        if (_upload.fileName != null) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.insert_drive_file, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _upload.fileName!,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
        if (_upload.progress > 0 && _upload.progress < 1) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _upload.progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text(
            '${(_upload.progress * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        if (_upload.statusMessage != null) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _upload.success ? Icons.check_circle : Icons.error,
                color: _upload.success ? Colors.green : Colors.red,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _upload.statusMessage!,
                  style: TextStyle(
                    color: _upload.success
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDownloadSection(BuildContext context) {
    final newFiles =
        _availableFiles.where((f) => !_seenFiles.contains(f.name)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Available from Laptop',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            if (newFiles.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${newFiles.length} new',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Files in ~/Downloads/phone_share/ on laptop',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (_availableFiles.isEmpty)
          _buildEmptyState()
        else
          _buildFileList(context),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.folder_open, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            'No files available',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          SizedBox(height: 4),
          Text(
            'Add files to ~/Downloads/phone_share/ on your laptop',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _availableFiles.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final file = _availableFiles[index];
        final isNew = !_seenFiles.contains(file.name);
        final progress = _fileDownloadProgress[file.name] ?? 0.0;
        final isFileDownloading = _isDownloading && progress > 0 && progress < 1;

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getFileIcon(file.name),
                      color: isNew ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  file.name,
                                  style: TextStyle(
                                    fontWeight: isNew
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isNew)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${file.sizeReadable} • ${_formatDate(file.modificationDate)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (isFileDownloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Downloading: ${(progress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else if (progress == 1.0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Downloaded',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        isFileDownloading ? null : () => _downloadFile(file),
                    icon: Icon(
                      progress == 1.0 ? Icons.refresh : Icons.download,
                      size: 18,
                    ),
                    label: Text(
                      progress == 1.0 ? 'Download Again' : 'Download',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
        return Icons.audio_file;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) return '${diff.inMinutes} min ago';
      return '${diff.inHours} hr ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}
