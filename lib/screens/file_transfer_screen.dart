import 'package:flutter/material.dart';

class FileTransferScreen extends StatelessWidget {
  final String laptopIp;
  final bool isUploading;
  final double uploadProgress;
  final String? uploadStatusMessage;
  final String? pickedFileName;
  final bool uploadSuccess;
  final VoidCallback onPickAndUploadFile;

  const FileTransferScreen({
    super.key,
    required this.laptopIp,
    required this.isUploading,
    required this.uploadProgress,
    this.uploadStatusMessage,
    this.pickedFileName,
    required this.uploadSuccess,
    required this.onPickAndUploadFile,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Send File to Laptop',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Uploads to ~/Downloads/phone_transfers/ on $laptopIp.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: isUploading ? null : onPickAndUploadFile,
                icon: isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(isUploading ? 'Uploading...' : 'Pick & Upload File'),
              ),
            ),
            if (pickedFileName != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.insert_drive_file, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pickedFileName!,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (isUploading || (uploadProgress > 0 && uploadProgress < 1)) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: isUploading ? uploadProgress : null,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Text(
                '${(uploadProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.end,
              ),
            ],
            if (uploadStatusMessage != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    uploadSuccess ? Icons.check_circle : Icons.error,
                    color: uploadSuccess ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      uploadStatusMessage!,
                      style: TextStyle(
                        color: uploadSuccess ? Colors.green.shade700 : Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
