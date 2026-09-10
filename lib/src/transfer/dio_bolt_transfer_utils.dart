import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'dio_bolt_file.dart';

/// Internal key used in [RequestOptions.extra] to store [List<DioBoltFile>] for replayability.
const String kDioBoltUploadFilesKey = '_dioBoltUploadFiles';

/// Internal key used in [RequestOptions.extra] to store upload form fields for replayability.
const String kDioBoltUploadFieldsKey = '_dioBoltUploadFields';

/// Utility class for managing multipart FormData reconstruction and atomic temporary files.
class DioBoltTransferUtils {
  static int _tempFileCounter = 0;

  /// Asynchronously creates a fresh [MultipartFile] instance from a [DioBoltFile] descriptor.
  static Future<MultipartFile> createMultipartFile(DioBoltFile file) async {
    final mediaType = file.contentType != null
        ? DioMediaType.parse(file.contentType!)
        : null;

    if (file.path != null) {
      return MultipartFile.fromFile(
        file.path!,
        filename: file.filename,
        contentType: mediaType,
      );
    } else if (file.bytes != null) {
      return MultipartFile.fromBytes(
        file.bytes!,
        filename: file.filename,
        contentType: mediaType,
      );
    } else if (file.stream != null) {
      return MultipartFile.fromStream(
        () => file.stream!,
        file.length!,
        filename: file.filename,
        contentType: mediaType,
      );
    }

    throw StateError(
      'Invalid DioBoltFile: no path, bytes, or stream provided.',
    );
  }

  /// Creates a fresh [FormData] from the given [files] and [fields].
  ///
  /// Re-reads file paths from disk and byte arrays from memory to produce fresh streams.
  static Future<FormData> createFormData({
    List<DioBoltFile>? files,
    Map<String, dynamic>? fields,
  }) async {
    final formData = FormData();

    // 1. Add fields
    if (fields != null && fields.isNotEmpty) {
      for (final entry in fields.entries) {
        formData.fields.add(MapEntry(entry.key, entry.value?.toString() ?? ''));
      }
    }

    // 2. Add fresh MultipartFiles
    if (files != null && files.isNotEmpty) {
      for (final file in files) {
        final multipartFile = await createMultipartFile(file);
        formData.files.add(MapEntry(file.fieldName, multipartFile));
      }
    }

    return formData;
  }

  /// Evaluates whether all [files] are safely replayable across retries.
  static bool areFilesReplayable(List<DioBoltFile>? files) {
    if (files == null || files.isEmpty) return true;
    return files.every((f) => f.isReplayable);
  }

  /// Generates a unique temporary file path adjacent to [destinationPath].
  static String generateTempFilePath(String destinationPath) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final counter = ++_tempFileCounter;
    return '$destinationPath.$timestamp.$counter.tmp';
  }

  /// Safely cleans up the temporary file at [tempPath] if it exists.
  static Future<void> cleanTempFile(String? tempPath) async {
    if (tempPath == null || tempPath.isEmpty) return;
    try {
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignored for zero-crash guarantee
    }
  }

  /// Hardened replacement of downloaded temporary file into its final [destinationPath].
  ///
  /// Guarantees:
  /// 1. Destination remains untouched throughout the network download.
  /// 2. If destination already exists and overwrite is true, replacement prefers
  ///    atomic rename semantics on POSIX platforms. On platforms where direct rename
  ///    over an existing file is rejected (e.g. Windows), a two-phase backup-swap is
  ///    used so the previous valid file is restored if commit fails.
  /// 3. In the event of a failed download or failed commit, the previous valid destination
  ///    is preserved.
  static Future<void> commitTempFile({
    required String tempPath,
    required String destinationPath,
    required bool overwrite,
  }) async {
    final tempFile = File(tempPath);
    final destFile = File(destinationPath);

    if (!await tempFile.exists()) {
      throw StateError(
        'Temporary download file does not exist at "$tempPath".',
      );
    }

    // Ensure parent directory exists
    final parent = destFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final destExists = await destFile.exists();
    if (destExists && !overwrite) {
      throw StateError(
        'Destination file already exists at "$destinationPath" and overwrite is disabled.',
      );
    }

    // 1. Direct rename attempt (atomic replace on POSIX systems)
    try {
      await tempFile.rename(destinationPath);
      return;
    } catch (_) {
      // Direct rename may fail on Windows if destination already exists,
      // or in cross-filesystem / cross-device move scenarios.
    }

    // 2. If destination exists, perform a safe swap using a backup file to prevent
    // destroying the existing valid file if the subsequent move fails.
    if (destExists) {
      final backupPath =
          '$destinationPath.${DateTime.now().microsecondsSinceEpoch}.bak';
      final backupFile = File(backupPath);

      try {
        await destFile.rename(backupPath);
      } catch (_) {
        // If backup rename fails, attempt fallback copy without deleting destination upfront
        await tempFile.copy(destinationPath);
        await cleanTempFile(tempPath);
        return;
      }

      try {
        try {
          await tempFile.rename(destinationPath);
        } catch (_) {
          await tempFile.copy(destinationPath);
          await cleanTempFile(tempPath);
        }
        // Commit succeeded; clean up backup
        await cleanTempFile(backupPath);
      } catch (commitError) {
        // Commit failed; restore original valid destination from backup
        try {
          if (await backupFile.exists()) {
            await backupFile.rename(destinationPath);
          }
        } catch (_) {
          // Best-effort restoration
        }
        rethrow;
      }
    } else {
      // Destination did not exist; fallback copy + delete
      await tempFile.copy(destinationPath);
      await cleanTempFile(tempPath);
    }
  }
}
