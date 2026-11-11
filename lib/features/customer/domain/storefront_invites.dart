// lib/features/customer/domain/storefront_invites.dart
//
// bosapp://store/... invite links.

String storefrontInvitePayload(String businessId, {String? branchId}) =>
    branchId == null
    ? 'bosapp://store/$businessId'
    : 'bosapp://store/$businessId?branch=$branchId';

String? branchIdFromStorefrontInvite(String payload) {
  final id = Uri.tryParse(payload.trim())?.queryParameters['branch'];
  if (id == null ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(id)) {
    return null;
  }
  return id;
}

String? businessIdFromStorefrontInvite(String payload) {
  final uri = Uri.tryParse(payload.trim());
  if (uri == null || uri.scheme != 'bosapp' || uri.host != 'store') return null;
  final businessId = uri.pathSegments.length == 1
      ? uri.pathSegments.single
      : '';
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(businessId)) {
    return null;
  }
  return businessId;
}
