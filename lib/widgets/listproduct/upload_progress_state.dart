enum UploadPhase { uploading, submitting }

class UploadState {
  final UploadPhase phase;
  final int uploadedFiles;
  final int totalFiles;
  final int bytesTransferred;
  final int totalBytes;

  const UploadState({
    required this.phase,
    this.uploadedFiles = 0,
    this.totalFiles = 0,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
  });

  double get fraction {
    switch (phase) {
      case UploadPhase.uploading:
        if (totalBytes == 0) return 0.0;
        return (bytesTransferred / totalBytes).clamp(0.0, 0.95);
      case UploadPhase.submitting:
        return 1.0;
    }
  }

  String get percentLabel => '${(fraction * 100).toStringAsFixed(0)}%';

  bool get isComplete => phase == UploadPhase.submitting;

  UploadState copyWith({
    UploadPhase? phase,
    int? uploadedFiles,
    int? totalFiles,
    int? bytesTransferred,
    int? totalBytes,
  }) {
    return UploadState(
      phase: phase ?? this.phase,
      uploadedFiles: uploadedFiles ?? this.uploadedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
    );
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}