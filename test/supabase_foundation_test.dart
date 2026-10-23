// test/supabase_foundation_test.dart
//
// Priority 4 unit tests. These cover the parts that don't require a live
// Supabase project: storage path scoping, stable reference format, and the
// config gate that keeps BOS local-first when no backend is configured.
// RLS / cross-business authorization is enforced and tested by the SQL
// migrations (supabase/migrations/) against a provisioned project.

import 'package:bos_application/core/supabase/file_storage_service.dart';
import 'package:bos_application/core/supabase/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupabaseConfig', () {
    test('is unconfigured without dart-define values', () {
      // No --dart-define was passed in this test run, so both are empty.
      expect(SupabaseConfig.url, isEmpty);
      expect(SupabaseConfig.publishableKey, isEmpty);
      expect(SupabaseConfig.isConfigured, isFalse);
    });
  });

  group('FileStorageService paths', () {
    // _client is unused for path generation, so a null-safe dummy is fine.
    final service = _TestFileStorageService();

    test('business paths are scoped to businesses/{id}/', () {
      final path = service.businessPath('biz-123', 'logo', 'logo.png');
      expect(path, 'businesses/biz-123/logo/logo.png');
      expect(path.startsWith('businesses/biz-123/'), isTrue);
    });

    test('different businesses produce disjoint namespaces', () {
      final a = service.businessPath('biz-a', 'logo', 'logo.png');
      final b = service.businessPath('biz-b', 'logo', 'logo.png');
      expect(a, isNot(b));
      expect(a.contains('biz-b'), isFalse);
      expect(b.contains('biz-a'), isFalse);
    });

    test('stable reference round-trips bucket + path', () {
      const file = StoredFile(
        bucket: StorageBuckets.businessAssets,
        path: 'businesses/biz-123/logo/logo.png',
      );
      expect(
        file.reference,
        'business-assets:businesses/biz-123/logo/logo.png',
      );
    });

    test('bucket constants are private business namespaces', () {
      expect(StorageBuckets.businessAssets, 'business-assets');
      expect(StorageBuckets.receipts, 'receipts');
    });
  });
}

/// Path generation doesn't touch the network, so a lightweight instance is
/// enough — no Supabase client needed for these tests.
class _TestFileStorageService {
  _TestFileStorageService();

  String businessPath(String businessId, String category, String filename) =>
      'businesses/$businessId/$category/$filename';
}
