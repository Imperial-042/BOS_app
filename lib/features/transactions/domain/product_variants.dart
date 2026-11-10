import 'dart:convert';

import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ProductOptionGroup {
  const ProductOptionGroup({
    required this.id,
    required this.productId,
    required this.businessId,
    required this.name,
    required this.required,
    required this.multiple,
    required this.minSelections,
    required this.maxSelections,
    required this.isAddOn,
    required this.sortOrder,
    required this.choices,
    this.isActive = true,
  });

  final String id;
  final String productId;
  final String businessId;
  final String name;
  final bool required;
  final bool multiple;
  final int minSelections;
  final int? maxSelections;
  final bool isAddOn;
  final int sortOrder;
  final List<ProductOptionChoice> choices;
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'groupId': id,
    'group': name,
    'required': required,
    'choices': choices.map((choice) => choice.toJson()).toList(),
  };
}

class ProductOptionChoice {
  const ProductOptionChoice({
    required this.id,
    required this.groupId,
    required this.name,
    required this.priceDeltaCents,
    required this.inventoryProductId,
    required this.inventoryQuantity,
    required this.sortOrder,
    this.inventorySupplyId,
    this.isActive = true,
  });

  final String id;
  final String groupId;
  final String name;
  final int priceDeltaCents;
  final String? inventoryProductId;
  final double inventoryQuantity;
  final int sortOrder;
  final String? inventorySupplyId;
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'choiceId': id,
    'name': name,
    'priceDeltaCents': priceDeltaCents,
    'inventoryProductId': inventoryProductId,
    'inventorySupplyId': inventorySupplyId,
    'inventoryQuantity': inventoryQuantity,
  };
}

class ProductOptionSelection {
  const ProductOptionSelection({
    required this.groupId,
    required this.choiceId,
    required this.groupName,
    required this.choiceName,
    required this.priceDeltaCents,
    required this.inventoryProductId,
    required this.inventorySupplyId,
    required this.inventoryQuantity,
  });

  final String groupId;
  final String choiceId;
  final String groupName;
  final String choiceName;
  final int priceDeltaCents;
  final String? inventoryProductId;
  final String? inventorySupplyId;
  final double inventoryQuantity;

  Map<String, dynamic> toJson() => {
    'groupId': groupId,
    'choiceId': choiceId,
    'groupName': groupName,
    'choiceName': choiceName,
    'priceDeltaCents': priceDeltaCents,
    'inventoryProductId': inventoryProductId,
    'inventorySupplyId': inventorySupplyId,
    'inventoryQuantity': inventoryQuantity,
  };

  static ProductOptionSelection fromJson(Map<String, dynamic> json) =>
      ProductOptionSelection(
        groupId: json['groupId'] as String,
        choiceId: json['choiceId'] as String,
        groupName: json['groupName'] as String,
        choiceName: json['choiceName'] as String,
        priceDeltaCents: (json['priceDeltaCents'] as num).toInt(),
        inventoryProductId: json['inventoryProductId'] as String?,
        inventorySupplyId: json['inventorySupplyId'] as String?,
        inventoryQuantity: (json['inventoryQuantity'] as num?)?.toDouble() ?? 0,
      );
}

String encodeProductOptionSelections(List<ProductOptionSelection> selections) =>
    jsonEncode(selections.map((selection) => selection.toJson()).toList());

List<ProductOptionSelection> decodeProductOptionSelections(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  final decoded = jsonDecode(value);
  if (decoded is! List) return const [];
  return [
    for (final item in decoded)
      if (item is Map<String, dynamic>) ProductOptionSelection.fromJson(item),
  ];
}

class ProductVariantService {
  ProductVariantService(this.db, {this.client});

  final AppDatabase db;
  final SupabaseClient? client;
  static const _uuid = Uuid();

  Future<List<ProductOptionGroup>> loadGroups(
    String productId, {
    bool activeOnly = false,
  }) async {
    final activeClause = activeOnly ? ' AND is_active = 1' : '';
    final groups = await db
        .customSelect(
          'SELECT * FROM product_option_groups WHERE product_id = ? '
          '$activeClause ORDER BY sort_order, name',
          variables: [Variable.withString(productId)],
        )
        .get();
    final choices = await db
        .customSelect(
          'SELECT * FROM product_option_choices WHERE product_id = ? '
          '$activeClause ORDER BY sort_order, name',
          variables: [Variable.withString(productId)],
        )
        .get();
    return [
      for (final group in groups)
        ProductOptionGroup(
          id: group.read<String>('id'),
          productId: productId,
          businessId: group.read<String>('business_id'),
          name: group.read<String>('name'),
          required: group.read<bool>('is_required'),
          multiple: group.read<bool>('allow_multiple'),
          minSelections: group.read<int>('min_selections'),
          maxSelections: group.read<int?>('max_selections'),
          isAddOn: group.read<bool>('is_add_on'),
          sortOrder: group.read<int>('sort_order'),
          choices: [
            for (final choice in choices)
              if (choice.read<String>('group_id') == group.read<String>('id'))
                ProductOptionChoice(
                  id: choice.read<String>('id'),
                  groupId: choice.read<String>('group_id'),
                  name: choice.read<String>('name'),
                  priceDeltaCents: choice.read<int>('price_delta_cents'),
                  inventoryProductId: choice.read<String?>(
                    'inventory_product_id',
                  ),
                  inventorySupplyId: choice.read<String?>(
                    'inventory_supply_id',
                  ),
                  inventoryQuantity: choice.read<double>('inventory_quantity'),
                  sortOrder: choice.read<int>('sort_order'),
                  isActive: choice.read<bool>('is_active'),
                ),
          ],
          isActive: group.read<bool>('is_active'),
        ),
    ];
  }

