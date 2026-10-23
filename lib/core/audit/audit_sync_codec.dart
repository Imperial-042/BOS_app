// lib/core/audit/audit_sync_codec.dart
//
// Local audit rows keep details/before/after as JSON TEXT; the cloud columns
// are jsonb. Without decoding, jsonb would receive a JSON *string* instead of
// an object. (The pull path already re-encodes Map/List via _toLocal.)

import 'dart:convert';

abstract final class AuditSyncCodec {
  static const table = 'audit_logs';
  static const _jsonColumns = {'details', 'before_json', 'after_json'};

  static Map<String, dynamic> toCloud(Map<String, dynamic> row) {
    return {
      for (final e in row.entries)
        e.key: _jsonColumns.contains(e.key) && e.value is String
            ? _decode(e.value as String)
            : e.value,
    };
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text; // legacy non-JSON details survive as a jsonb string
    }
  }
}
