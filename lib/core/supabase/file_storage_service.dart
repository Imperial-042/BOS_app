// lib/core/supabase/file_storage_service.dart
//
// Cloud file abstraction. Business entities hold a stable reference (bucket
// + path), never a raw local path or a Storage-API call. Upload/delete go
// through this service so the same call sites work whether files live on
// device now or in Supabase Storage later.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class CloudStorageException implements Exception {
  final String code;
  final String message;
  const CloudStorageException(this.code, this.message);

  @override
  String toString() => message;
}

class StoredFile {
  final String bucket;
  final String path;
  const StoredFile({required this.bucket, required this.path});

  /// The stable reference persisted on a business entity (e.g. logo_path).
  String get reference => '$bucket:$path';
}

abstract final class StorageBuckets {
  static const businessAssets = 'business-assets';
  static const receipts = 'receipts';
}

class FileStorageService {
  final SupabaseClient _client;
  FileStorageService(this._client);

  /// Business-scoped object path. The leading businesses/{id}/ segment is
  /// what Storage RLS uses to authorize the object.
  String businessPath(String businessId, String category, String filename) =>
      'businesses/$businessId/$category/$filename';

  Future<StoredFile> upload({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
  }) async {
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return StoredFile(bucket: bucket, path: path);
    } on StorageException catch (error) {
      throw CloudStorageException('storage_error', error.message);
    }
  }

  Future<List<int>> download(StoredFile file) async {
    try {
      final bytes = await _client.storage.from(file.bucket).download(file.path);
      return bytes;
    } on StorageException catch (error) {
      throw CloudStorageException('storage_error', error.message);
    }
  }

  Future<void> delete(StoredFile file) async {
    try {
      await _client.storage.from(file.bucket).remove([file.path]);
    } on StorageException catch (error) {
      throw CloudStorageException('storage_error', error.message);
    }
  }
}

final fileStorageServiceProvider = Provider<FileStorageService>((ref) {
  return FileStorageService(ref.watch(supabaseClientProvider));
});
