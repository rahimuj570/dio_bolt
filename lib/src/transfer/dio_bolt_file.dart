import 'dart:async';

/// Descriptor for file payloads used in multipart uploads.
///
/// Supports path-backed, byte-backed, and stream-backed file sources without
/// exposing `dart:io File` in the public contract.
class DioBoltFile {
  /// File path on disk (if path-backed).
  final String? path;

  /// In-memory byte array (if byte-backed).
  final List<int>? bytes;

  /// Stream of bytes (if stream-backed).
  final Stream<List<int>>? stream;

  /// Byte length (required for stream-backed files).
  final int? length;

  /// Multipart form field name (e.g. `'avatar'`, `'files[]'`).
  final String fieldName;

  /// Target file name (e.g. `'avatar.png'`).
  final String? filename;

  /// Content type of the file (e.g. `'image/png'`).
  final String? contentType;

  /// Constructs a file descriptor from a local file path.
  ///
  /// Re-readable from disk on retries.
  DioBoltFile.fromPath(
    this.path, {
    required this.fieldName,
    this.filename,
    this.contentType,
  }) : bytes = null,
       stream = null,
       length = null;

  /// Constructs a file descriptor from an in-memory byte buffer.
  ///
  /// Re-readable from memory buffer on retries.
  DioBoltFile.fromBytes(
    this.bytes, {
    required this.fieldName,
    required this.filename,
    this.contentType,
  }) : path = null,
       stream = null,
       length = bytes?.length;

  /// Constructs a file descriptor from a one-shot Stream.
  ///
  /// Strictly non-replayable across request retries.
  DioBoltFile.fromStream(
    this.stream, {
    required this.fieldName,
    required this.length,
    required this.filename,
    this.contentType,
  }) : path = null,
       bytes = null;

  /// Whether this file descriptor can be safely re-read on request retries.
  bool get isReplayable => stream == null && (path != null || bytes != null);
}