  Future<List<ProductOptionGroup>> saveGroups({
    required String productId,
    required String businessId,
    required List<ProductOptionGroup> groups,
  }) async {
    final normalizedGroups = <ProductOptionGroup>[
      for (final group in groups)
        () {
          final groupId = group.id.isEmpty ? _uuid.v4() : group.id;
          return ProductOptionGroup(
            id: groupId,
            productId: productId,
            businessId: businessId,
            name: group.name.trim(),
            required: group.required,
            multiple: group.multiple,
            minSelections: group.minSelections,
            maxSelections: group.maxSelections,
            isAddOn: group.isAddOn,
            sortOrder: group.sortOrder,
            choices: [
              for (final choice in group.choices)
                ProductOptionChoice(
                  id: choice.id.isEmpty ? _uuid.v4() : choice.id,
                  groupId: groupId,
                  name: choice.name.trim(),
                  priceDeltaCents: choice.priceDeltaCents,
                  inventoryProductId: choice.inventoryProductId,
                  inventorySupplyId: choice.inventorySupplyId,
                  inventoryQuantity: choice.inventoryQuantity,
                  sortOrder: choice.sortOrder,
                  isActive: choice.isActive,
                ),
            ],
          );
        }(),
    ];
    await db.transaction(() async {
      await db.customStatement(
        'UPDATE product_option_groups SET is_active = 0 WHERE product_id = ?',
        [productId],
      );
      await db.customStatement(
        'UPDATE product_option_choices SET is_active = 0 WHERE product_id = ?',
        [productId],
      );
      for (
        var groupIndex = 0;
        groupIndex < normalizedGroups.length;
        groupIndex++
      ) {
        final group = normalizedGroups[groupIndex];
        final groupId = group.id;
        await db.customStatement(
          'INSERT OR REPLACE INTO product_option_groups '
          '(id, business_id, product_id, name, is_required, allow_multiple, '
          'min_selections, max_selections, is_add_on, sort_order, is_active) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            groupId,
            businessId,
            productId,
            group.name.trim(),
            group.required ? 1 : 0,
            group.multiple ? 1 : 0,
            group.minSelections,
            group.maxSelections,
            group.isAddOn ? 1 : 0,
            groupIndex,
            group.isActive ? 1 : 0,
          ],
        );
        for (
          var choiceIndex = 0;
          choiceIndex < group.choices.length;
          choiceIndex++
        ) {
          final choice = group.choices[choiceIndex];
          await db.customStatement(
            'INSERT OR REPLACE INTO product_option_choices '
            '(id, business_id, product_id, group_id, name, price_delta_cents, '
            'inventory_product_id, inventory_supply_id, inventory_quantity, '
            'sort_order, is_active) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              choice.id,
              businessId,
              productId,
              groupId,
              choice.name.trim(),
              choice.priceDeltaCents,
              choice.inventoryProductId,
              choice.inventorySupplyId,
              choice.inventoryQuantity,
              choiceIndex,
              choice.isActive ? 1 : 0,
            ],
          );
        }
      }
    });
    if (client == null) return normalizedGroups;
    await client!
        .from('product_option_choices')
        .delete()
        .eq('product_id', productId);
    await client!
        .from('product_option_groups')
        .delete()
        .eq('product_id', productId);
    await client!.from('product_option_groups').upsert([
      for (final group in normalizedGroups)
        {
          'id': group.id,
          'business_id': businessId,
          'product_id': productId,
          'name': group.name.trim(),
          'is_required': group.required,
          'allow_multiple': group.multiple,
          'min_selections': group.minSelections,
          'max_selections': group.maxSelections,
          'is_add_on': group.isAddOn,
          'sort_order': group.sortOrder,
          'is_active': group.isActive,
        },
    ]);
    try {
      await client!.from('product_option_choices').upsert([
        for (final group in normalizedGroups)
          for (final choice in group.choices)
            {
              'id': choice.id,
              'business_id': businessId,
              'product_id': productId,
              'group_id': group.id,
              'name': choice.name,
              'price_delta_cents': choice.priceDeltaCents,
              'inventory_product_id': choice.inventoryProductId,
              'inventory_supply_id': choice.inventorySupplyId,
              'inventory_quantity': choice.inventoryQuantity,
              'sort_order': choice.sortOrder,
              'is_active': choice.isActive,
            },
      ]);
    } on PostgrestException catch (error) {
      if (error.message.toLowerCase().contains('schema cache') ||
          error.message.toLowerCase().contains('inventory_supply_id')) {
        throw StateError(
          'Options were saved locally, but cloud sync needs the latest '
          'Supabase migration. Apply 20261101060000_reload_product_option_schema.sql '
          'and try again.',
        );
      }
      rethrow;
    }
    return normalizedGroups;
  }
}

final productVariantServiceProvider = Provider<ProductVariantService>((ref) {
  final client = ref.watch(supabaseAvailableProvider)
      ? ref.watch(supabaseClientProvider)
      : null;
  return ProductVariantService(ref.watch(databaseProvider), client: client);
});

final productVariantVersionProvider = StateProvider<int>((ref) => 0);
