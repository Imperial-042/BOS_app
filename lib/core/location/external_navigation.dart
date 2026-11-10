import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'location_models.dart';

Future<void> openExternalNavigation({
  required GeoCoordinate coordinate,
  String? label,
}) async {
  final query = Uri.encodeComponent(
    label == null || label.trim().isEmpty
        ? '${coordinate.latitude},${coordinate.longitude}'
        : '${label.trim()}@${coordinate.latitude},${coordinate.longitude}',
  );
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$query',
  );
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      !kIsWeb &&
      !await launchUrl(uri, mode: LaunchMode.platformDefault)) {
    throw StateError('No supported navigation application is available.');
  }
}
