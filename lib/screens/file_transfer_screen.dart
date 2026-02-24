import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants.dart';
import '../providers/upload_notifier.dart';
import '../providers/riverpod_providers.dart';

class FileTransferScreen extends ConsumerStatefulWidget {
  const FileTransferScreen({super.key});

  @override
  ConsumerState<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends ConsumerState<FileTransferScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = ref.read(settingsProvider);
    ref
        .read(uploadProvider.notifier)
        .setActive(settings.drawerIndex == 1, settings.pollingIntervalSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final upload = ref.watch(uploadProvider);
    final settings = ref.watch(settingsProvider);
    if (upload.pendingSharedFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(uploadProvider.notifier).uploadSharedFiles();
      });
    }

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: kHorizontalPadding,
          vertical: kLargeSpacing,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUploadSection(ref, upload, settings.laptopIp),
            const Divider(height: 40, thickness: 1),
            _buildDownloadSection(ref, upload),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadSection(
    WidgetRef ref,
    UploadNotifierState upload,
    String laptopIp,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Send File to Laptop',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: kSmallSpacing),
        Text(
          'Uploads to ~/Downloads/phone_transfers/ on $laptopIp',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: kButtonHeight,
          child: ElevatedButton.icon(
            onPressed: upload.upload.isUploading
                ? null
                : () => ref.read(uploadProvider.notifier).pickAndUploadFile(),
            icon: upload.upload.isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: Text(
              upload.upload.isUploading ? 'Uploading...' : 'Pick & Upload File',
            ),
          ),
        ),
        if (upload.upload.fileName != null) ...[
          const SizedBox(height: kVerticalPadding),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.insert_drive_file, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  upload.upload.fileName!,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
        if (upload.upload.progress > 0 && upload.upload.progress < 1) ...[
          const SizedBox(height: kVerticalPadding),
          LinearProgressIndicator(
            value: upload.upload.progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text(
            '${(upload.upload.progress * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        if (upload.upload.statusMessage != null) ...[
          const SizedBox(height: kVerticalPadding),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                upload.upload.success ? Icons.check_circle : Icons.error,
                color: upload.upload.success ? Colors.green : Colors.red,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  upload.upload.statusMessage!,
                  style: TextStyle(
                    color: upload.upload.success
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

  Widget _buildDownloadSection(WidgetRef ref, UploadNotifierState upload) {
    final newFiles = upload.availableFiles
        .where((f) => !upload.seenFiles.contains(f.name))
        .toList();

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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
        const SizedBox(height: kSmallSpacing),
        Text(
          'Files in ~/Downloads/phone_share/ on laptop',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: kVerticalPadding),
        if (upload.availableFiles.isEmpty)
          _buildEmptyState()
        else
          _buildFileList(context, upload),
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

  Widget _buildFileList(BuildContext context, UploadNotifierState upload) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: upload.availableFiles.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final file = upload.availableFiles[index];
        final isNew = !upload.seenFiles.contains(file.name);
        final progress = upload.fileDownloadProgress[file.name] ?? 0.0;
        final isFileDownloading =
            upload.isDownloading && progress > 0 && progress < 1;

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
                  const SizedBox(height: kMediumSpacing),
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
                  const SizedBox(height: kSmallSpacing),
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
                const SizedBox(height: kMediumSpacing),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isFileDownloading
                        ? null
                        : () => ref
                              .read(uploadProvider.notifier)
                              .downloadFile(file),
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
