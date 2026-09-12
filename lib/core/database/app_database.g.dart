// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BusinessesTable extends Businesses
    with TableInfo<$BusinessesTable, BusinessesData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BusinessesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerNameMeta = const VerificationMeta(
    'ownerName',
  );
  @override
  late final GeneratedColumn<String> ownerName = GeneratedColumn<String>(
    'owner_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _managerNameMeta = const VerificationMeta(
    'managerName',
  );
  @override
  late final GeneratedColumn<String> managerName = GeneratedColumn<String>(
    'manager_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _businessCategoryMeta = const VerificationMeta(
    'businessCategory',
  );
  @override
  late final GeneratedColumn<String> businessCategory = GeneratedColumn<String>(
    'business_category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressCountryMeta = const VerificationMeta(
    'addressCountry',
  );
  @override
  late final GeneratedColumn<String> addressCountry = GeneratedColumn<String>(
    'address_country',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressProvinceMeta = const VerificationMeta(
    'addressProvince',
  );
  @override
  late final GeneratedColumn<String> addressProvince = GeneratedColumn<String>(
    'address_province',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressCityMeta = const VerificationMeta(
    'addressCity',
  );
  @override
  late final GeneratedColumn<String> addressCity = GeneratedColumn<String>(
    'address_city',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressBarangayMeta = const VerificationMeta(
    'addressBarangay',
  );
  @override
  late final GeneratedColumn<String> addressBarangay = GeneratedColumn<String>(
    'address_barangay',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressZipCodeMeta = const VerificationMeta(
    'addressZipCode',
  );
  @override
  late final GeneratedColumn<String> addressZipCode = GeneratedColumn<String>(
    'address_zip_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startingCapitalMeta = const VerificationMeta(
    'startingCapital',
  );
  @override
  late final GeneratedColumn<int> startingCapital = GeneratedColumn<int>(
    'starting_capital',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _startingCapitalAccountIdMeta =
      const VerificationMeta('startingCapitalAccountId');
  @override
  late final GeneratedColumn<String> startingCapitalAccountId =
      GeneratedColumn<String>(
        'starting_capital_account_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isCurrentMeta = const VerificationMeta(
    'isCurrent',
  );
  @override
  late final GeneratedColumn<bool> isCurrent = GeneratedColumn<bool>(
    'is_current',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_current" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('PHP'),
  );
  static const VerificationMeta _ownerUserIdMeta = const VerificationMeta(
    'ownerUserId',
  );
  @override
  late final GeneratedColumn<String> ownerUserId = GeneratedColumn<String>(
    'owner_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    ownerName,
    managerName,
    businessCategory,
    addressCountry,
    addressProvince,
    addressCity,
    addressBarangay,
    addressZipCode,
    startingCapital,
    startingCapitalAccountId,
    isCurrent,
    currency,
    ownerUserId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'businesses';
  @override
  VerificationContext validateIntegrity(
    Insertable<BusinessesData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('owner_name')) {
      context.handle(
        _ownerNameMeta,
        ownerName.isAcceptableOrUnknown(data['owner_name']!, _ownerNameMeta),
      );
    }
    if (data.containsKey('manager_name')) {
      context.handle(
        _managerNameMeta,
        managerName.isAcceptableOrUnknown(
          data['manager_name']!,
          _managerNameMeta,
        ),
      );
    }
    if (data.containsKey('business_category')) {
      context.handle(
        _businessCategoryMeta,
        businessCategory.isAcceptableOrUnknown(
          data['business_category']!,
          _businessCategoryMeta,
        ),
      );
    }
    if (data.containsKey('address_country')) {
      context.handle(
        _addressCountryMeta,
        addressCountry.isAcceptableOrUnknown(
          data['address_country']!,
          _addressCountryMeta,
        ),
      );
    }
    if (data.containsKey('address_province')) {
      context.handle(
        _addressProvinceMeta,
        addressProvince.isAcceptableOrUnknown(
          data['address_province']!,
          _addressProvinceMeta,
        ),
      );
    }
    if (data.containsKey('address_city')) {
      context.handle(
        _addressCityMeta,
        addressCity.isAcceptableOrUnknown(
          data['address_city']!,
          _addressCityMeta,
        ),
      );
    }
    if (data.containsKey('address_barangay')) {
      context.handle(
        _addressBarangayMeta,
        addressBarangay.isAcceptableOrUnknown(
          data['address_barangay']!,
          _addressBarangayMeta,
        ),
      );
    }
    if (data.containsKey('address_zip_code')) {
      context.handle(
        _addressZipCodeMeta,
        addressZipCode.isAcceptableOrUnknown(
          data['address_zip_code']!,
          _addressZipCodeMeta,
        ),
      );
    }
    if (data.containsKey('starting_capital')) {
      context.handle(
        _startingCapitalMeta,
        startingCapital.isAcceptableOrUnknown(
          data['starting_capital']!,
          _startingCapitalMeta,
        ),
      );
    }
    if (data.containsKey('starting_capital_account_id')) {
      context.handle(
        _startingCapitalAccountIdMeta,
        startingCapitalAccountId.isAcceptableOrUnknown(
          data['starting_capital_account_id']!,
          _startingCapitalAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('is_current')) {
      context.handle(
        _isCurrentMeta,
        isCurrent.isAcceptableOrUnknown(data['is_current']!, _isCurrentMeta),
      );
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    }
    if (data.containsKey('owner_user_id')) {
      context.handle(
        _ownerUserIdMeta,
        ownerUserId.isAcceptableOrUnknown(
          data['owner_user_id']!,
          _ownerUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerUserIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BusinessesData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BusinessesData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      ownerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_name'],
      ),
      managerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manager_name'],
      ),
      businessCategory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_category'],
      ),
      addressCountry: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address_country'],
      ),
      addressProvince: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address_province'],
      ),
      addressCity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address_city'],
      ),
      addressBarangay: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address_barangay'],
      ),
      addressZipCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address_zip_code'],
      ),
      startingCapital: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starting_capital'],
      )!,
      startingCapitalAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}starting_capital_account_id'],
      ),
      isCurrent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_current'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      ownerUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_user_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BusinessesTable createAlias(String alias) {
    return $BusinessesTable(attachedDatabase, alias);
  }
}

class BusinessesData extends DataClass implements Insertable<BusinessesData> {
  final String id;
  final String name;
  final String? ownerName;
  final String? managerName;
  final String? businessCategory;
  final String? addressCountry;
  final String? addressProvince;
  final String? addressCity;
  final String? addressBarangay;
  final String? addressZipCode;
  final int startingCapital;
  final String? startingCapitalAccountId;
  final bool isCurrent;
  final String currency;
  final String ownerUserId;
  final DateTime createdAt;
  const BusinessesData({
    required this.id,
    required this.name,
    this.ownerName,
    this.managerName,
    this.businessCategory,
    this.addressCountry,
    this.addressProvince,
    this.addressCity,
    this.addressBarangay,
    this.addressZipCode,
    required this.startingCapital,
    this.startingCapitalAccountId,
    required this.isCurrent,
    required this.currency,
    required this.ownerUserId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || ownerName != null) {
      map['owner_name'] = Variable<String>(ownerName);
    }
    if (!nullToAbsent || managerName != null) {
      map['manager_name'] = Variable<String>(managerName);
    }
    if (!nullToAbsent || businessCategory != null) {
      map['business_category'] = Variable<String>(businessCategory);
    }
    if (!nullToAbsent || addressCountry != null) {
      map['address_country'] = Variable<String>(addressCountry);
    }
    if (!nullToAbsent || addressProvince != null) {
      map['address_province'] = Variable<String>(addressProvince);
    }
    if (!nullToAbsent || addressCity != null) {
      map['address_city'] = Variable<String>(addressCity);
    }
    if (!nullToAbsent || addressBarangay != null) {
      map['address_barangay'] = Variable<String>(addressBarangay);
    }
    if (!nullToAbsent || addressZipCode != null) {
      map['address_zip_code'] = Variable<String>(addressZipCode);
    }
    map['starting_capital'] = Variable<int>(startingCapital);
    if (!nullToAbsent || startingCapitalAccountId != null) {
      map['starting_capital_account_id'] = Variable<String>(
        startingCapitalAccountId,
      );
    }
    map['is_current'] = Variable<bool>(isCurrent);
    map['currency'] = Variable<String>(currency);
    map['owner_user_id'] = Variable<String>(ownerUserId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  BusinessesCompanion toCompanion(bool nullToAbsent) {
    return BusinessesCompanion(
      id: Value(id),
      name: Value(name),
      ownerName: ownerName == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerName),
      managerName: managerName == null && nullToAbsent
          ? const Value.absent()
          : Value(managerName),
      businessCategory: businessCategory == null && nullToAbsent
          ? const Value.absent()
          : Value(businessCategory),
      addressCountry: addressCountry == null && nullToAbsent
          ? const Value.absent()
          : Value(addressCountry),
      addressProvince: addressProvince == null && nullToAbsent
          ? const Value.absent()
          : Value(addressProvince),
      addressCity: addressCity == null && nullToAbsent
          ? const Value.absent()
          : Value(addressCity),
      addressBarangay: addressBarangay == null && nullToAbsent
          ? const Value.absent()
          : Value(addressBarangay),
      addressZipCode: addressZipCode == null && nullToAbsent
          ? const Value.absent()
          : Value(addressZipCode),
      startingCapital: Value(startingCapital),
      startingCapitalAccountId: startingCapitalAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(startingCapitalAccountId),
      isCurrent: Value(isCurrent),
      currency: Value(currency),
      ownerUserId: Value(ownerUserId),
      createdAt: Value(createdAt),
    );
  }

  factory BusinessesData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BusinessesData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      ownerName: serializer.fromJson<String?>(json['ownerName']),
      managerName: serializer.fromJson<String?>(json['managerName']),
      businessCategory: serializer.fromJson<String?>(json['businessCategory']),
      addressCountry: serializer.fromJson<String?>(json['addressCountry']),
      addressProvince: serializer.fromJson<String?>(json['addressProvince']),
      addressCity: serializer.fromJson<String?>(json['addressCity']),
      addressBarangay: serializer.fromJson<String?>(json['addressBarangay']),
      addressZipCode: serializer.fromJson<String?>(json['addressZipCode']),
      startingCapital: serializer.fromJson<int>(json['startingCapital']),
      startingCapitalAccountId: serializer.fromJson<String?>(
        json['startingCapitalAccountId'],
      ),
      isCurrent: serializer.fromJson<bool>(json['isCurrent']),
      currency: serializer.fromJson<String>(json['currency']),
      ownerUserId: serializer.fromJson<String>(json['ownerUserId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'ownerName': serializer.toJson<String?>(ownerName),
      'managerName': serializer.toJson<String?>(managerName),
      'businessCategory': serializer.toJson<String?>(businessCategory),
      'addressCountry': serializer.toJson<String?>(addressCountry),
      'addressProvince': serializer.toJson<String?>(addressProvince),
      'addressCity': serializer.toJson<String?>(addressCity),
      'addressBarangay': serializer.toJson<String?>(addressBarangay),
      'addressZipCode': serializer.toJson<String?>(addressZipCode),
      'startingCapital': serializer.toJson<int>(startingCapital),
      'startingCapitalAccountId': serializer.toJson<String?>(
        startingCapitalAccountId,
      ),
      'isCurrent': serializer.toJson<bool>(isCurrent),
      'currency': serializer.toJson<String>(currency),
      'ownerUserId': serializer.toJson<String>(ownerUserId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  BusinessesData copyWith({
    String? id,
    String? name,
    Value<String?> ownerName = const Value.absent(),
    Value<String?> managerName = const Value.absent(),
    Value<String?> businessCategory = const Value.absent(),
    Value<String?> addressCountry = const Value.absent(),
    Value<String?> addressProvince = const Value.absent(),
    Value<String?> addressCity = const Value.absent(),
    Value<String?> addressBarangay = const Value.absent(),
    Value<String?> addressZipCode = const Value.absent(),
    int? startingCapital,
    Value<String?> startingCapitalAccountId = const Value.absent(),
    bool? isCurrent,
    String? currency,
    String? ownerUserId,
    DateTime? createdAt,
  }) => BusinessesData(
    id: id ?? this.id,
    name: name ?? this.name,
    ownerName: ownerName.present ? ownerName.value : this.ownerName,
    managerName: managerName.present ? managerName.value : this.managerName,
    businessCategory: businessCategory.present
        ? businessCategory.value
        : this.businessCategory,
    addressCountry: addressCountry.present
        ? addressCountry.value
        : this.addressCountry,
    addressProvince: addressProvince.present
        ? addressProvince.value
        : this.addressProvince,
    addressCity: addressCity.present ? addressCity.value : this.addressCity,
    addressBarangay: addressBarangay.present
        ? addressBarangay.value
        : this.addressBarangay,
    addressZipCode: addressZipCode.present
        ? addressZipCode.value
        : this.addressZipCode,
    startingCapital: startingCapital ?? this.startingCapital,
    startingCapitalAccountId: startingCapitalAccountId.present
        ? startingCapitalAccountId.value
        : this.startingCapitalAccountId,
    isCurrent: isCurrent ?? this.isCurrent,
    currency: currency ?? this.currency,
    ownerUserId: ownerUserId ?? this.ownerUserId,
    createdAt: createdAt ?? this.createdAt,
  );
  BusinessesData copyWithCompanion(BusinessesCompanion data) {
    return BusinessesData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      ownerName: data.ownerName.present ? data.ownerName.value : this.ownerName,
      managerName: data.managerName.present
          ? data.managerName.value
          : this.managerName,
      businessCategory: data.businessCategory.present
          ? data.businessCategory.value
          : this.businessCategory,
      addressCountry: data.addressCountry.present
          ? data.addressCountry.value
          : this.addressCountry,
      addressProvince: data.addressProvince.present
          ? data.addressProvince.value
          : this.addressProvince,
      addressCity: data.addressCity.present
          ? data.addressCity.value
          : this.addressCity,
      addressBarangay: data.addressBarangay.present
          ? data.addressBarangay.value
          : this.addressBarangay,
      addressZipCode: data.addressZipCode.present
          ? data.addressZipCode.value
          : this.addressZipCode,
      startingCapital: data.startingCapital.present
          ? data.startingCapital.value
          : this.startingCapital,
      startingCapitalAccountId: data.startingCapitalAccountId.present
          ? data.startingCapitalAccountId.value
          : this.startingCapitalAccountId,
      isCurrent: data.isCurrent.present ? data.isCurrent.value : this.isCurrent,
      currency: data.currency.present ? data.currency.value : this.currency,
      ownerUserId: data.ownerUserId.present
          ? data.ownerUserId.value
          : this.ownerUserId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BusinessesData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('ownerName: $ownerName, ')
          ..write('managerName: $managerName, ')
          ..write('businessCategory: $businessCategory, ')
          ..write('addressCountry: $addressCountry, ')
          ..write('addressProvince: $addressProvince, ')
          ..write('addressCity: $addressCity, ')
          ..write('addressBarangay: $addressBarangay, ')
          ..write('addressZipCode: $addressZipCode, ')
          ..write('startingCapital: $startingCapital, ')
          ..write('startingCapitalAccountId: $startingCapitalAccountId, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('currency: $currency, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    ownerName,
    managerName,
    businessCategory,
    addressCountry,
    addressProvince,
    addressCity,
    addressBarangay,
    addressZipCode,
    startingCapital,
    startingCapitalAccountId,
    isCurrent,
    currency,
    ownerUserId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BusinessesData &&
          other.id == this.id &&
          other.name == this.name &&
          other.ownerName == this.ownerName &&
          other.managerName == this.managerName &&
          other.businessCategory == this.businessCategory &&
          other.addressCountry == this.addressCountry &&
          other.addressProvince == this.addressProvince &&
          other.addressCity == this.addressCity &&
          other.addressBarangay == this.addressBarangay &&
          other.addressZipCode == this.addressZipCode &&
          other.startingCapital == this.startingCapital &&
          other.startingCapitalAccountId == this.startingCapitalAccountId &&
          other.isCurrent == this.isCurrent &&
          other.currency == this.currency &&
          other.ownerUserId == this.ownerUserId &&
          other.createdAt == this.createdAt);
}

class BusinessesCompanion extends UpdateCompanion<BusinessesData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> ownerName;
  final Value<String?> managerName;
  final Value<String?> businessCategory;
  final Value<String?> addressCountry;
  final Value<String?> addressProvince;
  final Value<String?> addressCity;
  final Value<String?> addressBarangay;
  final Value<String?> addressZipCode;
  final Value<int> startingCapital;
  final Value<String?> startingCapitalAccountId;
  final Value<bool> isCurrent;
  final Value<String> currency;
  final Value<String> ownerUserId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const BusinessesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.ownerName = const Value.absent(),
    this.managerName = const Value.absent(),
    this.businessCategory = const Value.absent(),
    this.addressCountry = const Value.absent(),
    this.addressProvince = const Value.absent(),
    this.addressCity = const Value.absent(),
    this.addressBarangay = const Value.absent(),
    this.addressZipCode = const Value.absent(),
    this.startingCapital = const Value.absent(),
    this.startingCapitalAccountId = const Value.absent(),
    this.isCurrent = const Value.absent(),
    this.currency = const Value.absent(),
    this.ownerUserId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BusinessesCompanion.insert({
    required String id,
    required String name,
    this.ownerName = const Value.absent(),
    this.managerName = const Value.absent(),
    this.businessCategory = const Value.absent(),
    this.addressCountry = const Value.absent(),
    this.addressProvince = const Value.absent(),
    this.addressCity = const Value.absent(),
    this.addressBarangay = const Value.absent(),
    this.addressZipCode = const Value.absent(),
    this.startingCapital = const Value.absent(),
    this.startingCapitalAccountId = const Value.absent(),
    this.isCurrent = const Value.absent(),
    this.currency = const Value.absent(),
    required String ownerUserId,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       ownerUserId = Value(ownerUserId);
  static Insertable<BusinessesData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? ownerName,
    Expression<String>? managerName,
    Expression<String>? businessCategory,
    Expression<String>? addressCountry,
    Expression<String>? addressProvince,
    Expression<String>? addressCity,
    Expression<String>? addressBarangay,
    Expression<String>? addressZipCode,
    Expression<int>? startingCapital,
    Expression<String>? startingCapitalAccountId,
    Expression<bool>? isCurrent,
    Expression<String>? currency,
    Expression<String>? ownerUserId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (ownerName != null) 'owner_name': ownerName,
      if (managerName != null) 'manager_name': managerName,
      if (businessCategory != null) 'business_category': businessCategory,
      if (addressCountry != null) 'address_country': addressCountry,
      if (addressProvince != null) 'address_province': addressProvince,
      if (addressCity != null) 'address_city': addressCity,
      if (addressBarangay != null) 'address_barangay': addressBarangay,
      if (addressZipCode != null) 'address_zip_code': addressZipCode,
      if (startingCapital != null) 'starting_capital': startingCapital,
      if (startingCapitalAccountId != null)
        'starting_capital_account_id': startingCapitalAccountId,
      if (isCurrent != null) 'is_current': isCurrent,
      if (currency != null) 'currency': currency,
      if (ownerUserId != null) 'owner_user_id': ownerUserId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BusinessesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? ownerName,
    Value<String?>? managerName,
    Value<String?>? businessCategory,
    Value<String?>? addressCountry,
    Value<String?>? addressProvince,
    Value<String?>? addressCity,
    Value<String?>? addressBarangay,
    Value<String?>? addressZipCode,
    Value<int>? startingCapital,
    Value<String?>? startingCapitalAccountId,
    Value<bool>? isCurrent,
    Value<String>? currency,
    Value<String>? ownerUserId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return BusinessesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerName: ownerName ?? this.ownerName,
      managerName: managerName ?? this.managerName,
      businessCategory: businessCategory ?? this.businessCategory,
      addressCountry: addressCountry ?? this.addressCountry,
      addressProvince: addressProvince ?? this.addressProvince,
      addressCity: addressCity ?? this.addressCity,
      addressBarangay: addressBarangay ?? this.addressBarangay,
      addressZipCode: addressZipCode ?? this.addressZipCode,
      startingCapital: startingCapital ?? this.startingCapital,
      startingCapitalAccountId:
          startingCapitalAccountId ?? this.startingCapitalAccountId,
      isCurrent: isCurrent ?? this.isCurrent,
      currency: currency ?? this.currency,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (ownerName.present) {
      map['owner_name'] = Variable<String>(ownerName.value);
    }
    if (managerName.present) {
      map['manager_name'] = Variable<String>(managerName.value);
    }
    if (businessCategory.present) {
      map['business_category'] = Variable<String>(businessCategory.value);
    }
    if (addressCountry.present) {
      map['address_country'] = Variable<String>(addressCountry.value);
    }
    if (addressProvince.present) {
      map['address_province'] = Variable<String>(addressProvince.value);
    }
    if (addressCity.present) {
      map['address_city'] = Variable<String>(addressCity.value);
    }
    if (addressBarangay.present) {
      map['address_barangay'] = Variable<String>(addressBarangay.value);
    }
    if (addressZipCode.present) {
      map['address_zip_code'] = Variable<String>(addressZipCode.value);
    }
    if (startingCapital.present) {
      map['starting_capital'] = Variable<int>(startingCapital.value);
    }
    if (startingCapitalAccountId.present) {
      map['starting_capital_account_id'] = Variable<String>(
        startingCapitalAccountId.value,
      );
    }
    if (isCurrent.present) {
      map['is_current'] = Variable<bool>(isCurrent.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (ownerUserId.present) {
      map['owner_user_id'] = Variable<String>(ownerUserId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BusinessesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('ownerName: $ownerName, ')
          ..write('managerName: $managerName, ')
          ..write('businessCategory: $businessCategory, ')
          ..write('addressCountry: $addressCountry, ')
          ..write('addressProvince: $addressProvince, ')
          ..write('addressCity: $addressCity, ')
          ..write('addressBarangay: $addressBarangay, ')
          ..write('addressZipCode: $addressZipCode, ')
          ..write('startingCapital: $startingCapital, ')
          ..write('startingCapitalAccountId: $startingCapitalAccountId, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('currency: $currency, ')
          ..write('ownerUserId: $ownerUserId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 20,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPaymentAccountMeta = const VerificationMeta(
    'isPaymentAccount',
  );
  @override
  late final GeneratedColumn<bool> isPaymentAccount = GeneratedColumn<bool>(
    'is_payment_account',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_payment_account" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _startingBalanceMeta = const VerificationMeta(
    'startingBalance',
  );
  @override
  late final GeneratedColumn<int> startingBalance = GeneratedColumn<int>(
    'starting_balance',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    name,
    type,
    isPaymentAccount,
    startingBalance,
    isActive,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Account> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('is_payment_account')) {
      context.handle(
        _isPaymentAccountMeta,
        isPaymentAccount.isAcceptableOrUnknown(
          data['is_payment_account']!,
          _isPaymentAccountMeta,
        ),
      );
    }
    if (data.containsKey('starting_balance')) {
      context.handle(
        _startingBalanceMeta,
        startingBalance.isAcceptableOrUnknown(
          data['starting_balance']!,
          _startingBalanceMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      isPaymentAccount: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_payment_account'],
      )!,
      startingBalance: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starting_balance'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class Account extends DataClass implements Insertable<Account> {
  final String id;
  final String businessId;
  final String name;
  final String type;
  final bool isPaymentAccount;
  final int startingBalance;
  final bool isActive;
  final DateTime createdAt;
  const Account({
    required this.id,
    required this.businessId,
    required this.name,
    required this.type,
    required this.isPaymentAccount,
    required this.startingBalance,
    required this.isActive,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['is_payment_account'] = Variable<bool>(isPaymentAccount);
    map['starting_balance'] = Variable<int>(startingBalance);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      name: Value(name),
      type: Value(type),
      isPaymentAccount: Value(isPaymentAccount),
      startingBalance: Value(startingBalance),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory Account.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      isPaymentAccount: serializer.fromJson<bool>(json['isPaymentAccount']),
      startingBalance: serializer.fromJson<int>(json['startingBalance']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'isPaymentAccount': serializer.toJson<bool>(isPaymentAccount),
      'startingBalance': serializer.toJson<int>(startingBalance),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Account copyWith({
    String? id,
    String? businessId,
    String? name,
    String? type,
    bool? isPaymentAccount,
    int? startingBalance,
    bool? isActive,
    DateTime? createdAt,
  }) => Account(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    name: name ?? this.name,
    type: type ?? this.type,
    isPaymentAccount: isPaymentAccount ?? this.isPaymentAccount,
    startingBalance: startingBalance ?? this.startingBalance,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      isPaymentAccount: data.isPaymentAccount.present
          ? data.isPaymentAccount.value
          : this.isPaymentAccount,
      startingBalance: data.startingBalance.present
          ? data.startingBalance.value
          : this.startingBalance,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('isPaymentAccount: $isPaymentAccount, ')
          ..write('startingBalance: $startingBalance, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    name,
    type,
    isPaymentAccount,
    startingBalance,
    isActive,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.name == this.name &&
          other.type == this.type &&
          other.isPaymentAccount == this.isPaymentAccount &&
          other.startingBalance == this.startingBalance &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> name;
  final Value<String> type;
  final Value<bool> isPaymentAccount;
  final Value<int> startingBalance;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.isPaymentAccount = const Value.absent(),
    this.startingBalance = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required String businessId,
    required String name,
    required String type,
    this.isPaymentAccount = const Value.absent(),
    this.startingBalance = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       name = Value(name),
       type = Value(type);
  static Insertable<Account> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? name,
    Expression<String>? type,
    Expression<bool>? isPaymentAccount,
    Expression<int>? startingBalance,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (isPaymentAccount != null) 'is_payment_account': isPaymentAccount,
      if (startingBalance != null) 'starting_balance': startingBalance,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? name,
    Value<String>? type,
    Value<bool>? isPaymentAccount,
    Value<int>? startingBalance,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      type: type ?? this.type,
      isPaymentAccount: isPaymentAccount ?? this.isPaymentAccount,
      startingBalance: startingBalance ?? this.startingBalance,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (isPaymentAccount.present) {
      map['is_payment_account'] = Variable<bool>(isPaymentAccount.value);
    }
    if (startingBalance.present) {
      map['starting_balance'] = Variable<int>(startingBalance.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('isPaymentAccount: $isPaymentAccount, ')
          ..write('startingBalance: $startingBalance, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JournalEntriesTable extends JournalEntries
    with TableInfo<$JournalEntriesTable, JournalEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _entryDateMeta = const VerificationMeta(
    'entryDate',
  );
  @override
  late final GeneratedColumn<DateTime> entryDate = GeneratedColumn<DateTime>(
    'entry_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('completed'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    entryDate,
    description,
    sourceType,
    sourceId,
    status,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<JournalEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('entry_date')) {
      context.handle(
        _entryDateMeta,
        entryDate.isAcceptableOrUnknown(data['entry_date']!, _entryDateMeta),
      );
    } else if (isInserting) {
      context.missing(_entryDateMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTypeMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JournalEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      entryDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}entry_date'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $JournalEntriesTable createAlias(String alias) {
    return $JournalEntriesTable(attachedDatabase, alias);
  }
}

class JournalEntry extends DataClass implements Insertable<JournalEntry> {
  final String id;
  final String businessId;
  final DateTime entryDate;
  final String? description;
  final String sourceType;
  final String? sourceId;
  final String status;
  final DateTime createdAt;
  const JournalEntry({
    required this.id,
    required this.businessId,
    required this.entryDate,
    this.description,
    required this.sourceType,
    this.sourceId,
    required this.status,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['entry_date'] = Variable<DateTime>(entryDate);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['source_type'] = Variable<String>(sourceType);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  JournalEntriesCompanion toCompanion(bool nullToAbsent) {
    return JournalEntriesCompanion(
      id: Value(id),
      businessId: Value(businessId),
      entryDate: Value(entryDate),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      sourceType: Value(sourceType),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      status: Value(status),
      createdAt: Value(createdAt),
    );
  }

  factory JournalEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalEntry(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      entryDate: serializer.fromJson<DateTime>(json['entryDate']),
      description: serializer.fromJson<String?>(json['description']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'entryDate': serializer.toJson<DateTime>(entryDate),
      'description': serializer.toJson<String?>(description),
      'sourceType': serializer.toJson<String>(sourceType),
      'sourceId': serializer.toJson<String?>(sourceId),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  JournalEntry copyWith({
    String? id,
    String? businessId,
    DateTime? entryDate,
    Value<String?> description = const Value.absent(),
    String? sourceType,
    Value<String?> sourceId = const Value.absent(),
    String? status,
    DateTime? createdAt,
  }) => JournalEntry(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    entryDate: entryDate ?? this.entryDate,
    description: description.present ? description.value : this.description,
    sourceType: sourceType ?? this.sourceType,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
  );
  JournalEntry copyWithCompanion(JournalEntriesCompanion data) {
    return JournalEntry(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      entryDate: data.entryDate.present ? data.entryDate.value : this.entryDate,
      description: data.description.present
          ? data.description.value
          : this.description,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntry(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('entryDate: $entryDate, ')
          ..write('description: $description, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceId: $sourceId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    entryDate,
    description,
    sourceType,
    sourceId,
    status,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalEntry &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.entryDate == this.entryDate &&
          other.description == this.description &&
          other.sourceType == this.sourceType &&
          other.sourceId == this.sourceId &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class JournalEntriesCompanion extends UpdateCompanion<JournalEntry> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<DateTime> entryDate;
  final Value<String?> description;
  final Value<String> sourceType;
  final Value<String?> sourceId;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const JournalEntriesCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.entryDate = const Value.absent(),
    this.description = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JournalEntriesCompanion.insert({
    required String id,
    required String businessId,
    required DateTime entryDate,
    this.description = const Value.absent(),
    required String sourceType,
    this.sourceId = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       entryDate = Value(entryDate),
       sourceType = Value(sourceType);
  static Insertable<JournalEntry> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<DateTime>? entryDate,
    Expression<String>? description,
    Expression<String>? sourceType,
    Expression<String>? sourceId,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (entryDate != null) 'entry_date': entryDate,
      if (description != null) 'description': description,
      if (sourceType != null) 'source_type': sourceType,
      if (sourceId != null) 'source_id': sourceId,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JournalEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<DateTime>? entryDate,
    Value<String?>? description,
    Value<String>? sourceType,
    Value<String?>? sourceId,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return JournalEntriesCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      entryDate: entryDate ?? this.entryDate,
      description: description ?? this.description,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (entryDate.present) {
      map['entry_date'] = Variable<DateTime>(entryDate.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntriesCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('entryDate: $entryDate, ')
          ..write('description: $description, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceId: $sourceId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LedgerLinesTable extends LedgerLines
    with TableInfo<$LedgerLinesTable, LedgerLine> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgerLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _journalEntryIdMeta = const VerificationMeta(
    'journalEntryId',
  );
  @override
  late final GeneratedColumn<String> journalEntryId = GeneratedColumn<String>(
    'journal_entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES journal_entries (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _debitMeta = const VerificationMeta('debit');
  @override
  late final GeneratedColumn<int> debit = GeneratedColumn<int>(
    'debit',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _creditMeta = const VerificationMeta('credit');
  @override
  late final GeneratedColumn<int> credit = GeneratedColumn<int>(
    'credit',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    journalEntryId,
    accountId,
    debit,
    credit,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledger_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<LedgerLine> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('journal_entry_id')) {
      context.handle(
        _journalEntryIdMeta,
        journalEntryId.isAcceptableOrUnknown(
          data['journal_entry_id']!,
          _journalEntryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_journalEntryIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('debit')) {
      context.handle(
        _debitMeta,
        debit.isAcceptableOrUnknown(data['debit']!, _debitMeta),
      );
    }
    if (data.containsKey('credit')) {
      context.handle(
        _creditMeta,
        credit.isAcceptableOrUnknown(data['credit']!, _creditMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LedgerLine map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LedgerLine(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      journalEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}journal_entry_id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      debit: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}debit'],
      )!,
      credit: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}credit'],
      )!,
    );
  }

  @override
  $LedgerLinesTable createAlias(String alias) {
    return $LedgerLinesTable(attachedDatabase, alias);
  }
}

class LedgerLine extends DataClass implements Insertable<LedgerLine> {
  final String id;
  final String journalEntryId;
  final String accountId;
  final int debit;
  final int credit;
  const LedgerLine({
    required this.id,
    required this.journalEntryId,
    required this.accountId,
    required this.debit,
    required this.credit,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['journal_entry_id'] = Variable<String>(journalEntryId);
    map['account_id'] = Variable<String>(accountId);
    map['debit'] = Variable<int>(debit);
    map['credit'] = Variable<int>(credit);
    return map;
  }

  LedgerLinesCompanion toCompanion(bool nullToAbsent) {
    return LedgerLinesCompanion(
      id: Value(id),
      journalEntryId: Value(journalEntryId),
      accountId: Value(accountId),
      debit: Value(debit),
      credit: Value(credit),
    );
  }

  factory LedgerLine.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LedgerLine(
      id: serializer.fromJson<String>(json['id']),
      journalEntryId: serializer.fromJson<String>(json['journalEntryId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      debit: serializer.fromJson<int>(json['debit']),
      credit: serializer.fromJson<int>(json['credit']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'journalEntryId': serializer.toJson<String>(journalEntryId),
      'accountId': serializer.toJson<String>(accountId),
      'debit': serializer.toJson<int>(debit),
      'credit': serializer.toJson<int>(credit),
    };
  }

  LedgerLine copyWith({
    String? id,
    String? journalEntryId,
    String? accountId,
    int? debit,
    int? credit,
  }) => LedgerLine(
    id: id ?? this.id,
    journalEntryId: journalEntryId ?? this.journalEntryId,
    accountId: accountId ?? this.accountId,
    debit: debit ?? this.debit,
    credit: credit ?? this.credit,
  );
  LedgerLine copyWithCompanion(LedgerLinesCompanion data) {
    return LedgerLine(
      id: data.id.present ? data.id.value : this.id,
      journalEntryId: data.journalEntryId.present
          ? data.journalEntryId.value
          : this.journalEntryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      debit: data.debit.present ? data.debit.value : this.debit,
      credit: data.credit.present ? data.credit.value : this.credit,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LedgerLine(')
          ..write('id: $id, ')
          ..write('journalEntryId: $journalEntryId, ')
          ..write('accountId: $accountId, ')
          ..write('debit: $debit, ')
          ..write('credit: $credit')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, journalEntryId, accountId, debit, credit);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerLine &&
          other.id == this.id &&
          other.journalEntryId == this.journalEntryId &&
          other.accountId == this.accountId &&
          other.debit == this.debit &&
          other.credit == this.credit);
}

class LedgerLinesCompanion extends UpdateCompanion<LedgerLine> {
  final Value<String> id;
  final Value<String> journalEntryId;
  final Value<String> accountId;
  final Value<int> debit;
  final Value<int> credit;
  final Value<int> rowid;
  const LedgerLinesCompanion({
    this.id = const Value.absent(),
    this.journalEntryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.debit = const Value.absent(),
    this.credit = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LedgerLinesCompanion.insert({
    required String id,
    required String journalEntryId,
    required String accountId,
    this.debit = const Value.absent(),
    this.credit = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       journalEntryId = Value(journalEntryId),
       accountId = Value(accountId);
  static Insertable<LedgerLine> custom({
    Expression<String>? id,
    Expression<String>? journalEntryId,
    Expression<String>? accountId,
    Expression<int>? debit,
    Expression<int>? credit,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (journalEntryId != null) 'journal_entry_id': journalEntryId,
      if (accountId != null) 'account_id': accountId,
      if (debit != null) 'debit': debit,
      if (credit != null) 'credit': credit,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LedgerLinesCompanion copyWith({
    Value<String>? id,
    Value<String>? journalEntryId,
    Value<String>? accountId,
    Value<int>? debit,
    Value<int>? credit,
    Value<int>? rowid,
  }) {
    return LedgerLinesCompanion(
      id: id ?? this.id,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      accountId: accountId ?? this.accountId,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (journalEntryId.present) {
      map['journal_entry_id'] = Variable<String>(journalEntryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (debit.present) {
      map['debit'] = Variable<int>(debit.value);
    }
    if (credit.present) {
      map['credit'] = Variable<int>(credit.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgerLinesCompanion(')
          ..write('id: $id, ')
          ..write('journalEntryId: $journalEntryId, ')
          ..write('accountId: $accountId, ')
          ..write('debit: $debit, ')
          ..write('credit: $credit, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _txnTypeMeta = const VerificationMeta(
    'txnType',
  );
  @override
  late final GeneratedColumn<String> txnType = GeneratedColumn<String>(
    'txn_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ledgerAccountIdMeta = const VerificationMeta(
    'ledgerAccountId',
  );
  @override
  late final GeneratedColumn<String> ledgerAccountId = GeneratedColumn<String>(
    'ledger_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _isCustomMeta = const VerificationMeta(
    'isCustom',
  );
  @override
  late final GeneratedColumn<bool> isCustom = GeneratedColumn<bool>(
    'is_custom',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_custom" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    name,
    txnType,
    ledgerAccountId,
    isCustom,
    isActive,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('txn_type')) {
      context.handle(
        _txnTypeMeta,
        txnType.isAcceptableOrUnknown(data['txn_type']!, _txnTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_txnTypeMeta);
    }
    if (data.containsKey('ledger_account_id')) {
      context.handle(
        _ledgerAccountIdMeta,
        ledgerAccountId.isAcceptableOrUnknown(
          data['ledger_account_id']!,
          _ledgerAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ledgerAccountIdMeta);
    }
    if (data.containsKey('is_custom')) {
      context.handle(
        _isCustomMeta,
        isCustom.isAcceptableOrUnknown(data['is_custom']!, _isCustomMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      txnType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}txn_type'],
      )!,
      ledgerAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_account_id'],
      )!,
      isCustom: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_custom'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final String id;
  final String businessId;
  final String name;
  final String txnType;
  final String ledgerAccountId;
  final bool isCustom;
  final bool isActive;
  final DateTime createdAt;
  const Category({
    required this.id,
    required this.businessId,
    required this.name,
    required this.txnType,
    required this.ledgerAccountId,
    required this.isCustom,
    required this.isActive,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['name'] = Variable<String>(name);
    map['txn_type'] = Variable<String>(txnType);
    map['ledger_account_id'] = Variable<String>(ledgerAccountId);
    map['is_custom'] = Variable<bool>(isCustom);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      businessId: Value(businessId),
      name: Value(name),
      txnType: Value(txnType),
      ledgerAccountId: Value(ledgerAccountId),
      isCustom: Value(isCustom),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      name: serializer.fromJson<String>(json['name']),
      txnType: serializer.fromJson<String>(json['txnType']),
      ledgerAccountId: serializer.fromJson<String>(json['ledgerAccountId']),
      isCustom: serializer.fromJson<bool>(json['isCustom']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'name': serializer.toJson<String>(name),
      'txnType': serializer.toJson<String>(txnType),
      'ledgerAccountId': serializer.toJson<String>(ledgerAccountId),
      'isCustom': serializer.toJson<bool>(isCustom),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Category copyWith({
    String? id,
    String? businessId,
    String? name,
    String? txnType,
    String? ledgerAccountId,
    bool? isCustom,
    bool? isActive,
    DateTime? createdAt,
  }) => Category(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    name: name ?? this.name,
    txnType: txnType ?? this.txnType,
    ledgerAccountId: ledgerAccountId ?? this.ledgerAccountId,
    isCustom: isCustom ?? this.isCustom,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      name: data.name.present ? data.name.value : this.name,
      txnType: data.txnType.present ? data.txnType.value : this.txnType,
      ledgerAccountId: data.ledgerAccountId.present
          ? data.ledgerAccountId.value
          : this.ledgerAccountId,
      isCustom: data.isCustom.present ? data.isCustom.value : this.isCustom,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('txnType: $txnType, ')
          ..write('ledgerAccountId: $ledgerAccountId, ')
          ..write('isCustom: $isCustom, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    name,
    txnType,
    ledgerAccountId,
    isCustom,
    isActive,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.name == this.name &&
          other.txnType == this.txnType &&
          other.ledgerAccountId == this.ledgerAccountId &&
          other.isCustom == this.isCustom &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> name;
  final Value<String> txnType;
  final Value<String> ledgerAccountId;
  final Value<bool> isCustom;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.name = const Value.absent(),
    this.txnType = const Value.absent(),
    this.ledgerAccountId = const Value.absent(),
    this.isCustom = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required String businessId,
    required String name,
    required String txnType,
    required String ledgerAccountId,
    this.isCustom = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       name = Value(name),
       txnType = Value(txnType),
       ledgerAccountId = Value(ledgerAccountId);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? name,
    Expression<String>? txnType,
    Expression<String>? ledgerAccountId,
    Expression<bool>? isCustom,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (name != null) 'name': name,
      if (txnType != null) 'txn_type': txnType,
      if (ledgerAccountId != null) 'ledger_account_id': ledgerAccountId,
      if (isCustom != null) 'is_custom': isCustom,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? name,
    Value<String>? txnType,
    Value<String>? ledgerAccountId,
    Value<bool>? isCustom,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      txnType: txnType ?? this.txnType,
      ledgerAccountId: ledgerAccountId ?? this.ledgerAccountId,
      isCustom: isCustom ?? this.isCustom,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (txnType.present) {
      map['txn_type'] = Variable<String>(txnType.value);
    }
    if (ledgerAccountId.present) {
      map['ledger_account_id'] = Variable<String>(ledgerAccountId.value);
    }
    if (isCustom.present) {
      map['is_custom'] = Variable<bool>(isCustom.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('txnType: $txnType, ')
          ..write('ledgerAccountId: $ledgerAccountId, ')
          ..write('isCustom: $isCustom, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomersTable extends Customers
    with TableInfo<$CustomersTable, Customer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    name,
    phone,
    notes,
    isActive,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Customer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Customer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Customer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CustomersTable createAlias(String alias) {
    return $CustomersTable(attachedDatabase, alias);
  }
}

class Customer extends DataClass implements Insertable<Customer> {
  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    this.notes,
    required this.isActive,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CustomersCompanion toCompanion(bool nullToAbsent) {
    return CustomersCompanion(
      id: Value(id),
      businessId: Value(businessId),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory Customer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Customer(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      notes: serializer.fromJson<String?>(json['notes']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'notes': serializer.toJson<String?>(notes),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Customer copyWith({
    String? id,
    String? businessId,
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
  }) => Customer(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    notes: notes.present ? notes.value : this.notes,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
  );
  Customer copyWithCompanion(CustomersCompanion data) {
    return Customer(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      notes: data.notes.present ? data.notes.value : this.notes,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Customer(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, businessId, name, phone, notes, isActive, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Customer &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.notes == this.notes &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class CustomersCompanion extends UpdateCompanion<Customer> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> notes;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CustomersCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomersCompanion.insert({
    required String id,
    required String businessId,
    required String name,
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       name = Value(name);
  static Insertable<Customer> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? notes,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (notes != null) 'notes': notes,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomersCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? name,
    Value<String?>? phone,
    Value<String?>? notes,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return CustomersCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomersCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IncomeTransactionsTable extends IncomeTransactions
    with TableInfo<$IncomeTransactionsTable, IncomeTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IncomeTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _txnDateMeta = const VerificationMeta(
    'txnDate',
  );
  @override
  late final GeneratedColumn<DateTime> txnDate = GeneratedColumn<DateTime>(
    'txn_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES customers (id)',
    ),
  );
  static const VerificationMeta _paymentAccountIdMeta = const VerificationMeta(
    'paymentAccountId',
  );
  @override
  late final GeneratedColumn<String> paymentAccountId = GeneratedColumn<String>(
    'payment_account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _referenceMeta = const VerificationMeta(
    'reference',
  );
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
    'reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('completed'),
  );
  static const VerificationMeta _journalEntryIdMeta = const VerificationMeta(
    'journalEntryId',
  );
  @override
  late final GeneratedColumn<String> journalEntryId = GeneratedColumn<String>(
    'journal_entry_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES journal_entries (id)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    txnDate,
    description,
    categoryId,
    amount,
    customerId,
    paymentAccountId,
    reference,
    notes,
    status,
    journalEntryId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'income_transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<IncomeTransaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('txn_date')) {
      context.handle(
        _txnDateMeta,
        txnDate.isAcceptableOrUnknown(data['txn_date']!, _txnDateMeta),
      );
    } else if (isInserting) {
      context.missing(_txnDateMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    }
    if (data.containsKey('payment_account_id')) {
      context.handle(
        _paymentAccountIdMeta,
        paymentAccountId.isAcceptableOrUnknown(
          data['payment_account_id']!,
          _paymentAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('reference')) {
      context.handle(
        _referenceMeta,
        reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('journal_entry_id')) {
      context.handle(
        _journalEntryIdMeta,
        journalEntryId.isAcceptableOrUnknown(
          data['journal_entry_id']!,
          _journalEntryIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IncomeTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IncomeTransaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      txnDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}txn_date'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      ),
      paymentAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_account_id'],
      ),
      reference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      journalEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}journal_entry_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $IncomeTransactionsTable createAlias(String alias) {
    return $IncomeTransactionsTable(attachedDatabase, alias);
  }
}

class IncomeTransaction extends DataClass
    implements Insertable<IncomeTransaction> {
  final String id;
  final String businessId;
  final DateTime txnDate;
  final String? description;
  final String categoryId;
  final int amount;
  final String? customerId;
  final String? paymentAccountId;
  final String? reference;
  final String? notes;
  final String status;
  final String? journalEntryId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const IncomeTransaction({
    required this.id,
    required this.businessId,
    required this.txnDate,
    this.description,
    required this.categoryId,
    required this.amount,
    this.customerId,
    this.paymentAccountId,
    this.reference,
    this.notes,
    required this.status,
    this.journalEntryId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['txn_date'] = Variable<DateTime>(txnDate);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['category_id'] = Variable<String>(categoryId);
    map['amount'] = Variable<int>(amount);
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    if (!nullToAbsent || paymentAccountId != null) {
      map['payment_account_id'] = Variable<String>(paymentAccountId);
    }
    if (!nullToAbsent || reference != null) {
      map['reference'] = Variable<String>(reference);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || journalEntryId != null) {
      map['journal_entry_id'] = Variable<String>(journalEntryId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  IncomeTransactionsCompanion toCompanion(bool nullToAbsent) {
    return IncomeTransactionsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      txnDate: Value(txnDate),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      categoryId: Value(categoryId),
      amount: Value(amount),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      paymentAccountId: paymentAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentAccountId),
      reference: reference == null && nullToAbsent
          ? const Value.absent()
          : Value(reference),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      status: Value(status),
      journalEntryId: journalEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(journalEntryId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory IncomeTransaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IncomeTransaction(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      txnDate: serializer.fromJson<DateTime>(json['txnDate']),
      description: serializer.fromJson<String?>(json['description']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      amount: serializer.fromJson<int>(json['amount']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      paymentAccountId: serializer.fromJson<String?>(json['paymentAccountId']),
      reference: serializer.fromJson<String?>(json['reference']),
      notes: serializer.fromJson<String?>(json['notes']),
      status: serializer.fromJson<String>(json['status']),
      journalEntryId: serializer.fromJson<String?>(json['journalEntryId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'txnDate': serializer.toJson<DateTime>(txnDate),
      'description': serializer.toJson<String?>(description),
      'categoryId': serializer.toJson<String>(categoryId),
      'amount': serializer.toJson<int>(amount),
      'customerId': serializer.toJson<String?>(customerId),
      'paymentAccountId': serializer.toJson<String?>(paymentAccountId),
      'reference': serializer.toJson<String?>(reference),
      'notes': serializer.toJson<String?>(notes),
      'status': serializer.toJson<String>(status),
      'journalEntryId': serializer.toJson<String?>(journalEntryId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  IncomeTransaction copyWith({
    String? id,
    String? businessId,
    DateTime? txnDate,
    Value<String?> description = const Value.absent(),
    String? categoryId,
    int? amount,
    Value<String?> customerId = const Value.absent(),
    Value<String?> paymentAccountId = const Value.absent(),
    Value<String?> reference = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? status,
    Value<String?> journalEntryId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => IncomeTransaction(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    txnDate: txnDate ?? this.txnDate,
    description: description.present ? description.value : this.description,
    categoryId: categoryId ?? this.categoryId,
    amount: amount ?? this.amount,
    customerId: customerId.present ? customerId.value : this.customerId,
    paymentAccountId: paymentAccountId.present
        ? paymentAccountId.value
        : this.paymentAccountId,
    reference: reference.present ? reference.value : this.reference,
    notes: notes.present ? notes.value : this.notes,
    status: status ?? this.status,
    journalEntryId: journalEntryId.present
        ? journalEntryId.value
        : this.journalEntryId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  IncomeTransaction copyWithCompanion(IncomeTransactionsCompanion data) {
    return IncomeTransaction(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      txnDate: data.txnDate.present ? data.txnDate.value : this.txnDate,
      description: data.description.present
          ? data.description.value
          : this.description,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      amount: data.amount.present ? data.amount.value : this.amount,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      paymentAccountId: data.paymentAccountId.present
          ? data.paymentAccountId.value
          : this.paymentAccountId,
      reference: data.reference.present ? data.reference.value : this.reference,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
      journalEntryId: data.journalEntryId.present
          ? data.journalEntryId.value
          : this.journalEntryId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IncomeTransaction(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('txnDate: $txnDate, ')
          ..write('description: $description, ')
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('customerId: $customerId, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('reference: $reference, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('journalEntryId: $journalEntryId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    txnDate,
    description,
    categoryId,
    amount,
    customerId,
    paymentAccountId,
    reference,
    notes,
    status,
    journalEntryId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IncomeTransaction &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.txnDate == this.txnDate &&
          other.description == this.description &&
          other.categoryId == this.categoryId &&
          other.amount == this.amount &&
          other.customerId == this.customerId &&
          other.paymentAccountId == this.paymentAccountId &&
          other.reference == this.reference &&
          other.notes == this.notes &&
          other.status == this.status &&
          other.journalEntryId == this.journalEntryId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class IncomeTransactionsCompanion extends UpdateCompanion<IncomeTransaction> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<DateTime> txnDate;
  final Value<String?> description;
  final Value<String> categoryId;
  final Value<int> amount;
  final Value<String?> customerId;
  final Value<String?> paymentAccountId;
  final Value<String?> reference;
  final Value<String?> notes;
  final Value<String> status;
  final Value<String?> journalEntryId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const IncomeTransactionsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.txnDate = const Value.absent(),
    this.description = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amount = const Value.absent(),
    this.customerId = const Value.absent(),
    this.paymentAccountId = const Value.absent(),
    this.reference = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.journalEntryId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IncomeTransactionsCompanion.insert({
    required String id,
    required String businessId,
    required DateTime txnDate,
    this.description = const Value.absent(),
    required String categoryId,
    required int amount,
    this.customerId = const Value.absent(),
    this.paymentAccountId = const Value.absent(),
    this.reference = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.journalEntryId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       txnDate = Value(txnDate),
       categoryId = Value(categoryId),
       amount = Value(amount);
  static Insertable<IncomeTransaction> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<DateTime>? txnDate,
    Expression<String>? description,
    Expression<String>? categoryId,
    Expression<int>? amount,
    Expression<String>? customerId,
    Expression<String>? paymentAccountId,
    Expression<String>? reference,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<String>? journalEntryId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (txnDate != null) 'txn_date': txnDate,
      if (description != null) 'description': description,
      if (categoryId != null) 'category_id': categoryId,
      if (amount != null) 'amount': amount,
      if (customerId != null) 'customer_id': customerId,
      if (paymentAccountId != null) 'payment_account_id': paymentAccountId,
      if (reference != null) 'reference': reference,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (journalEntryId != null) 'journal_entry_id': journalEntryId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IncomeTransactionsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<DateTime>? txnDate,
    Value<String?>? description,
    Value<String>? categoryId,
    Value<int>? amount,
    Value<String?>? customerId,
    Value<String?>? paymentAccountId,
    Value<String?>? reference,
    Value<String?>? notes,
    Value<String>? status,
    Value<String?>? journalEntryId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return IncomeTransactionsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      txnDate: txnDate ?? this.txnDate,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      customerId: customerId ?? this.customerId,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (txnDate.present) {
      map['txn_date'] = Variable<DateTime>(txnDate.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (paymentAccountId.present) {
      map['payment_account_id'] = Variable<String>(paymentAccountId.value);
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (journalEntryId.present) {
      map['journal_entry_id'] = Variable<String>(journalEntryId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IncomeTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('txnDate: $txnDate, ')
          ..write('description: $description, ')
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('customerId: $customerId, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('reference: $reference, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('journalEntryId: $journalEntryId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReceivablePaymentsTable extends ReceivablePayments
    with TableInfo<$ReceivablePaymentsTable, ReceivablePayment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReceivablePaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES customers (id)',
    ),
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentAccountIdMeta = const VerificationMeta(
    'paymentAccountId',
  );
  @override
  late final GeneratedColumn<String> paymentAccountId = GeneratedColumn<String>(
    'payment_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _paymentDateMeta = const VerificationMeta(
    'paymentDate',
  );
  @override
  late final GeneratedColumn<DateTime> paymentDate = GeneratedColumn<DateTime>(
    'payment_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    customerId,
    amount,
    paymentAccountId,
    paymentDate,
    notes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'receivable_payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReceivablePayment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_customerIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('payment_account_id')) {
      context.handle(
        _paymentAccountIdMeta,
        paymentAccountId.isAcceptableOrUnknown(
          data['payment_account_id']!,
          _paymentAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentAccountIdMeta);
    }
    if (data.containsKey('payment_date')) {
      context.handle(
        _paymentDateMeta,
        paymentDate.isAcceptableOrUnknown(
          data['payment_date']!,
          _paymentDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentDateMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReceivablePayment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReceivablePayment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      paymentAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_account_id'],
      )!,
      paymentDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}payment_date'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ReceivablePaymentsTable createAlias(String alias) {
    return $ReceivablePaymentsTable(attachedDatabase, alias);
  }
}

class ReceivablePayment extends DataClass
    implements Insertable<ReceivablePayment> {
  final String id;
  final String businessId;
  final String customerId;
  final int amount;
  final String paymentAccountId;
  final DateTime paymentDate;
  final String? notes;
  final DateTime createdAt;
  const ReceivablePayment({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.amount,
    required this.paymentAccountId,
    required this.paymentDate,
    this.notes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['customer_id'] = Variable<String>(customerId);
    map['amount'] = Variable<int>(amount);
    map['payment_account_id'] = Variable<String>(paymentAccountId);
    map['payment_date'] = Variable<DateTime>(paymentDate);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ReceivablePaymentsCompanion toCompanion(bool nullToAbsent) {
    return ReceivablePaymentsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      customerId: Value(customerId),
      amount: Value(amount),
      paymentAccountId: Value(paymentAccountId),
      paymentDate: Value(paymentDate),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
    );
  }

  factory ReceivablePayment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReceivablePayment(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      customerId: serializer.fromJson<String>(json['customerId']),
      amount: serializer.fromJson<int>(json['amount']),
      paymentAccountId: serializer.fromJson<String>(json['paymentAccountId']),
      paymentDate: serializer.fromJson<DateTime>(json['paymentDate']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'customerId': serializer.toJson<String>(customerId),
      'amount': serializer.toJson<int>(amount),
      'paymentAccountId': serializer.toJson<String>(paymentAccountId),
      'paymentDate': serializer.toJson<DateTime>(paymentDate),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ReceivablePayment copyWith({
    String? id,
    String? businessId,
    String? customerId,
    int? amount,
    String? paymentAccountId,
    DateTime? paymentDate,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
  }) => ReceivablePayment(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    customerId: customerId ?? this.customerId,
    amount: amount ?? this.amount,
    paymentAccountId: paymentAccountId ?? this.paymentAccountId,
    paymentDate: paymentDate ?? this.paymentDate,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
  );
  ReceivablePayment copyWithCompanion(ReceivablePaymentsCompanion data) {
    return ReceivablePayment(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      amount: data.amount.present ? data.amount.value : this.amount,
      paymentAccountId: data.paymentAccountId.present
          ? data.paymentAccountId.value
          : this.paymentAccountId,
      paymentDate: data.paymentDate.present
          ? data.paymentDate.value
          : this.paymentDate,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReceivablePayment(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('customerId: $customerId, ')
          ..write('amount: $amount, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    customerId,
    amount,
    paymentAccountId,
    paymentDate,
    notes,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReceivablePayment &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.customerId == this.customerId &&
          other.amount == this.amount &&
          other.paymentAccountId == this.paymentAccountId &&
          other.paymentDate == this.paymentDate &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt);
}

class ReceivablePaymentsCompanion extends UpdateCompanion<ReceivablePayment> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> customerId;
  final Value<int> amount;
  final Value<String> paymentAccountId;
  final Value<DateTime> paymentDate;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ReceivablePaymentsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.amount = const Value.absent(),
    this.paymentAccountId = const Value.absent(),
    this.paymentDate = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReceivablePaymentsCompanion.insert({
    required String id,
    required String businessId,
    required String customerId,
    required int amount,
    required String paymentAccountId,
    required DateTime paymentDate,
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       customerId = Value(customerId),
       amount = Value(amount),
       paymentAccountId = Value(paymentAccountId),
       paymentDate = Value(paymentDate);
  static Insertable<ReceivablePayment> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? customerId,
    Expression<int>? amount,
    Expression<String>? paymentAccountId,
    Expression<DateTime>? paymentDate,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (customerId != null) 'customer_id': customerId,
      if (amount != null) 'amount': amount,
      if (paymentAccountId != null) 'payment_account_id': paymentAccountId,
      if (paymentDate != null) 'payment_date': paymentDate,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReceivablePaymentsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? customerId,
    Value<int>? amount,
    Value<String>? paymentAccountId,
    Value<DateTime>? paymentDate,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ReceivablePaymentsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      customerId: customerId ?? this.customerId,
      amount: amount ?? this.amount,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      paymentDate: paymentDate ?? this.paymentDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (paymentAccountId.present) {
      map['payment_account_id'] = Variable<String>(paymentAccountId.value);
    }
    if (paymentDate.present) {
      map['payment_date'] = Variable<DateTime>(paymentDate.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReceivablePaymentsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('customerId: $customerId, ')
          ..write('amount: $amount, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SuppliersTable extends Suppliers
    with TableInfo<$SuppliersTable, Supplier> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SuppliersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    name,
    phone,
    address,
    notes,
    isActive,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'suppliers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Supplier> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Supplier map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Supplier(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SuppliersTable createAlias(String alias) {
    return $SuppliersTable(attachedDatabase, alias);
  }
}

class Supplier extends DataClass implements Insertable<Supplier> {
  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final String? address;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  const Supplier({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    this.address,
    this.notes,
    required this.isActive,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SuppliersCompanion toCompanion(bool nullToAbsent) {
    return SuppliersCompanion(
      id: Value(id),
      businessId: Value(businessId),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory Supplier.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Supplier(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      address: serializer.fromJson<String?>(json['address']),
      notes: serializer.fromJson<String?>(json['notes']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'address': serializer.toJson<String?>(address),
      'notes': serializer.toJson<String?>(notes),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Supplier copyWith({
    String? id,
    String? businessId,
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> address = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
  }) => Supplier(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    address: address.present ? address.value : this.address,
    notes: notes.present ? notes.value : this.notes,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
  );
  Supplier copyWithCompanion(SuppliersCompanion data) {
    return Supplier(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      address: data.address.present ? data.address.value : this.address,
      notes: data.notes.present ? data.notes.value : this.notes,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Supplier(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('address: $address, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    name,
    phone,
    address,
    notes,
    isActive,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Supplier &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.address == this.address &&
          other.notes == this.notes &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class SuppliersCompanion extends UpdateCompanion<Supplier> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> address;
  final Value<String?> notes;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SuppliersCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.address = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SuppliersCompanion.insert({
    required String id,
    required String businessId,
    required String name,
    this.phone = const Value.absent(),
    this.address = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       name = Value(name);
  static Insertable<Supplier> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? address,
    Expression<String>? notes,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (notes != null) 'notes': notes,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SuppliersCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? name,
    Value<String?>? phone,
    Value<String?>? address,
    Value<String?>? notes,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SuppliersCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SuppliersCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('address: $address, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SupplierPurchasesTable extends SupplierPurchases
    with TableInfo<$SupplierPurchasesTable, SupplierPurchase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SupplierPurchasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _supplierIdMeta = const VerificationMeta(
    'supplierId',
  );
  @override
  late final GeneratedColumn<String> supplierId = GeneratedColumn<String>(
    'supplier_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES suppliers (id)',
    ),
  );
  static const VerificationMeta _purchaseDateMeta = const VerificationMeta(
    'purchaseDate',
  );
  @override
  late final GeneratedColumn<DateTime> purchaseDate = GeneratedColumn<DateTime>(
    'purchase_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isOnCreditMeta = const VerificationMeta(
    'isOnCredit',
  );
  @override
  late final GeneratedColumn<bool> isOnCredit = GeneratedColumn<bool>(
    'is_on_credit',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_on_credit" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _paymentAccountIdMeta = const VerificationMeta(
    'paymentAccountId',
  );
  @override
  late final GeneratedColumn<String> paymentAccountId = GeneratedColumn<String>(
    'payment_account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('completed'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    supplierId,
    purchaseDate,
    amount,
    isOnCredit,
    paymentAccountId,
    notes,
    status,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'supplier_purchases';
  @override
  VerificationContext validateIntegrity(
    Insertable<SupplierPurchase> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('supplier_id')) {
      context.handle(
        _supplierIdMeta,
        supplierId.isAcceptableOrUnknown(data['supplier_id']!, _supplierIdMeta),
      );
    } else if (isInserting) {
      context.missing(_supplierIdMeta);
    }
    if (data.containsKey('purchase_date')) {
      context.handle(
        _purchaseDateMeta,
        purchaseDate.isAcceptableOrUnknown(
          data['purchase_date']!,
          _purchaseDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_purchaseDateMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('is_on_credit')) {
      context.handle(
        _isOnCreditMeta,
        isOnCredit.isAcceptableOrUnknown(
          data['is_on_credit']!,
          _isOnCreditMeta,
        ),
      );
    }
    if (data.containsKey('payment_account_id')) {
      context.handle(
        _paymentAccountIdMeta,
        paymentAccountId.isAcceptableOrUnknown(
          data['payment_account_id']!,
          _paymentAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SupplierPurchase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SupplierPurchase(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      supplierId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supplier_id'],
      )!,
      purchaseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}purchase_date'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      isOnCredit: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_on_credit'],
      )!,
      paymentAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_account_id'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SupplierPurchasesTable createAlias(String alias) {
    return $SupplierPurchasesTable(attachedDatabase, alias);
  }
}

class SupplierPurchase extends DataClass
    implements Insertable<SupplierPurchase> {
  final String id;
  final String businessId;
  final String supplierId;
  final DateTime purchaseDate;
  final int amount;
  final bool isOnCredit;
  final String? paymentAccountId;
  final String? notes;
  final String status;
  final DateTime createdAt;
  const SupplierPurchase({
    required this.id,
    required this.businessId,
    required this.supplierId,
    required this.purchaseDate,
    required this.amount,
    required this.isOnCredit,
    this.paymentAccountId,
    this.notes,
    required this.status,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['supplier_id'] = Variable<String>(supplierId);
    map['purchase_date'] = Variable<DateTime>(purchaseDate);
    map['amount'] = Variable<int>(amount);
    map['is_on_credit'] = Variable<bool>(isOnCredit);
    if (!nullToAbsent || paymentAccountId != null) {
      map['payment_account_id'] = Variable<String>(paymentAccountId);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SupplierPurchasesCompanion toCompanion(bool nullToAbsent) {
    return SupplierPurchasesCompanion(
      id: Value(id),
      businessId: Value(businessId),
      supplierId: Value(supplierId),
      purchaseDate: Value(purchaseDate),
      amount: Value(amount),
      isOnCredit: Value(isOnCredit),
      paymentAccountId: paymentAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentAccountId),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      status: Value(status),
      createdAt: Value(createdAt),
    );
  }

  factory SupplierPurchase.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SupplierPurchase(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      supplierId: serializer.fromJson<String>(json['supplierId']),
      purchaseDate: serializer.fromJson<DateTime>(json['purchaseDate']),
      amount: serializer.fromJson<int>(json['amount']),
      isOnCredit: serializer.fromJson<bool>(json['isOnCredit']),
      paymentAccountId: serializer.fromJson<String?>(json['paymentAccountId']),
      notes: serializer.fromJson<String?>(json['notes']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'supplierId': serializer.toJson<String>(supplierId),
      'purchaseDate': serializer.toJson<DateTime>(purchaseDate),
      'amount': serializer.toJson<int>(amount),
      'isOnCredit': serializer.toJson<bool>(isOnCredit),
      'paymentAccountId': serializer.toJson<String?>(paymentAccountId),
      'notes': serializer.toJson<String?>(notes),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SupplierPurchase copyWith({
    String? id,
    String? businessId,
    String? supplierId,
    DateTime? purchaseDate,
    int? amount,
    bool? isOnCredit,
    Value<String?> paymentAccountId = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? status,
    DateTime? createdAt,
  }) => SupplierPurchase(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    supplierId: supplierId ?? this.supplierId,
    purchaseDate: purchaseDate ?? this.purchaseDate,
    amount: amount ?? this.amount,
    isOnCredit: isOnCredit ?? this.isOnCredit,
    paymentAccountId: paymentAccountId.present
        ? paymentAccountId.value
        : this.paymentAccountId,
    notes: notes.present ? notes.value : this.notes,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
  );
  SupplierPurchase copyWithCompanion(SupplierPurchasesCompanion data) {
    return SupplierPurchase(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      supplierId: data.supplierId.present
          ? data.supplierId.value
          : this.supplierId,
      purchaseDate: data.purchaseDate.present
          ? data.purchaseDate.value
          : this.purchaseDate,
      amount: data.amount.present ? data.amount.value : this.amount,
      isOnCredit: data.isOnCredit.present
          ? data.isOnCredit.value
          : this.isOnCredit,
      paymentAccountId: data.paymentAccountId.present
          ? data.paymentAccountId.value
          : this.paymentAccountId,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SupplierPurchase(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('supplierId: $supplierId, ')
          ..write('purchaseDate: $purchaseDate, ')
          ..write('amount: $amount, ')
          ..write('isOnCredit: $isOnCredit, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    supplierId,
    purchaseDate,
    amount,
    isOnCredit,
    paymentAccountId,
    notes,
    status,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SupplierPurchase &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.supplierId == this.supplierId &&
          other.purchaseDate == this.purchaseDate &&
          other.amount == this.amount &&
          other.isOnCredit == this.isOnCredit &&
          other.paymentAccountId == this.paymentAccountId &&
          other.notes == this.notes &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class SupplierPurchasesCompanion extends UpdateCompanion<SupplierPurchase> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> supplierId;
  final Value<DateTime> purchaseDate;
  final Value<int> amount;
  final Value<bool> isOnCredit;
  final Value<String?> paymentAccountId;
  final Value<String?> notes;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SupplierPurchasesCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.supplierId = const Value.absent(),
    this.purchaseDate = const Value.absent(),
    this.amount = const Value.absent(),
    this.isOnCredit = const Value.absent(),
    this.paymentAccountId = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SupplierPurchasesCompanion.insert({
    required String id,
    required String businessId,
    required String supplierId,
    required DateTime purchaseDate,
    required int amount,
    this.isOnCredit = const Value.absent(),
    this.paymentAccountId = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       supplierId = Value(supplierId),
       purchaseDate = Value(purchaseDate),
       amount = Value(amount);
  static Insertable<SupplierPurchase> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? supplierId,
    Expression<DateTime>? purchaseDate,
    Expression<int>? amount,
    Expression<bool>? isOnCredit,
    Expression<String>? paymentAccountId,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (supplierId != null) 'supplier_id': supplierId,
      if (purchaseDate != null) 'purchase_date': purchaseDate,
      if (amount != null) 'amount': amount,
      if (isOnCredit != null) 'is_on_credit': isOnCredit,
      if (paymentAccountId != null) 'payment_account_id': paymentAccountId,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SupplierPurchasesCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? supplierId,
    Value<DateTime>? purchaseDate,
    Value<int>? amount,
    Value<bool>? isOnCredit,
    Value<String?>? paymentAccountId,
    Value<String?>? notes,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SupplierPurchasesCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      supplierId: supplierId ?? this.supplierId,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      amount: amount ?? this.amount,
      isOnCredit: isOnCredit ?? this.isOnCredit,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (supplierId.present) {
      map['supplier_id'] = Variable<String>(supplierId.value);
    }
    if (purchaseDate.present) {
      map['purchase_date'] = Variable<DateTime>(purchaseDate.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (isOnCredit.present) {
      map['is_on_credit'] = Variable<bool>(isOnCredit.value);
    }
    if (paymentAccountId.present) {
      map['payment_account_id'] = Variable<String>(paymentAccountId.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SupplierPurchasesCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('supplierId: $supplierId, ')
          ..write('purchaseDate: $purchaseDate, ')
          ..write('amount: $amount, ')
          ..write('isOnCredit: $isOnCredit, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PayablePaymentsTable extends PayablePayments
    with TableInfo<$PayablePaymentsTable, PayablePayment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PayablePaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _supplierIdMeta = const VerificationMeta(
    'supplierId',
  );
  @override
  late final GeneratedColumn<String> supplierId = GeneratedColumn<String>(
    'supplier_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES suppliers (id)',
    ),
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentAccountIdMeta = const VerificationMeta(
    'paymentAccountId',
  );
  @override
  late final GeneratedColumn<String> paymentAccountId = GeneratedColumn<String>(
    'payment_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _paymentDateMeta = const VerificationMeta(
    'paymentDate',
  );
  @override
  late final GeneratedColumn<DateTime> paymentDate = GeneratedColumn<DateTime>(
    'payment_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    supplierId,
    amount,
    paymentAccountId,
    paymentDate,
    notes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payable_payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<PayablePayment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('supplier_id')) {
      context.handle(
        _supplierIdMeta,
        supplierId.isAcceptableOrUnknown(data['supplier_id']!, _supplierIdMeta),
      );
    } else if (isInserting) {
      context.missing(_supplierIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('payment_account_id')) {
      context.handle(
        _paymentAccountIdMeta,
        paymentAccountId.isAcceptableOrUnknown(
          data['payment_account_id']!,
          _paymentAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentAccountIdMeta);
    }
    if (data.containsKey('payment_date')) {
      context.handle(
        _paymentDateMeta,
        paymentDate.isAcceptableOrUnknown(
          data['payment_date']!,
          _paymentDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentDateMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PayablePayment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PayablePayment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      supplierId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supplier_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      paymentAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_account_id'],
      )!,
      paymentDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}payment_date'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PayablePaymentsTable createAlias(String alias) {
    return $PayablePaymentsTable(attachedDatabase, alias);
  }
}

class PayablePayment extends DataClass implements Insertable<PayablePayment> {
  final String id;
  final String businessId;
  final String supplierId;
  final int amount;
  final String paymentAccountId;
  final DateTime paymentDate;
  final String? notes;
  final DateTime createdAt;
  const PayablePayment({
    required this.id,
    required this.businessId,
    required this.supplierId,
    required this.amount,
    required this.paymentAccountId,
    required this.paymentDate,
    this.notes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['supplier_id'] = Variable<String>(supplierId);
    map['amount'] = Variable<int>(amount);
    map['payment_account_id'] = Variable<String>(paymentAccountId);
    map['payment_date'] = Variable<DateTime>(paymentDate);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PayablePaymentsCompanion toCompanion(bool nullToAbsent) {
    return PayablePaymentsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      supplierId: Value(supplierId),
      amount: Value(amount),
      paymentAccountId: Value(paymentAccountId),
      paymentDate: Value(paymentDate),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
    );
  }

  factory PayablePayment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PayablePayment(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      supplierId: serializer.fromJson<String>(json['supplierId']),
      amount: serializer.fromJson<int>(json['amount']),
      paymentAccountId: serializer.fromJson<String>(json['paymentAccountId']),
      paymentDate: serializer.fromJson<DateTime>(json['paymentDate']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'supplierId': serializer.toJson<String>(supplierId),
      'amount': serializer.toJson<int>(amount),
      'paymentAccountId': serializer.toJson<String>(paymentAccountId),
      'paymentDate': serializer.toJson<DateTime>(paymentDate),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PayablePayment copyWith({
    String? id,
    String? businessId,
    String? supplierId,
    int? amount,
    String? paymentAccountId,
    DateTime? paymentDate,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
  }) => PayablePayment(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    supplierId: supplierId ?? this.supplierId,
    amount: amount ?? this.amount,
    paymentAccountId: paymentAccountId ?? this.paymentAccountId,
    paymentDate: paymentDate ?? this.paymentDate,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
  );
  PayablePayment copyWithCompanion(PayablePaymentsCompanion data) {
    return PayablePayment(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      supplierId: data.supplierId.present
          ? data.supplierId.value
          : this.supplierId,
      amount: data.amount.present ? data.amount.value : this.amount,
      paymentAccountId: data.paymentAccountId.present
          ? data.paymentAccountId.value
          : this.paymentAccountId,
      paymentDate: data.paymentDate.present
          ? data.paymentDate.value
          : this.paymentDate,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PayablePayment(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('supplierId: $supplierId, ')
          ..write('amount: $amount, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    supplierId,
    amount,
    paymentAccountId,
    paymentDate,
    notes,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PayablePayment &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.supplierId == this.supplierId &&
          other.amount == this.amount &&
          other.paymentAccountId == this.paymentAccountId &&
          other.paymentDate == this.paymentDate &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt);
}

class PayablePaymentsCompanion extends UpdateCompanion<PayablePayment> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> supplierId;
  final Value<int> amount;
  final Value<String> paymentAccountId;
  final Value<DateTime> paymentDate;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PayablePaymentsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.supplierId = const Value.absent(),
    this.amount = const Value.absent(),
    this.paymentAccountId = const Value.absent(),
    this.paymentDate = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PayablePaymentsCompanion.insert({
    required String id,
    required String businessId,
    required String supplierId,
    required int amount,
    required String paymentAccountId,
    required DateTime paymentDate,
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       supplierId = Value(supplierId),
       amount = Value(amount),
       paymentAccountId = Value(paymentAccountId),
       paymentDate = Value(paymentDate);
  static Insertable<PayablePayment> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? supplierId,
    Expression<int>? amount,
    Expression<String>? paymentAccountId,
    Expression<DateTime>? paymentDate,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (supplierId != null) 'supplier_id': supplierId,
      if (amount != null) 'amount': amount,
      if (paymentAccountId != null) 'payment_account_id': paymentAccountId,
      if (paymentDate != null) 'payment_date': paymentDate,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PayablePaymentsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? supplierId,
    Value<int>? amount,
    Value<String>? paymentAccountId,
    Value<DateTime>? paymentDate,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PayablePaymentsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      supplierId: supplierId ?? this.supplierId,
      amount: amount ?? this.amount,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      paymentDate: paymentDate ?? this.paymentDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (supplierId.present) {
      map['supplier_id'] = Variable<String>(supplierId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (paymentAccountId.present) {
      map['payment_account_id'] = Variable<String>(paymentAccountId.value);
    }
    if (paymentDate.present) {
      map['payment_date'] = Variable<DateTime>(paymentDate.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PayablePaymentsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('supplierId: $supplierId, ')
          ..write('amount: $amount, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpensesTable extends Expenses with TableInfo<$ExpensesTable, Expense> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpensesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _expenseDateMeta = const VerificationMeta(
    'expenseDate',
  );
  @override
  late final GeneratedColumn<DateTime> expenseDate = GeneratedColumn<DateTime>(
    'expense_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id)',
    ),
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentAccountIdMeta = const VerificationMeta(
    'paymentAccountId',
  );
  @override
  late final GeneratedColumn<String> paymentAccountId = GeneratedColumn<String>(
    'payment_account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _receiptPhotoPathMeta = const VerificationMeta(
    'receiptPhotoPath',
  );
  @override
  late final GeneratedColumn<String> receiptPhotoPath = GeneratedColumn<String>(
    'receipt_photo_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceMeta = const VerificationMeta(
    'reference',
  );
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
    'reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('completed'),
  );
  static const VerificationMeta _journalEntryIdMeta = const VerificationMeta(
    'journalEntryId',
  );
  @override
  late final GeneratedColumn<String> journalEntryId = GeneratedColumn<String>(
    'journal_entry_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES journal_entries (id)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    expenseDate,
    description,
    categoryId,
    amount,
    paymentAccountId,
    receiptPhotoPath,
    reference,
    notes,
    status,
    journalEntryId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(
    Insertable<Expense> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('expense_date')) {
      context.handle(
        _expenseDateMeta,
        expenseDate.isAcceptableOrUnknown(
          data['expense_date']!,
          _expenseDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expenseDateMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('payment_account_id')) {
      context.handle(
        _paymentAccountIdMeta,
        paymentAccountId.isAcceptableOrUnknown(
          data['payment_account_id']!,
          _paymentAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('receipt_photo_path')) {
      context.handle(
        _receiptPhotoPathMeta,
        receiptPhotoPath.isAcceptableOrUnknown(
          data['receipt_photo_path']!,
          _receiptPhotoPathMeta,
        ),
      );
    }
    if (data.containsKey('reference')) {
      context.handle(
        _referenceMeta,
        reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('journal_entry_id')) {
      context.handle(
        _journalEntryIdMeta,
        journalEntryId.isAcceptableOrUnknown(
          data['journal_entry_id']!,
          _journalEntryIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Expense map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Expense(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      expenseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expense_date'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      paymentAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_account_id'],
      ),
      receiptPhotoPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_photo_path'],
      ),
      reference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      journalEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}journal_entry_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ExpensesTable createAlias(String alias) {
    return $ExpensesTable(attachedDatabase, alias);
  }
}

class Expense extends DataClass implements Insertable<Expense> {
  final String id;
  final String businessId;
  final DateTime expenseDate;
  final String? description;
  final String categoryId;
  final int amount;
  final String? paymentAccountId;
  final String? receiptPhotoPath;
  final String? reference;
  final String? notes;
  final String status;
  final String? journalEntryId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Expense({
    required this.id,
    required this.businessId,
    required this.expenseDate,
    this.description,
    required this.categoryId,
    required this.amount,
    this.paymentAccountId,
    this.receiptPhotoPath,
    this.reference,
    this.notes,
    required this.status,
    this.journalEntryId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['expense_date'] = Variable<DateTime>(expenseDate);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['category_id'] = Variable<String>(categoryId);
    map['amount'] = Variable<int>(amount);
    if (!nullToAbsent || paymentAccountId != null) {
      map['payment_account_id'] = Variable<String>(paymentAccountId);
    }
    if (!nullToAbsent || receiptPhotoPath != null) {
      map['receipt_photo_path'] = Variable<String>(receiptPhotoPath);
    }
    if (!nullToAbsent || reference != null) {
      map['reference'] = Variable<String>(reference);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || journalEntryId != null) {
      map['journal_entry_id'] = Variable<String>(journalEntryId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ExpensesCompanion toCompanion(bool nullToAbsent) {
    return ExpensesCompanion(
      id: Value(id),
      businessId: Value(businessId),
      expenseDate: Value(expenseDate),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      categoryId: Value(categoryId),
      amount: Value(amount),
      paymentAccountId: paymentAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentAccountId),
      receiptPhotoPath: receiptPhotoPath == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptPhotoPath),
      reference: reference == null && nullToAbsent
          ? const Value.absent()
          : Value(reference),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      status: Value(status),
      journalEntryId: journalEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(journalEntryId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Expense.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Expense(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      expenseDate: serializer.fromJson<DateTime>(json['expenseDate']),
      description: serializer.fromJson<String?>(json['description']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      amount: serializer.fromJson<int>(json['amount']),
      paymentAccountId: serializer.fromJson<String?>(json['paymentAccountId']),
      receiptPhotoPath: serializer.fromJson<String?>(json['receiptPhotoPath']),
      reference: serializer.fromJson<String?>(json['reference']),
      notes: serializer.fromJson<String?>(json['notes']),
      status: serializer.fromJson<String>(json['status']),
      journalEntryId: serializer.fromJson<String?>(json['journalEntryId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'expenseDate': serializer.toJson<DateTime>(expenseDate),
      'description': serializer.toJson<String?>(description),
      'categoryId': serializer.toJson<String>(categoryId),
      'amount': serializer.toJson<int>(amount),
      'paymentAccountId': serializer.toJson<String?>(paymentAccountId),
      'receiptPhotoPath': serializer.toJson<String?>(receiptPhotoPath),
      'reference': serializer.toJson<String?>(reference),
      'notes': serializer.toJson<String?>(notes),
      'status': serializer.toJson<String>(status),
      'journalEntryId': serializer.toJson<String?>(journalEntryId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Expense copyWith({
    String? id,
    String? businessId,
    DateTime? expenseDate,
    Value<String?> description = const Value.absent(),
    String? categoryId,
    int? amount,
    Value<String?> paymentAccountId = const Value.absent(),
    Value<String?> receiptPhotoPath = const Value.absent(),
    Value<String?> reference = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? status,
    Value<String?> journalEntryId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Expense(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    expenseDate: expenseDate ?? this.expenseDate,
    description: description.present ? description.value : this.description,
    categoryId: categoryId ?? this.categoryId,
    amount: amount ?? this.amount,
    paymentAccountId: paymentAccountId.present
        ? paymentAccountId.value
        : this.paymentAccountId,
    receiptPhotoPath: receiptPhotoPath.present
        ? receiptPhotoPath.value
        : this.receiptPhotoPath,
    reference: reference.present ? reference.value : this.reference,
    notes: notes.present ? notes.value : this.notes,
    status: status ?? this.status,
    journalEntryId: journalEntryId.present
        ? journalEntryId.value
        : this.journalEntryId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Expense copyWithCompanion(ExpensesCompanion data) {
    return Expense(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      expenseDate: data.expenseDate.present
          ? data.expenseDate.value
          : this.expenseDate,
      description: data.description.present
          ? data.description.value
          : this.description,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      amount: data.amount.present ? data.amount.value : this.amount,
      paymentAccountId: data.paymentAccountId.present
          ? data.paymentAccountId.value
          : this.paymentAccountId,
      receiptPhotoPath: data.receiptPhotoPath.present
          ? data.receiptPhotoPath.value
          : this.receiptPhotoPath,
      reference: data.reference.present ? data.reference.value : this.reference,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
      journalEntryId: data.journalEntryId.present
          ? data.journalEntryId.value
          : this.journalEntryId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Expense(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('expenseDate: $expenseDate, ')
          ..write('description: $description, ')
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('receiptPhotoPath: $receiptPhotoPath, ')
          ..write('reference: $reference, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('journalEntryId: $journalEntryId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    expenseDate,
    description,
    categoryId,
    amount,
    paymentAccountId,
    receiptPhotoPath,
    reference,
    notes,
    status,
    journalEntryId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Expense &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.expenseDate == this.expenseDate &&
          other.description == this.description &&
          other.categoryId == this.categoryId &&
          other.amount == this.amount &&
          other.paymentAccountId == this.paymentAccountId &&
          other.receiptPhotoPath == this.receiptPhotoPath &&
          other.reference == this.reference &&
          other.notes == this.notes &&
          other.status == this.status &&
          other.journalEntryId == this.journalEntryId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ExpensesCompanion extends UpdateCompanion<Expense> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<DateTime> expenseDate;
  final Value<String?> description;
  final Value<String> categoryId;
  final Value<int> amount;
  final Value<String?> paymentAccountId;
  final Value<String?> receiptPhotoPath;
  final Value<String?> reference;
  final Value<String?> notes;
  final Value<String> status;
  final Value<String?> journalEntryId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ExpensesCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.expenseDate = const Value.absent(),
    this.description = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amount = const Value.absent(),
    this.paymentAccountId = const Value.absent(),
    this.receiptPhotoPath = const Value.absent(),
    this.reference = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.journalEntryId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpensesCompanion.insert({
    required String id,
    required String businessId,
    required DateTime expenseDate,
    this.description = const Value.absent(),
    required String categoryId,
    required int amount,
    this.paymentAccountId = const Value.absent(),
    this.receiptPhotoPath = const Value.absent(),
    this.reference = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.journalEntryId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       expenseDate = Value(expenseDate),
       categoryId = Value(categoryId),
       amount = Value(amount);
  static Insertable<Expense> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<DateTime>? expenseDate,
    Expression<String>? description,
    Expression<String>? categoryId,
    Expression<int>? amount,
    Expression<String>? paymentAccountId,
    Expression<String>? receiptPhotoPath,
    Expression<String>? reference,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<String>? journalEntryId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (expenseDate != null) 'expense_date': expenseDate,
      if (description != null) 'description': description,
      if (categoryId != null) 'category_id': categoryId,
      if (amount != null) 'amount': amount,
      if (paymentAccountId != null) 'payment_account_id': paymentAccountId,
      if (receiptPhotoPath != null) 'receipt_photo_path': receiptPhotoPath,
      if (reference != null) 'reference': reference,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (journalEntryId != null) 'journal_entry_id': journalEntryId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpensesCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<DateTime>? expenseDate,
    Value<String?>? description,
    Value<String>? categoryId,
    Value<int>? amount,
    Value<String?>? paymentAccountId,
    Value<String?>? receiptPhotoPath,
    Value<String?>? reference,
    Value<String?>? notes,
    Value<String>? status,
    Value<String?>? journalEntryId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ExpensesCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      expenseDate: expenseDate ?? this.expenseDate,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      receiptPhotoPath: receiptPhotoPath ?? this.receiptPhotoPath,
      reference: reference ?? this.reference,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (expenseDate.present) {
      map['expense_date'] = Variable<DateTime>(expenseDate.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (paymentAccountId.present) {
      map['payment_account_id'] = Variable<String>(paymentAccountId.value);
    }
    if (receiptPhotoPath.present) {
      map['receipt_photo_path'] = Variable<String>(receiptPhotoPath.value);
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (journalEntryId.present) {
      map['journal_entry_id'] = Variable<String>(journalEntryId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpensesCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('expenseDate: $expenseDate, ')
          ..write('description: $description, ')
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('paymentAccountId: $paymentAccountId, ')
          ..write('receiptPhotoPath: $receiptPhotoPath, ')
          ..write('reference: $reference, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('journalEntryId: $journalEntryId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SuppliesTable extends Supplies with TableInfo<$SuppliesTable, Supply> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SuppliesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitQuantityMeta = const VerificationMeta(
    'unitQuantity',
  );
  @override
  late final GeneratedColumn<double> unitQuantity = GeneratedColumn<double>(
    'unit_quantity',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastStoreNameMeta = const VerificationMeta(
    'lastStoreName',
  );
  @override
  late final GeneratedColumn<String> lastStoreName = GeneratedColumn<String>(
    'last_store_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastStoreAddressMeta = const VerificationMeta(
    'lastStoreAddress',
  );
  @override
  late final GeneratedColumn<String> lastStoreAddress = GeneratedColumn<String>(
    'last_store_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currentPriceMeta = const VerificationMeta(
    'currentPrice',
  );
  @override
  late final GeneratedColumn<int> currentPrice = GeneratedColumn<int>(
    'current_price',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    name,
    brand,
    unitQuantity,
    unit,
    lastStoreName,
    lastStoreAddress,
    currentPrice,
    notes,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'supplies';
  @override
  VerificationContext validateIntegrity(
    Insertable<Supply> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    }
    if (data.containsKey('unit_quantity')) {
      context.handle(
        _unitQuantityMeta,
        unitQuantity.isAcceptableOrUnknown(
          data['unit_quantity']!,
          _unitQuantityMeta,
        ),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('last_store_name')) {
      context.handle(
        _lastStoreNameMeta,
        lastStoreName.isAcceptableOrUnknown(
          data['last_store_name']!,
          _lastStoreNameMeta,
        ),
      );
    }
    if (data.containsKey('last_store_address')) {
      context.handle(
        _lastStoreAddressMeta,
        lastStoreAddress.isAcceptableOrUnknown(
          data['last_store_address']!,
          _lastStoreAddressMeta,
        ),
      );
    }
    if (data.containsKey('current_price')) {
      context.handle(
        _currentPriceMeta,
        currentPrice.isAcceptableOrUnknown(
          data['current_price']!,
          _currentPriceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentPriceMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Supply map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Supply(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      ),
      unitQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}unit_quantity'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      lastStoreName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_store_name'],
      ),
      lastStoreAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_store_address'],
      ),
      currentPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_price'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SuppliesTable createAlias(String alias) {
    return $SuppliesTable(attachedDatabase, alias);
  }
}

class Supply extends DataClass implements Insertable<Supply> {
  final String id;
  final String businessId;
  final String name;
  final String? brand;
  final double? unitQuantity;
  final String? unit;
  final String? lastStoreName;
  final String? lastStoreAddress;
  final int currentPrice;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Supply({
    required this.id,
    required this.businessId,
    required this.name,
    this.brand,
    this.unitQuantity,
    this.unit,
    this.lastStoreName,
    this.lastStoreAddress,
    required this.currentPrice,
    this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || brand != null) {
      map['brand'] = Variable<String>(brand);
    }
    if (!nullToAbsent || unitQuantity != null) {
      map['unit_quantity'] = Variable<double>(unitQuantity);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    if (!nullToAbsent || lastStoreName != null) {
      map['last_store_name'] = Variable<String>(lastStoreName);
    }
    if (!nullToAbsent || lastStoreAddress != null) {
      map['last_store_address'] = Variable<String>(lastStoreAddress);
    }
    map['current_price'] = Variable<int>(currentPrice);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SuppliesCompanion toCompanion(bool nullToAbsent) {
    return SuppliesCompanion(
      id: Value(id),
      businessId: Value(businessId),
      name: Value(name),
      brand: brand == null && nullToAbsent
          ? const Value.absent()
          : Value(brand),
      unitQuantity: unitQuantity == null && nullToAbsent
          ? const Value.absent()
          : Value(unitQuantity),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      lastStoreName: lastStoreName == null && nullToAbsent
          ? const Value.absent()
          : Value(lastStoreName),
      lastStoreAddress: lastStoreAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(lastStoreAddress),
      currentPrice: Value(currentPrice),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Supply.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Supply(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      name: serializer.fromJson<String>(json['name']),
      brand: serializer.fromJson<String?>(json['brand']),
      unitQuantity: serializer.fromJson<double?>(json['unitQuantity']),
      unit: serializer.fromJson<String?>(json['unit']),
      lastStoreName: serializer.fromJson<String?>(json['lastStoreName']),
      lastStoreAddress: serializer.fromJson<String?>(json['lastStoreAddress']),
      currentPrice: serializer.fromJson<int>(json['currentPrice']),
      notes: serializer.fromJson<String?>(json['notes']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'name': serializer.toJson<String>(name),
      'brand': serializer.toJson<String?>(brand),
      'unitQuantity': serializer.toJson<double?>(unitQuantity),
      'unit': serializer.toJson<String?>(unit),
      'lastStoreName': serializer.toJson<String?>(lastStoreName),
      'lastStoreAddress': serializer.toJson<String?>(lastStoreAddress),
      'currentPrice': serializer.toJson<int>(currentPrice),
      'notes': serializer.toJson<String?>(notes),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Supply copyWith({
    String? id,
    String? businessId,
    String? name,
    Value<String?> brand = const Value.absent(),
    Value<double?> unitQuantity = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    Value<String?> lastStoreName = const Value.absent(),
    Value<String?> lastStoreAddress = const Value.absent(),
    int? currentPrice,
    Value<String?> notes = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Supply(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    name: name ?? this.name,
    brand: brand.present ? brand.value : this.brand,
    unitQuantity: unitQuantity.present ? unitQuantity.value : this.unitQuantity,
    unit: unit.present ? unit.value : this.unit,
    lastStoreName: lastStoreName.present
        ? lastStoreName.value
        : this.lastStoreName,
    lastStoreAddress: lastStoreAddress.present
        ? lastStoreAddress.value
        : this.lastStoreAddress,
    currentPrice: currentPrice ?? this.currentPrice,
    notes: notes.present ? notes.value : this.notes,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Supply copyWithCompanion(SuppliesCompanion data) {
    return Supply(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      name: data.name.present ? data.name.value : this.name,
      brand: data.brand.present ? data.brand.value : this.brand,
      unitQuantity: data.unitQuantity.present
          ? data.unitQuantity.value
          : this.unitQuantity,
      unit: data.unit.present ? data.unit.value : this.unit,
      lastStoreName: data.lastStoreName.present
          ? data.lastStoreName.value
          : this.lastStoreName,
      lastStoreAddress: data.lastStoreAddress.present
          ? data.lastStoreAddress.value
          : this.lastStoreAddress,
      currentPrice: data.currentPrice.present
          ? data.currentPrice.value
          : this.currentPrice,
      notes: data.notes.present ? data.notes.value : this.notes,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Supply(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('unitQuantity: $unitQuantity, ')
          ..write('unit: $unit, ')
          ..write('lastStoreName: $lastStoreName, ')
          ..write('lastStoreAddress: $lastStoreAddress, ')
          ..write('currentPrice: $currentPrice, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    name,
    brand,
    unitQuantity,
    unit,
    lastStoreName,
    lastStoreAddress,
    currentPrice,
    notes,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Supply &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.name == this.name &&
          other.brand == this.brand &&
          other.unitQuantity == this.unitQuantity &&
          other.unit == this.unit &&
          other.lastStoreName == this.lastStoreName &&
          other.lastStoreAddress == this.lastStoreAddress &&
          other.currentPrice == this.currentPrice &&
          other.notes == this.notes &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SuppliesCompanion extends UpdateCompanion<Supply> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> name;
  final Value<String?> brand;
  final Value<double?> unitQuantity;
  final Value<String?> unit;
  final Value<String?> lastStoreName;
  final Value<String?> lastStoreAddress;
  final Value<int> currentPrice;
  final Value<String?> notes;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SuppliesCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.name = const Value.absent(),
    this.brand = const Value.absent(),
    this.unitQuantity = const Value.absent(),
    this.unit = const Value.absent(),
    this.lastStoreName = const Value.absent(),
    this.lastStoreAddress = const Value.absent(),
    this.currentPrice = const Value.absent(),
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SuppliesCompanion.insert({
    required String id,
    required String businessId,
    required String name,
    this.brand = const Value.absent(),
    this.unitQuantity = const Value.absent(),
    this.unit = const Value.absent(),
    this.lastStoreName = const Value.absent(),
    this.lastStoreAddress = const Value.absent(),
    required int currentPrice,
    this.notes = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       name = Value(name),
       currentPrice = Value(currentPrice);
  static Insertable<Supply> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? name,
    Expression<String>? brand,
    Expression<double>? unitQuantity,
    Expression<String>? unit,
    Expression<String>? lastStoreName,
    Expression<String>? lastStoreAddress,
    Expression<int>? currentPrice,
    Expression<String>? notes,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (name != null) 'name': name,
      if (brand != null) 'brand': brand,
      if (unitQuantity != null) 'unit_quantity': unitQuantity,
      if (unit != null) 'unit': unit,
      if (lastStoreName != null) 'last_store_name': lastStoreName,
      if (lastStoreAddress != null) 'last_store_address': lastStoreAddress,
      if (currentPrice != null) 'current_price': currentPrice,
      if (notes != null) 'notes': notes,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SuppliesCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? name,
    Value<String?>? brand,
    Value<double?>? unitQuantity,
    Value<String?>? unit,
    Value<String?>? lastStoreName,
    Value<String?>? lastStoreAddress,
    Value<int>? currentPrice,
    Value<String?>? notes,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SuppliesCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      unitQuantity: unitQuantity ?? this.unitQuantity,
      unit: unit ?? this.unit,
      lastStoreName: lastStoreName ?? this.lastStoreName,
      lastStoreAddress: lastStoreAddress ?? this.lastStoreAddress,
      currentPrice: currentPrice ?? this.currentPrice,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (unitQuantity.present) {
      map['unit_quantity'] = Variable<double>(unitQuantity.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (lastStoreName.present) {
      map['last_store_name'] = Variable<String>(lastStoreName.value);
    }
    if (lastStoreAddress.present) {
      map['last_store_address'] = Variable<String>(lastStoreAddress.value);
    }
    if (currentPrice.present) {
      map['current_price'] = Variable<int>(currentPrice.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SuppliesCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('unitQuantity: $unitQuantity, ')
          ..write('unit: $unit, ')
          ..write('lastStoreName: $lastStoreName, ')
          ..write('lastStoreAddress: $lastStoreAddress, ')
          ..write('currentPrice: $currentPrice, ')
          ..write('notes: $notes, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SupplyPriceHistoryTable extends SupplyPriceHistory
    with TableInfo<$SupplyPriceHistoryTable, SupplyPriceHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SupplyPriceHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _supplyIdMeta = const VerificationMeta(
    'supplyId',
  );
  @override
  late final GeneratedColumn<String> supplyId = GeneratedColumn<String>(
    'supply_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES supplies (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<int> price = GeneratedColumn<int>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storeNameMeta = const VerificationMeta(
    'storeName',
  );
  @override
  late final GeneratedColumn<String> storeName = GeneratedColumn<String>(
    'store_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storeAddressMeta = const VerificationMeta(
    'storeAddress',
  );
  @override
  late final GeneratedColumn<String> storeAddress = GeneratedColumn<String>(
    'store_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _supplierIdMeta = const VerificationMeta(
    'supplierId',
  );
  @override
  late final GeneratedColumn<String> supplierId = GeneratedColumn<String>(
    'supplier_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES suppliers (id)',
    ),
  );
  static const VerificationMeta _recordedDateMeta = const VerificationMeta(
    'recordedDate',
  );
  @override
  late final GeneratedColumn<DateTime> recordedDate = GeneratedColumn<DateTime>(
    'recorded_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    supplyId,
    price,
    storeName,
    storeAddress,
    supplierId,
    recordedDate,
    notes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'supply_price_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<SupplyPriceHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('supply_id')) {
      context.handle(
        _supplyIdMeta,
        supplyId.isAcceptableOrUnknown(data['supply_id']!, _supplyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_supplyIdMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('store_name')) {
      context.handle(
        _storeNameMeta,
        storeName.isAcceptableOrUnknown(data['store_name']!, _storeNameMeta),
      );
    } else if (isInserting) {
      context.missing(_storeNameMeta);
    }
    if (data.containsKey('store_address')) {
      context.handle(
        _storeAddressMeta,
        storeAddress.isAcceptableOrUnknown(
          data['store_address']!,
          _storeAddressMeta,
        ),
      );
    }
    if (data.containsKey('supplier_id')) {
      context.handle(
        _supplierIdMeta,
        supplierId.isAcceptableOrUnknown(data['supplier_id']!, _supplierIdMeta),
      );
    }
    if (data.containsKey('recorded_date')) {
      context.handle(
        _recordedDateMeta,
        recordedDate.isAcceptableOrUnknown(
          data['recorded_date']!,
          _recordedDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordedDateMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SupplyPriceHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SupplyPriceHistoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      supplyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supply_id'],
      )!,
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price'],
      )!,
      storeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_name'],
      )!,
      storeAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_address'],
      ),
      supplierId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supplier_id'],
      ),
      recordedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recorded_date'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SupplyPriceHistoryTable createAlias(String alias) {
    return $SupplyPriceHistoryTable(attachedDatabase, alias);
  }
}

class SupplyPriceHistoryData extends DataClass
    implements Insertable<SupplyPriceHistoryData> {
  final String id;
  final String supplyId;
  final int price;
  final String storeName;
  final String? storeAddress;
  final String? supplierId;
  final DateTime recordedDate;
  final String? notes;
  final DateTime createdAt;
  const SupplyPriceHistoryData({
    required this.id,
    required this.supplyId,
    required this.price,
    required this.storeName,
    this.storeAddress,
    this.supplierId,
    required this.recordedDate,
    this.notes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['supply_id'] = Variable<String>(supplyId);
    map['price'] = Variable<int>(price);
    map['store_name'] = Variable<String>(storeName);
    if (!nullToAbsent || storeAddress != null) {
      map['store_address'] = Variable<String>(storeAddress);
    }
    if (!nullToAbsent || supplierId != null) {
      map['supplier_id'] = Variable<String>(supplierId);
    }
    map['recorded_date'] = Variable<DateTime>(recordedDate);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SupplyPriceHistoryCompanion toCompanion(bool nullToAbsent) {
    return SupplyPriceHistoryCompanion(
      id: Value(id),
      supplyId: Value(supplyId),
      price: Value(price),
      storeName: Value(storeName),
      storeAddress: storeAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(storeAddress),
      supplierId: supplierId == null && nullToAbsent
          ? const Value.absent()
          : Value(supplierId),
      recordedDate: Value(recordedDate),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
    );
  }

  factory SupplyPriceHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SupplyPriceHistoryData(
      id: serializer.fromJson<String>(json['id']),
      supplyId: serializer.fromJson<String>(json['supplyId']),
      price: serializer.fromJson<int>(json['price']),
      storeName: serializer.fromJson<String>(json['storeName']),
      storeAddress: serializer.fromJson<String?>(json['storeAddress']),
      supplierId: serializer.fromJson<String?>(json['supplierId']),
      recordedDate: serializer.fromJson<DateTime>(json['recordedDate']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'supplyId': serializer.toJson<String>(supplyId),
      'price': serializer.toJson<int>(price),
      'storeName': serializer.toJson<String>(storeName),
      'storeAddress': serializer.toJson<String?>(storeAddress),
      'supplierId': serializer.toJson<String?>(supplierId),
      'recordedDate': serializer.toJson<DateTime>(recordedDate),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SupplyPriceHistoryData copyWith({
    String? id,
    String? supplyId,
    int? price,
    String? storeName,
    Value<String?> storeAddress = const Value.absent(),
    Value<String?> supplierId = const Value.absent(),
    DateTime? recordedDate,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
  }) => SupplyPriceHistoryData(
    id: id ?? this.id,
    supplyId: supplyId ?? this.supplyId,
    price: price ?? this.price,
    storeName: storeName ?? this.storeName,
    storeAddress: storeAddress.present ? storeAddress.value : this.storeAddress,
    supplierId: supplierId.present ? supplierId.value : this.supplierId,
    recordedDate: recordedDate ?? this.recordedDate,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
  );
  SupplyPriceHistoryData copyWithCompanion(SupplyPriceHistoryCompanion data) {
    return SupplyPriceHistoryData(
      id: data.id.present ? data.id.value : this.id,
      supplyId: data.supplyId.present ? data.supplyId.value : this.supplyId,
      price: data.price.present ? data.price.value : this.price,
      storeName: data.storeName.present ? data.storeName.value : this.storeName,
      storeAddress: data.storeAddress.present
          ? data.storeAddress.value
          : this.storeAddress,
      supplierId: data.supplierId.present
          ? data.supplierId.value
          : this.supplierId,
      recordedDate: data.recordedDate.present
          ? data.recordedDate.value
          : this.recordedDate,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SupplyPriceHistoryData(')
          ..write('id: $id, ')
          ..write('supplyId: $supplyId, ')
          ..write('price: $price, ')
          ..write('storeName: $storeName, ')
          ..write('storeAddress: $storeAddress, ')
          ..write('supplierId: $supplierId, ')
          ..write('recordedDate: $recordedDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    supplyId,
    price,
    storeName,
    storeAddress,
    supplierId,
    recordedDate,
    notes,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SupplyPriceHistoryData &&
          other.id == this.id &&
          other.supplyId == this.supplyId &&
          other.price == this.price &&
          other.storeName == this.storeName &&
          other.storeAddress == this.storeAddress &&
          other.supplierId == this.supplierId &&
          other.recordedDate == this.recordedDate &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt);
}

class SupplyPriceHistoryCompanion
    extends UpdateCompanion<SupplyPriceHistoryData> {
  final Value<String> id;
  final Value<String> supplyId;
  final Value<int> price;
  final Value<String> storeName;
  final Value<String?> storeAddress;
  final Value<String?> supplierId;
  final Value<DateTime> recordedDate;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SupplyPriceHistoryCompanion({
    this.id = const Value.absent(),
    this.supplyId = const Value.absent(),
    this.price = const Value.absent(),
    this.storeName = const Value.absent(),
    this.storeAddress = const Value.absent(),
    this.supplierId = const Value.absent(),
    this.recordedDate = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SupplyPriceHistoryCompanion.insert({
    required String id,
    required String supplyId,
    required int price,
    required String storeName,
    this.storeAddress = const Value.absent(),
    this.supplierId = const Value.absent(),
    required DateTime recordedDate,
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       supplyId = Value(supplyId),
       price = Value(price),
       storeName = Value(storeName),
       recordedDate = Value(recordedDate);
  static Insertable<SupplyPriceHistoryData> custom({
    Expression<String>? id,
    Expression<String>? supplyId,
    Expression<int>? price,
    Expression<String>? storeName,
    Expression<String>? storeAddress,
    Expression<String>? supplierId,
    Expression<DateTime>? recordedDate,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (supplyId != null) 'supply_id': supplyId,
      if (price != null) 'price': price,
      if (storeName != null) 'store_name': storeName,
      if (storeAddress != null) 'store_address': storeAddress,
      if (supplierId != null) 'supplier_id': supplierId,
      if (recordedDate != null) 'recorded_date': recordedDate,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SupplyPriceHistoryCompanion copyWith({
    Value<String>? id,
    Value<String>? supplyId,
    Value<int>? price,
    Value<String>? storeName,
    Value<String?>? storeAddress,
    Value<String?>? supplierId,
    Value<DateTime>? recordedDate,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SupplyPriceHistoryCompanion(
      id: id ?? this.id,
      supplyId: supplyId ?? this.supplyId,
      price: price ?? this.price,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      supplierId: supplierId ?? this.supplierId,
      recordedDate: recordedDate ?? this.recordedDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (supplyId.present) {
      map['supply_id'] = Variable<String>(supplyId.value);
    }
    if (price.present) {
      map['price'] = Variable<int>(price.value);
    }
    if (storeName.present) {
      map['store_name'] = Variable<String>(storeName.value);
    }
    if (storeAddress.present) {
      map['store_address'] = Variable<String>(storeAddress.value);
    }
    if (supplierId.present) {
      map['supplier_id'] = Variable<String>(supplierId.value);
    }
    if (recordedDate.present) {
      map['recorded_date'] = Variable<DateTime>(recordedDate.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SupplyPriceHistoryCompanion(')
          ..write('id: $id, ')
          ..write('supplyId: $supplyId, ')
          ..write('price: $price, ')
          ..write('storeName: $storeName, ')
          ..write('storeAddress: $storeAddress, ')
          ..write('supplierId: $supplierId, ')
          ..write('recordedDate: $recordedDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShoppingCartsTable extends ShoppingCarts
    with TableInfo<$ShoppingCartsTable, ShoppingCart> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShoppingCartsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _cartDateMeta = const VerificationMeta(
    'cartDate',
  );
  @override
  late final GeneratedColumn<DateTime> cartDate = GeneratedColumn<DateTime>(
    'cart_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storeNameMeta = const VerificationMeta(
    'storeName',
  );
  @override
  late final GeneratedColumn<String> storeName = GeneratedColumn<String>(
    'store_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storeAddressMeta = const VerificationMeta(
    'storeAddress',
  );
  @override
  late final GeneratedColumn<String> storeAddress = GeneratedColumn<String>(
    'store_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalAmountMeta = const VerificationMeta(
    'totalAmount',
  );
  @override
  late final GeneratedColumn<int> totalAmount = GeneratedColumn<int>(
    'total_amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expenseIdMeta = const VerificationMeta(
    'expenseId',
  );
  @override
  late final GeneratedColumn<String> expenseId = GeneratedColumn<String>(
    'expense_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES expenses (id)',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    cartDate,
    storeName,
    storeAddress,
    totalAmount,
    expenseId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shopping_carts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShoppingCart> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('cart_date')) {
      context.handle(
        _cartDateMeta,
        cartDate.isAcceptableOrUnknown(data['cart_date']!, _cartDateMeta),
      );
    } else if (isInserting) {
      context.missing(_cartDateMeta);
    }
    if (data.containsKey('store_name')) {
      context.handle(
        _storeNameMeta,
        storeName.isAcceptableOrUnknown(data['store_name']!, _storeNameMeta),
      );
    }
    if (data.containsKey('store_address')) {
      context.handle(
        _storeAddressMeta,
        storeAddress.isAcceptableOrUnknown(
          data['store_address']!,
          _storeAddressMeta,
        ),
      );
    }
    if (data.containsKey('total_amount')) {
      context.handle(
        _totalAmountMeta,
        totalAmount.isAcceptableOrUnknown(
          data['total_amount']!,
          _totalAmountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalAmountMeta);
    }
    if (data.containsKey('expense_id')) {
      context.handle(
        _expenseIdMeta,
        expenseId.isAcceptableOrUnknown(data['expense_id']!, _expenseIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShoppingCart map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShoppingCart(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      cartDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cart_date'],
      )!,
      storeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_name'],
      ),
      storeAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_address'],
      ),
      totalAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_amount'],
      )!,
      expenseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expense_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ShoppingCartsTable createAlias(String alias) {
    return $ShoppingCartsTable(attachedDatabase, alias);
  }
}

class ShoppingCart extends DataClass implements Insertable<ShoppingCart> {
  final String id;
  final String businessId;
  final DateTime cartDate;
  final String? storeName;
  final String? storeAddress;
  final int totalAmount;
  final String? expenseId;
  final DateTime createdAt;
  const ShoppingCart({
    required this.id,
    required this.businessId,
    required this.cartDate,
    this.storeName,
    this.storeAddress,
    required this.totalAmount,
    this.expenseId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['cart_date'] = Variable<DateTime>(cartDate);
    if (!nullToAbsent || storeName != null) {
      map['store_name'] = Variable<String>(storeName);
    }
    if (!nullToAbsent || storeAddress != null) {
      map['store_address'] = Variable<String>(storeAddress);
    }
    map['total_amount'] = Variable<int>(totalAmount);
    if (!nullToAbsent || expenseId != null) {
      map['expense_id'] = Variable<String>(expenseId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ShoppingCartsCompanion toCompanion(bool nullToAbsent) {
    return ShoppingCartsCompanion(
      id: Value(id),
      businessId: Value(businessId),
      cartDate: Value(cartDate),
      storeName: storeName == null && nullToAbsent
          ? const Value.absent()
          : Value(storeName),
      storeAddress: storeAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(storeAddress),
      totalAmount: Value(totalAmount),
      expenseId: expenseId == null && nullToAbsent
          ? const Value.absent()
          : Value(expenseId),
      createdAt: Value(createdAt),
    );
  }

  factory ShoppingCart.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShoppingCart(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      cartDate: serializer.fromJson<DateTime>(json['cartDate']),
      storeName: serializer.fromJson<String?>(json['storeName']),
      storeAddress: serializer.fromJson<String?>(json['storeAddress']),
      totalAmount: serializer.fromJson<int>(json['totalAmount']),
      expenseId: serializer.fromJson<String?>(json['expenseId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'cartDate': serializer.toJson<DateTime>(cartDate),
      'storeName': serializer.toJson<String?>(storeName),
      'storeAddress': serializer.toJson<String?>(storeAddress),
      'totalAmount': serializer.toJson<int>(totalAmount),
      'expenseId': serializer.toJson<String?>(expenseId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ShoppingCart copyWith({
    String? id,
    String? businessId,
    DateTime? cartDate,
    Value<String?> storeName = const Value.absent(),
    Value<String?> storeAddress = const Value.absent(),
    int? totalAmount,
    Value<String?> expenseId = const Value.absent(),
    DateTime? createdAt,
  }) => ShoppingCart(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    cartDate: cartDate ?? this.cartDate,
    storeName: storeName.present ? storeName.value : this.storeName,
    storeAddress: storeAddress.present ? storeAddress.value : this.storeAddress,
    totalAmount: totalAmount ?? this.totalAmount,
    expenseId: expenseId.present ? expenseId.value : this.expenseId,
    createdAt: createdAt ?? this.createdAt,
  );
  ShoppingCart copyWithCompanion(ShoppingCartsCompanion data) {
    return ShoppingCart(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      cartDate: data.cartDate.present ? data.cartDate.value : this.cartDate,
      storeName: data.storeName.present ? data.storeName.value : this.storeName,
      storeAddress: data.storeAddress.present
          ? data.storeAddress.value
          : this.storeAddress,
      totalAmount: data.totalAmount.present
          ? data.totalAmount.value
          : this.totalAmount,
      expenseId: data.expenseId.present ? data.expenseId.value : this.expenseId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingCart(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('cartDate: $cartDate, ')
          ..write('storeName: $storeName, ')
          ..write('storeAddress: $storeAddress, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('expenseId: $expenseId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    cartDate,
    storeName,
    storeAddress,
    totalAmount,
    expenseId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShoppingCart &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.cartDate == this.cartDate &&
          other.storeName == this.storeName &&
          other.storeAddress == this.storeAddress &&
          other.totalAmount == this.totalAmount &&
          other.expenseId == this.expenseId &&
          other.createdAt == this.createdAt);
}

class ShoppingCartsCompanion extends UpdateCompanion<ShoppingCart> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<DateTime> cartDate;
  final Value<String?> storeName;
  final Value<String?> storeAddress;
  final Value<int> totalAmount;
  final Value<String?> expenseId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ShoppingCartsCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.cartDate = const Value.absent(),
    this.storeName = const Value.absent(),
    this.storeAddress = const Value.absent(),
    this.totalAmount = const Value.absent(),
    this.expenseId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShoppingCartsCompanion.insert({
    required String id,
    required String businessId,
    required DateTime cartDate,
    this.storeName = const Value.absent(),
    this.storeAddress = const Value.absent(),
    required int totalAmount,
    this.expenseId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       cartDate = Value(cartDate),
       totalAmount = Value(totalAmount);
  static Insertable<ShoppingCart> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<DateTime>? cartDate,
    Expression<String>? storeName,
    Expression<String>? storeAddress,
    Expression<int>? totalAmount,
    Expression<String>? expenseId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (cartDate != null) 'cart_date': cartDate,
      if (storeName != null) 'store_name': storeName,
      if (storeAddress != null) 'store_address': storeAddress,
      if (totalAmount != null) 'total_amount': totalAmount,
      if (expenseId != null) 'expense_id': expenseId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShoppingCartsCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<DateTime>? cartDate,
    Value<String?>? storeName,
    Value<String?>? storeAddress,
    Value<int>? totalAmount,
    Value<String?>? expenseId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ShoppingCartsCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      cartDate: cartDate ?? this.cartDate,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      totalAmount: totalAmount ?? this.totalAmount,
      expenseId: expenseId ?? this.expenseId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (cartDate.present) {
      map['cart_date'] = Variable<DateTime>(cartDate.value);
    }
    if (storeName.present) {
      map['store_name'] = Variable<String>(storeName.value);
    }
    if (storeAddress.present) {
      map['store_address'] = Variable<String>(storeAddress.value);
    }
    if (totalAmount.present) {
      map['total_amount'] = Variable<int>(totalAmount.value);
    }
    if (expenseId.present) {
      map['expense_id'] = Variable<String>(expenseId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingCartsCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('cartDate: $cartDate, ')
          ..write('storeName: $storeName, ')
          ..write('storeAddress: $storeAddress, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('expenseId: $expenseId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShoppingCartItemsTable extends ShoppingCartItems
    with TableInfo<$ShoppingCartItemsTable, ShoppingCartItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShoppingCartItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cartIdMeta = const VerificationMeta('cartId');
  @override
  late final GeneratedColumn<String> cartId = GeneratedColumn<String>(
    'cart_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shopping_carts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _supplyIdMeta = const VerificationMeta(
    'supplyId',
  );
  @override
  late final GeneratedColumn<String> supplyId = GeneratedColumn<String>(
    'supply_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES supplies (id)',
    ),
  );
  static const VerificationMeta _itemNameMeta = const VerificationMeta(
    'itemName',
  );
  @override
  late final GeneratedColumn<String> itemName = GeneratedColumn<String>(
    'item_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitQuantityMeta = const VerificationMeta(
    'unitQuantity',
  );
  @override
  late final GeneratedColumn<double> unitQuantity = GeneratedColumn<double>(
    'unit_quantity',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitPriceMeta = const VerificationMeta(
    'unitPrice',
  );
  @override
  late final GeneratedColumn<int> unitPrice = GeneratedColumn<int>(
    'unit_price',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _lineTotalMeta = const VerificationMeta(
    'lineTotal',
  );
  @override
  late final GeneratedColumn<int> lineTotal = GeneratedColumn<int>(
    'line_total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cartId,
    supplyId,
    itemName,
    brand,
    unitQuantity,
    unit,
    unitPrice,
    quantity,
    lineTotal,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shopping_cart_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShoppingCartItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('cart_id')) {
      context.handle(
        _cartIdMeta,
        cartId.isAcceptableOrUnknown(data['cart_id']!, _cartIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cartIdMeta);
    }
    if (data.containsKey('supply_id')) {
      context.handle(
        _supplyIdMeta,
        supplyId.isAcceptableOrUnknown(data['supply_id']!, _supplyIdMeta),
      );
    }
    if (data.containsKey('item_name')) {
      context.handle(
        _itemNameMeta,
        itemName.isAcceptableOrUnknown(data['item_name']!, _itemNameMeta),
      );
    } else if (isInserting) {
      context.missing(_itemNameMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    }
    if (data.containsKey('unit_quantity')) {
      context.handle(
        _unitQuantityMeta,
        unitQuantity.isAcceptableOrUnknown(
          data['unit_quantity']!,
          _unitQuantityMeta,
        ),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('unit_price')) {
      context.handle(
        _unitPriceMeta,
        unitPrice.isAcceptableOrUnknown(data['unit_price']!, _unitPriceMeta),
      );
    } else if (isInserting) {
      context.missing(_unitPriceMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    if (data.containsKey('line_total')) {
      context.handle(
        _lineTotalMeta,
        lineTotal.isAcceptableOrUnknown(data['line_total']!, _lineTotalMeta),
      );
    } else if (isInserting) {
      context.missing(_lineTotalMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShoppingCartItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShoppingCartItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cartId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cart_id'],
      )!,
      supplyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supply_id'],
      ),
      itemName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_name'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      ),
      unitQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}unit_quantity'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      unitPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_price'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      lineTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_total'],
      )!,
    );
  }

  @override
  $ShoppingCartItemsTable createAlias(String alias) {
    return $ShoppingCartItemsTable(attachedDatabase, alias);
  }
}

class ShoppingCartItem extends DataClass
    implements Insertable<ShoppingCartItem> {
  final String id;
  final String cartId;
  final String? supplyId;
  final String itemName;
  final String? brand;
  final double? unitQuantity;
  final String? unit;
  final int unitPrice;
  final int quantity;
  final int lineTotal;
  const ShoppingCartItem({
    required this.id,
    required this.cartId,
    this.supplyId,
    required this.itemName,
    this.brand,
    this.unitQuantity,
    this.unit,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['cart_id'] = Variable<String>(cartId);
    if (!nullToAbsent || supplyId != null) {
      map['supply_id'] = Variable<String>(supplyId);
    }
    map['item_name'] = Variable<String>(itemName);
    if (!nullToAbsent || brand != null) {
      map['brand'] = Variable<String>(brand);
    }
    if (!nullToAbsent || unitQuantity != null) {
      map['unit_quantity'] = Variable<double>(unitQuantity);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    map['unit_price'] = Variable<int>(unitPrice);
    map['quantity'] = Variable<int>(quantity);
    map['line_total'] = Variable<int>(lineTotal);
    return map;
  }

  ShoppingCartItemsCompanion toCompanion(bool nullToAbsent) {
    return ShoppingCartItemsCompanion(
      id: Value(id),
      cartId: Value(cartId),
      supplyId: supplyId == null && nullToAbsent
          ? const Value.absent()
          : Value(supplyId),
      itemName: Value(itemName),
      brand: brand == null && nullToAbsent
          ? const Value.absent()
          : Value(brand),
      unitQuantity: unitQuantity == null && nullToAbsent
          ? const Value.absent()
          : Value(unitQuantity),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      unitPrice: Value(unitPrice),
      quantity: Value(quantity),
      lineTotal: Value(lineTotal),
    );
  }

  factory ShoppingCartItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShoppingCartItem(
      id: serializer.fromJson<String>(json['id']),
      cartId: serializer.fromJson<String>(json['cartId']),
      supplyId: serializer.fromJson<String?>(json['supplyId']),
      itemName: serializer.fromJson<String>(json['itemName']),
      brand: serializer.fromJson<String?>(json['brand']),
      unitQuantity: serializer.fromJson<double?>(json['unitQuantity']),
      unit: serializer.fromJson<String?>(json['unit']),
      unitPrice: serializer.fromJson<int>(json['unitPrice']),
      quantity: serializer.fromJson<int>(json['quantity']),
      lineTotal: serializer.fromJson<int>(json['lineTotal']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cartId': serializer.toJson<String>(cartId),
      'supplyId': serializer.toJson<String?>(supplyId),
      'itemName': serializer.toJson<String>(itemName),
      'brand': serializer.toJson<String?>(brand),
      'unitQuantity': serializer.toJson<double?>(unitQuantity),
      'unit': serializer.toJson<String?>(unit),
      'unitPrice': serializer.toJson<int>(unitPrice),
      'quantity': serializer.toJson<int>(quantity),
      'lineTotal': serializer.toJson<int>(lineTotal),
    };
  }

  ShoppingCartItem copyWith({
    String? id,
    String? cartId,
    Value<String?> supplyId = const Value.absent(),
    String? itemName,
    Value<String?> brand = const Value.absent(),
    Value<double?> unitQuantity = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    int? unitPrice,
    int? quantity,
    int? lineTotal,
  }) => ShoppingCartItem(
    id: id ?? this.id,
    cartId: cartId ?? this.cartId,
    supplyId: supplyId.present ? supplyId.value : this.supplyId,
    itemName: itemName ?? this.itemName,
    brand: brand.present ? brand.value : this.brand,
    unitQuantity: unitQuantity.present ? unitQuantity.value : this.unitQuantity,
    unit: unit.present ? unit.value : this.unit,
    unitPrice: unitPrice ?? this.unitPrice,
    quantity: quantity ?? this.quantity,
    lineTotal: lineTotal ?? this.lineTotal,
  );
  ShoppingCartItem copyWithCompanion(ShoppingCartItemsCompanion data) {
    return ShoppingCartItem(
      id: data.id.present ? data.id.value : this.id,
      cartId: data.cartId.present ? data.cartId.value : this.cartId,
      supplyId: data.supplyId.present ? data.supplyId.value : this.supplyId,
      itemName: data.itemName.present ? data.itemName.value : this.itemName,
      brand: data.brand.present ? data.brand.value : this.brand,
      unitQuantity: data.unitQuantity.present
          ? data.unitQuantity.value
          : this.unitQuantity,
      unit: data.unit.present ? data.unit.value : this.unit,
      unitPrice: data.unitPrice.present ? data.unitPrice.value : this.unitPrice,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      lineTotal: data.lineTotal.present ? data.lineTotal.value : this.lineTotal,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingCartItem(')
          ..write('id: $id, ')
          ..write('cartId: $cartId, ')
          ..write('supplyId: $supplyId, ')
          ..write('itemName: $itemName, ')
          ..write('brand: $brand, ')
          ..write('unitQuantity: $unitQuantity, ')
          ..write('unit: $unit, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('quantity: $quantity, ')
          ..write('lineTotal: $lineTotal')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cartId,
    supplyId,
    itemName,
    brand,
    unitQuantity,
    unit,
    unitPrice,
    quantity,
    lineTotal,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShoppingCartItem &&
          other.id == this.id &&
          other.cartId == this.cartId &&
          other.supplyId == this.supplyId &&
          other.itemName == this.itemName &&
          other.brand == this.brand &&
          other.unitQuantity == this.unitQuantity &&
          other.unit == this.unit &&
          other.unitPrice == this.unitPrice &&
          other.quantity == this.quantity &&
          other.lineTotal == this.lineTotal);
}

class ShoppingCartItemsCompanion extends UpdateCompanion<ShoppingCartItem> {
  final Value<String> id;
  final Value<String> cartId;
  final Value<String?> supplyId;
  final Value<String> itemName;
  final Value<String?> brand;
  final Value<double?> unitQuantity;
  final Value<String?> unit;
  final Value<int> unitPrice;
  final Value<int> quantity;
  final Value<int> lineTotal;
  final Value<int> rowid;
  const ShoppingCartItemsCompanion({
    this.id = const Value.absent(),
    this.cartId = const Value.absent(),
    this.supplyId = const Value.absent(),
    this.itemName = const Value.absent(),
    this.brand = const Value.absent(),
    this.unitQuantity = const Value.absent(),
    this.unit = const Value.absent(),
    this.unitPrice = const Value.absent(),
    this.quantity = const Value.absent(),
    this.lineTotal = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShoppingCartItemsCompanion.insert({
    required String id,
    required String cartId,
    this.supplyId = const Value.absent(),
    required String itemName,
    this.brand = const Value.absent(),
    this.unitQuantity = const Value.absent(),
    this.unit = const Value.absent(),
    required int unitPrice,
    this.quantity = const Value.absent(),
    required int lineTotal,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       cartId = Value(cartId),
       itemName = Value(itemName),
       unitPrice = Value(unitPrice),
       lineTotal = Value(lineTotal);
  static Insertable<ShoppingCartItem> custom({
    Expression<String>? id,
    Expression<String>? cartId,
    Expression<String>? supplyId,
    Expression<String>? itemName,
    Expression<String>? brand,
    Expression<double>? unitQuantity,
    Expression<String>? unit,
    Expression<int>? unitPrice,
    Expression<int>? quantity,
    Expression<int>? lineTotal,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cartId != null) 'cart_id': cartId,
      if (supplyId != null) 'supply_id': supplyId,
      if (itemName != null) 'item_name': itemName,
      if (brand != null) 'brand': brand,
      if (unitQuantity != null) 'unit_quantity': unitQuantity,
      if (unit != null) 'unit': unit,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (quantity != null) 'quantity': quantity,
      if (lineTotal != null) 'line_total': lineTotal,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShoppingCartItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? cartId,
    Value<String?>? supplyId,
    Value<String>? itemName,
    Value<String?>? brand,
    Value<double?>? unitQuantity,
    Value<String?>? unit,
    Value<int>? unitPrice,
    Value<int>? quantity,
    Value<int>? lineTotal,
    Value<int>? rowid,
  }) {
    return ShoppingCartItemsCompanion(
      id: id ?? this.id,
      cartId: cartId ?? this.cartId,
      supplyId: supplyId ?? this.supplyId,
      itemName: itemName ?? this.itemName,
      brand: brand ?? this.brand,
      unitQuantity: unitQuantity ?? this.unitQuantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      lineTotal: lineTotal ?? this.lineTotal,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cartId.present) {
      map['cart_id'] = Variable<String>(cartId.value);
    }
    if (supplyId.present) {
      map['supply_id'] = Variable<String>(supplyId.value);
    }
    if (itemName.present) {
      map['item_name'] = Variable<String>(itemName.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (unitQuantity.present) {
      map['unit_quantity'] = Variable<double>(unitQuantity.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (unitPrice.present) {
      map['unit_price'] = Variable<int>(unitPrice.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (lineTotal.present) {
      map['line_total'] = Variable<int>(lineTotal.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShoppingCartItemsCompanion(')
          ..write('id: $id, ')
          ..write('cartId: $cartId, ')
          ..write('supplyId: $supplyId, ')
          ..write('itemName: $itemName, ')
          ..write('brand: $brand, ')
          ..write('unitQuantity: $unitQuantity, ')
          ..write('unit: $unit, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('quantity: $quantity, ')
          ..write('lineTotal: $lineTotal, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountTransfersTable extends AccountTransfers
    with TableInfo<$AccountTransfersTable, AccountTransfer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountTransfersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta(
    'businessId',
  );
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES businesses (id)',
    ),
  );
  static const VerificationMeta _fromAccountIdMeta = const VerificationMeta(
    'fromAccountId',
  );
  @override
  late final GeneratedColumn<String> fromAccountId = GeneratedColumn<String>(
    'from_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _toAccountIdMeta = const VerificationMeta(
    'toAccountId',
  );
  @override
  late final GeneratedColumn<String> toAccountId = GeneratedColumn<String>(
    'to_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES accounts (id)',
    ),
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transferDateMeta = const VerificationMeta(
    'transferDate',
  );
  @override
  late final GeneratedColumn<DateTime> transferDate = GeneratedColumn<DateTime>(
    'transfer_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    businessId,
    fromAccountId,
    toAccountId,
    amount,
    transferDate,
    notes,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'account_transfers';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountTransfer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(
        _businessIdMeta,
        businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta),
      );
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('from_account_id')) {
      context.handle(
        _fromAccountIdMeta,
        fromAccountId.isAcceptableOrUnknown(
          data['from_account_id']!,
          _fromAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromAccountIdMeta);
    }
    if (data.containsKey('to_account_id')) {
      context.handle(
        _toAccountIdMeta,
        toAccountId.isAcceptableOrUnknown(
          data['to_account_id']!,
          _toAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_toAccountIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('transfer_date')) {
      context.handle(
        _transferDateMeta,
        transferDate.isAcceptableOrUnknown(
          data['transfer_date']!,
          _transferDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transferDateMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountTransfer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountTransfer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      businessId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_id'],
      )!,
      fromAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_account_id'],
      )!,
      toAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_account_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      transferDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}transfer_date'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AccountTransfersTable createAlias(String alias) {
    return $AccountTransfersTable(attachedDatabase, alias);
  }
}

class AccountTransfer extends DataClass implements Insertable<AccountTransfer> {
  final String id;
  final String businessId;
  final String fromAccountId;
  final String toAccountId;
  final int amount;
  final DateTime transferDate;
  final String? notes;
  final DateTime createdAt;
  const AccountTransfer({
    required this.id,
    required this.businessId,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.transferDate,
    this.notes,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['business_id'] = Variable<String>(businessId);
    map['from_account_id'] = Variable<String>(fromAccountId);
    map['to_account_id'] = Variable<String>(toAccountId);
    map['amount'] = Variable<int>(amount);
    map['transfer_date'] = Variable<DateTime>(transferDate);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AccountTransfersCompanion toCompanion(bool nullToAbsent) {
    return AccountTransfersCompanion(
      id: Value(id),
      businessId: Value(businessId),
      fromAccountId: Value(fromAccountId),
      toAccountId: Value(toAccountId),
      amount: Value(amount),
      transferDate: Value(transferDate),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAt: Value(createdAt),
    );
  }

  factory AccountTransfer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountTransfer(
      id: serializer.fromJson<String>(json['id']),
      businessId: serializer.fromJson<String>(json['businessId']),
      fromAccountId: serializer.fromJson<String>(json['fromAccountId']),
      toAccountId: serializer.fromJson<String>(json['toAccountId']),
      amount: serializer.fromJson<int>(json['amount']),
      transferDate: serializer.fromJson<DateTime>(json['transferDate']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'businessId': serializer.toJson<String>(businessId),
      'fromAccountId': serializer.toJson<String>(fromAccountId),
      'toAccountId': serializer.toJson<String>(toAccountId),
      'amount': serializer.toJson<int>(amount),
      'transferDate': serializer.toJson<DateTime>(transferDate),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AccountTransfer copyWith({
    String? id,
    String? businessId,
    String? fromAccountId,
    String? toAccountId,
    int? amount,
    DateTime? transferDate,
    Value<String?> notes = const Value.absent(),
    DateTime? createdAt,
  }) => AccountTransfer(
    id: id ?? this.id,
    businessId: businessId ?? this.businessId,
    fromAccountId: fromAccountId ?? this.fromAccountId,
    toAccountId: toAccountId ?? this.toAccountId,
    amount: amount ?? this.amount,
    transferDate: transferDate ?? this.transferDate,
    notes: notes.present ? notes.value : this.notes,
    createdAt: createdAt ?? this.createdAt,
  );
  AccountTransfer copyWithCompanion(AccountTransfersCompanion data) {
    return AccountTransfer(
      id: data.id.present ? data.id.value : this.id,
      businessId: data.businessId.present
          ? data.businessId.value
          : this.businessId,
      fromAccountId: data.fromAccountId.present
          ? data.fromAccountId.value
          : this.fromAccountId,
      toAccountId: data.toAccountId.present
          ? data.toAccountId.value
          : this.toAccountId,
      amount: data.amount.present ? data.amount.value : this.amount,
      transferDate: data.transferDate.present
          ? data.transferDate.value
          : this.transferDate,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountTransfer(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('fromAccountId: $fromAccountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('amount: $amount, ')
          ..write('transferDate: $transferDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    businessId,
    fromAccountId,
    toAccountId,
    amount,
    transferDate,
    notes,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountTransfer &&
          other.id == this.id &&
          other.businessId == this.businessId &&
          other.fromAccountId == this.fromAccountId &&
          other.toAccountId == this.toAccountId &&
          other.amount == this.amount &&
          other.transferDate == this.transferDate &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt);
}

class AccountTransfersCompanion extends UpdateCompanion<AccountTransfer> {
  final Value<String> id;
  final Value<String> businessId;
  final Value<String> fromAccountId;
  final Value<String> toAccountId;
  final Value<int> amount;
  final Value<DateTime> transferDate;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AccountTransfersCompanion({
    this.id = const Value.absent(),
    this.businessId = const Value.absent(),
    this.fromAccountId = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.amount = const Value.absent(),
    this.transferDate = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountTransfersCompanion.insert({
    required String id,
    required String businessId,
    required String fromAccountId,
    required String toAccountId,
    required int amount,
    required DateTime transferDate,
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       businessId = Value(businessId),
       fromAccountId = Value(fromAccountId),
       toAccountId = Value(toAccountId),
       amount = Value(amount),
       transferDate = Value(transferDate);
  static Insertable<AccountTransfer> custom({
    Expression<String>? id,
    Expression<String>? businessId,
    Expression<String>? fromAccountId,
    Expression<String>? toAccountId,
    Expression<int>? amount,
    Expression<DateTime>? transferDate,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (businessId != null) 'business_id': businessId,
      if (fromAccountId != null) 'from_account_id': fromAccountId,
      if (toAccountId != null) 'to_account_id': toAccountId,
      if (amount != null) 'amount': amount,
      if (transferDate != null) 'transfer_date': transferDate,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountTransfersCompanion copyWith({
    Value<String>? id,
    Value<String>? businessId,
    Value<String>? fromAccountId,
    Value<String>? toAccountId,
    Value<int>? amount,
    Value<DateTime>? transferDate,
    Value<String?>? notes,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AccountTransfersCompanion(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      fromAccountId: fromAccountId ?? this.fromAccountId,
      toAccountId: toAccountId ?? this.toAccountId,
      amount: amount ?? this.amount,
      transferDate: transferDate ?? this.transferDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (fromAccountId.present) {
      map['from_account_id'] = Variable<String>(fromAccountId.value);
    }
    if (toAccountId.present) {
      map['to_account_id'] = Variable<String>(toAccountId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (transferDate.present) {
      map['transfer_date'] = Variable<DateTime>(transferDate.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountTransfersCompanion(')
          ..write('id: $id, ')
          ..write('businessId: $businessId, ')
          ..write('fromAccountId: $fromAccountId, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('amount: $amount, ')
          ..write('transferDate: $transferDate, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BusinessesTable businesses = $BusinessesTable(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $JournalEntriesTable journalEntries = $JournalEntriesTable(this);
  late final $LedgerLinesTable ledgerLines = $LedgerLinesTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $CustomersTable customers = $CustomersTable(this);
  late final $IncomeTransactionsTable incomeTransactions =
      $IncomeTransactionsTable(this);
  late final $ReceivablePaymentsTable receivablePayments =
      $ReceivablePaymentsTable(this);
  late final $SuppliersTable suppliers = $SuppliersTable(this);
  late final $SupplierPurchasesTable supplierPurchases =
      $SupplierPurchasesTable(this);
  late final $PayablePaymentsTable payablePayments = $PayablePaymentsTable(
    this,
  );
  late final $ExpensesTable expenses = $ExpensesTable(this);
  late final $SuppliesTable supplies = $SuppliesTable(this);
  late final $SupplyPriceHistoryTable supplyPriceHistory =
      $SupplyPriceHistoryTable(this);
  late final $ShoppingCartsTable shoppingCarts = $ShoppingCartsTable(this);
  late final $ShoppingCartItemsTable shoppingCartItems =
      $ShoppingCartItemsTable(this);
  late final $AccountTransfersTable accountTransfers = $AccountTransfersTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    businesses,
    accounts,
    journalEntries,
    ledgerLines,
    categories,
    customers,
    incomeTransactions,
    receivablePayments,
    suppliers,
    supplierPurchases,
    payablePayments,
    expenses,
    supplies,
    supplyPriceHistory,
    shoppingCarts,
    shoppingCartItems,
    accountTransfers,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'journal_entries',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('ledger_lines', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'supplies',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('supply_price_history', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'shopping_carts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('shopping_cart_items', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$BusinessesTableCreateCompanionBuilder =
    BusinessesCompanion Function({
      required String id,
      required String name,
      Value<String?> ownerName,
      Value<String?> managerName,
      Value<String?> businessCategory,
      Value<String?> addressCountry,
      Value<String?> addressProvince,
      Value<String?> addressCity,
      Value<String?> addressBarangay,
      Value<String?> addressZipCode,
      Value<int> startingCapital,
      Value<String?> startingCapitalAccountId,
      Value<bool> isCurrent,
      Value<String> currency,
      required String ownerUserId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$BusinessesTableUpdateCompanionBuilder =
    BusinessesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> ownerName,
      Value<String?> managerName,
      Value<String?> businessCategory,
      Value<String?> addressCountry,
      Value<String?> addressProvince,
      Value<String?> addressCity,
      Value<String?> addressBarangay,
      Value<String?> addressZipCode,
      Value<int> startingCapital,
      Value<String?> startingCapitalAccountId,
      Value<bool> isCurrent,
      Value<String> currency,
      Value<String> ownerUserId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$BusinessesTableReferences
    extends BaseReferences<_$AppDatabase, $BusinessesTable, BusinessesData> {
  $$BusinessesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AccountsTable, List<Account>> _accountsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.accounts,
    aliasName: 'businesses__id__accounts__business_id',
  );

  $$AccountsTableProcessedTableManager get accountsRefs {
    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_accountsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$JournalEntriesTable, List<JournalEntry>>
  _journalEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.journalEntries,
    aliasName: 'businesses__id__journal_entries__business_id',
  );

  $$JournalEntriesTableProcessedTableManager get journalEntriesRefs {
    final manager = $$JournalEntriesTableTableManager(
      $_db,
      $_db.journalEntries,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_journalEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CategoriesTable, List<Category>>
  _categoriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.categories,
    aliasName: 'businesses__id__categories__business_id',
  );

  $$CategoriesTableProcessedTableManager get categoriesRefs {
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_categoriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CustomersTable, List<Customer>>
  _customersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.customers,
    aliasName: 'businesses__id__customers__business_id',
  );

  $$CustomersTableProcessedTableManager get customersRefs {
    final manager = $$CustomersTableTableManager(
      $_db,
      $_db.customers,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_customersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$IncomeTransactionsTable, List<IncomeTransaction>>
  _incomeTransactionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.incomeTransactions,
        aliasName: 'businesses__id__income_transactions__business_id',
      );

  $$IncomeTransactionsTableProcessedTableManager get incomeTransactionsRefs {
    final manager = $$IncomeTransactionsTableTableManager(
      $_db,
      $_db.incomeTransactions,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _incomeTransactionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReceivablePaymentsTable, List<ReceivablePayment>>
  _receivablePaymentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.receivablePayments,
        aliasName: 'businesses__id__receivable_payments__business_id',
      );

  $$ReceivablePaymentsTableProcessedTableManager get receivablePaymentsRefs {
    final manager = $$ReceivablePaymentsTableTableManager(
      $_db,
      $_db.receivablePayments,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _receivablePaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SuppliersTable, List<Supplier>>
  _suppliersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.suppliers,
    aliasName: 'businesses__id__suppliers__business_id',
  );

  $$SuppliersTableProcessedTableManager get suppliersRefs {
    final manager = $$SuppliersTableTableManager(
      $_db,
      $_db.suppliers,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_suppliersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SupplierPurchasesTable, List<SupplierPurchase>>
  _supplierPurchasesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.supplierPurchases,
        aliasName: 'businesses__id__supplier_purchases__business_id',
      );

  $$SupplierPurchasesTableProcessedTableManager get supplierPurchasesRefs {
    final manager = $$SupplierPurchasesTableTableManager(
      $_db,
      $_db.supplierPurchases,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _supplierPurchasesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PayablePaymentsTable, List<PayablePayment>>
  _payablePaymentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.payablePayments,
    aliasName: 'businesses__id__payable_payments__business_id',
  );

  $$PayablePaymentsTableProcessedTableManager get payablePaymentsRefs {
    final manager = $$PayablePaymentsTableTableManager(
      $_db,
      $_db.payablePayments,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _payablePaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ExpensesTable, List<Expense>> _expensesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.expenses,
    aliasName: 'businesses__id__expenses__business_id',
  );

  $$ExpensesTableProcessedTableManager get expensesRefs {
    final manager = $$ExpensesTableTableManager(
      $_db,
      $_db.expenses,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_expensesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SuppliesTable, List<Supply>> _suppliesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.supplies,
    aliasName: 'businesses__id__supplies__business_id',
  );

  $$SuppliesTableProcessedTableManager get suppliesRefs {
    final manager = $$SuppliesTableTableManager(
      $_db,
      $_db.supplies,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_suppliesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ShoppingCartsTable, List<ShoppingCart>>
  _shoppingCartsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.shoppingCarts,
    aliasName: 'businesses__id__shopping_carts__business_id',
  );

  $$ShoppingCartsTableProcessedTableManager get shoppingCartsRefs {
    final manager = $$ShoppingCartsTableTableManager(
      $_db,
      $_db.shoppingCarts,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_shoppingCartsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AccountTransfersTable, List<AccountTransfer>>
  _accountTransfersRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.accountTransfers,
    aliasName: 'businesses__id__account_transfers__business_id',
  );

  $$AccountTransfersTableProcessedTableManager get accountTransfersRefs {
    final manager = $$AccountTransfersTableTableManager(
      $_db,
      $_db.accountTransfers,
    ).filter((f) => f.businessId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _accountTransfersRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BusinessesTableFilterComposer
    extends Composer<_$AppDatabase, $BusinessesTable> {
  $$BusinessesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerName => $composableBuilder(
    column: $table.ownerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get managerName => $composableBuilder(
    column: $table.managerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessCategory => $composableBuilder(
    column: $table.businessCategory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addressCountry => $composableBuilder(
    column: $table.addressCountry,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addressProvince => $composableBuilder(
    column: $table.addressProvince,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addressCity => $composableBuilder(
    column: $table.addressCity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addressBarangay => $composableBuilder(
    column: $table.addressBarangay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addressZipCode => $composableBuilder(
    column: $table.addressZipCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startingCapital => $composableBuilder(
    column: $table.startingCapital,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startingCapitalAccountId => $composableBuilder(
    column: $table.startingCapitalAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> accountsRefs(
    Expression<bool> Function($$AccountsTableFilterComposer f) f,
  ) {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> journalEntriesRefs(
    Expression<bool> Function($$JournalEntriesTableFilterComposer f) f,
  ) {
    final $$JournalEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableFilterComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> categoriesRefs(
    Expression<bool> Function($$CategoriesTableFilterComposer f) f,
  ) {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> customersRefs(
    Expression<bool> Function($$CustomersTableFilterComposer f) f,
  ) {
    final $$CustomersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableFilterComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> incomeTransactionsRefs(
    Expression<bool> Function($$IncomeTransactionsTableFilterComposer f) f,
  ) {
    final $$IncomeTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.incomeTransactions,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IncomeTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.incomeTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> receivablePaymentsRefs(
    Expression<bool> Function($$ReceivablePaymentsTableFilterComposer f) f,
  ) {
    final $$ReceivablePaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.receivablePayments,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceivablePaymentsTableFilterComposer(
            $db: $db,
            $table: $db.receivablePayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> suppliersRefs(
    Expression<bool> Function($$SuppliersTableFilterComposer f) f,
  ) {
    final $$SuppliersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableFilterComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> supplierPurchasesRefs(
    Expression<bool> Function($$SupplierPurchasesTableFilterComposer f) f,
  ) {
    final $$SupplierPurchasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.supplierPurchases,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SupplierPurchasesTableFilterComposer(
            $db: $db,
            $table: $db.supplierPurchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> payablePaymentsRefs(
    Expression<bool> Function($$PayablePaymentsTableFilterComposer f) f,
  ) {
    final $$PayablePaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payablePayments,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PayablePaymentsTableFilterComposer(
            $db: $db,
            $table: $db.payablePayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> expensesRefs(
    Expression<bool> Function($$ExpensesTableFilterComposer f) f,
  ) {
    final $$ExpensesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableFilterComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> suppliesRefs(
    Expression<bool> Function($$SuppliesTableFilterComposer f) f,
  ) {
    final $$SuppliesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.supplies,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliesTableFilterComposer(
            $db: $db,
            $table: $db.supplies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> shoppingCartsRefs(
    Expression<bool> Function($$ShoppingCartsTableFilterComposer f) f,
  ) {
    final $$ShoppingCartsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingCarts,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingCartsTableFilterComposer(
            $db: $db,
            $table: $db.shoppingCarts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> accountTransfersRefs(
    Expression<bool> Function($$AccountTransfersTableFilterComposer f) f,
  ) {
    final $$AccountTransfersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.accountTransfers,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountTransfersTableFilterComposer(
            $db: $db,
            $table: $db.accountTransfers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BusinessesTableOrderingComposer
    extends Composer<_$AppDatabase, $BusinessesTable> {
  $$BusinessesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerName => $composableBuilder(
    column: $table.ownerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get managerName => $composableBuilder(
    column: $table.managerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessCategory => $composableBuilder(
    column: $table.businessCategory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addressCountry => $composableBuilder(
    column: $table.addressCountry,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addressProvince => $composableBuilder(
    column: $table.addressProvince,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addressCity => $composableBuilder(
    column: $table.addressCity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addressBarangay => $composableBuilder(
    column: $table.addressBarangay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addressZipCode => $composableBuilder(
    column: $table.addressZipCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startingCapital => $composableBuilder(
    column: $table.startingCapital,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startingCapitalAccountId => $composableBuilder(
    column: $table.startingCapitalAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BusinessesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BusinessesTable> {
  $$BusinessesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get ownerName =>
      $composableBuilder(column: $table.ownerName, builder: (column) => column);

  GeneratedColumn<String> get managerName => $composableBuilder(
    column: $table.managerName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get businessCategory => $composableBuilder(
    column: $table.businessCategory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addressCountry => $composableBuilder(
    column: $table.addressCountry,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addressProvince => $composableBuilder(
    column: $table.addressProvince,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addressCity => $composableBuilder(
    column: $table.addressCity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addressBarangay => $composableBuilder(
    column: $table.addressBarangay,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addressZipCode => $composableBuilder(
    column: $table.addressZipCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startingCapital => $composableBuilder(
    column: $table.startingCapital,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startingCapitalAccountId => $composableBuilder(
    column: $table.startingCapitalAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCurrent =>
      $composableBuilder(column: $table.isCurrent, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get ownerUserId => $composableBuilder(
    column: $table.ownerUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> accountsRefs<T extends Object>(
    Expression<T> Function($$AccountsTableAnnotationComposer a) f,
  ) {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> journalEntriesRefs<T extends Object>(
    Expression<T> Function($$JournalEntriesTableAnnotationComposer a) f,
  ) {
    final $$JournalEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> categoriesRefs<T extends Object>(
    Expression<T> Function($$CategoriesTableAnnotationComposer a) f,
  ) {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> customersRefs<T extends Object>(
    Expression<T> Function($$CustomersTableAnnotationComposer a) f,
  ) {
    final $$CustomersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableAnnotationComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> incomeTransactionsRefs<T extends Object>(
    Expression<T> Function($$IncomeTransactionsTableAnnotationComposer a) f,
  ) {
    final $$IncomeTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.incomeTransactions,
          getReferencedColumn: (t) => t.businessId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$IncomeTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.incomeTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> receivablePaymentsRefs<T extends Object>(
    Expression<T> Function($$ReceivablePaymentsTableAnnotationComposer a) f,
  ) {
    final $$ReceivablePaymentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.receivablePayments,
          getReferencedColumn: (t) => t.businessId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReceivablePaymentsTableAnnotationComposer(
                $db: $db,
                $table: $db.receivablePayments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> suppliersRefs<T extends Object>(
    Expression<T> Function($$SuppliersTableAnnotationComposer a) f,
  ) {
    final $$SuppliersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableAnnotationComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> supplierPurchasesRefs<T extends Object>(
    Expression<T> Function($$SupplierPurchasesTableAnnotationComposer a) f,
  ) {
    final $$SupplierPurchasesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.supplierPurchases,
          getReferencedColumn: (t) => t.businessId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SupplierPurchasesTableAnnotationComposer(
                $db: $db,
                $table: $db.supplierPurchases,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> payablePaymentsRefs<T extends Object>(
    Expression<T> Function($$PayablePaymentsTableAnnotationComposer a) f,
  ) {
    final $$PayablePaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payablePayments,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PayablePaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.payablePayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> expensesRefs<T extends Object>(
    Expression<T> Function($$ExpensesTableAnnotationComposer a) f,
  ) {
    final $$ExpensesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableAnnotationComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> suppliesRefs<T extends Object>(
    Expression<T> Function($$SuppliesTableAnnotationComposer a) f,
  ) {
    final $$SuppliesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.supplies,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliesTableAnnotationComposer(
            $db: $db,
            $table: $db.supplies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> shoppingCartsRefs<T extends Object>(
    Expression<T> Function($$ShoppingCartsTableAnnotationComposer a) f,
  ) {
    final $$ShoppingCartsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingCarts,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingCartsTableAnnotationComposer(
            $db: $db,
            $table: $db.shoppingCarts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> accountTransfersRefs<T extends Object>(
    Expression<T> Function($$AccountTransfersTableAnnotationComposer a) f,
  ) {
    final $$AccountTransfersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.accountTransfers,
      getReferencedColumn: (t) => t.businessId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountTransfersTableAnnotationComposer(
            $db: $db,
            $table: $db.accountTransfers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BusinessesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BusinessesTable,
          BusinessesData,
          $$BusinessesTableFilterComposer,
          $$BusinessesTableOrderingComposer,
          $$BusinessesTableAnnotationComposer,
          $$BusinessesTableCreateCompanionBuilder,
          $$BusinessesTableUpdateCompanionBuilder,
          (BusinessesData, $$BusinessesTableReferences),
          BusinessesData,
          PrefetchHooks Function({
            bool accountsRefs,
            bool journalEntriesRefs,
            bool categoriesRefs,
            bool customersRefs,
            bool incomeTransactionsRefs,
            bool receivablePaymentsRefs,
            bool suppliersRefs,
            bool supplierPurchasesRefs,
            bool payablePaymentsRefs,
            bool expensesRefs,
            bool suppliesRefs,
            bool shoppingCartsRefs,
            bool accountTransfersRefs,
          })
        > {
  $$BusinessesTableTableManager(_$AppDatabase db, $BusinessesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BusinessesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BusinessesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BusinessesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> ownerName = const Value.absent(),
                Value<String?> managerName = const Value.absent(),
                Value<String?> businessCategory = const Value.absent(),
                Value<String?> addressCountry = const Value.absent(),
                Value<String?> addressProvince = const Value.absent(),
                Value<String?> addressCity = const Value.absent(),
                Value<String?> addressBarangay = const Value.absent(),
                Value<String?> addressZipCode = const Value.absent(),
                Value<int> startingCapital = const Value.absent(),
                Value<String?> startingCapitalAccountId = const Value.absent(),
                Value<bool> isCurrent = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> ownerUserId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BusinessesCompanion(
                id: id,
                name: name,
                ownerName: ownerName,
                managerName: managerName,
                businessCategory: businessCategory,
                addressCountry: addressCountry,
                addressProvince: addressProvince,
                addressCity: addressCity,
                addressBarangay: addressBarangay,
                addressZipCode: addressZipCode,
                startingCapital: startingCapital,
                startingCapitalAccountId: startingCapitalAccountId,
                isCurrent: isCurrent,
                currency: currency,
                ownerUserId: ownerUserId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> ownerName = const Value.absent(),
                Value<String?> managerName = const Value.absent(),
                Value<String?> businessCategory = const Value.absent(),
                Value<String?> addressCountry = const Value.absent(),
                Value<String?> addressProvince = const Value.absent(),
                Value<String?> addressCity = const Value.absent(),
                Value<String?> addressBarangay = const Value.absent(),
                Value<String?> addressZipCode = const Value.absent(),
                Value<int> startingCapital = const Value.absent(),
                Value<String?> startingCapitalAccountId = const Value.absent(),
                Value<bool> isCurrent = const Value.absent(),
                Value<String> currency = const Value.absent(),
                required String ownerUserId,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BusinessesCompanion.insert(
                id: id,
                name: name,
                ownerName: ownerName,
                managerName: managerName,
                businessCategory: businessCategory,
                addressCountry: addressCountry,
                addressProvince: addressProvince,
                addressCity: addressCity,
                addressBarangay: addressBarangay,
                addressZipCode: addressZipCode,
                startingCapital: startingCapital,
                startingCapitalAccountId: startingCapitalAccountId,
                isCurrent: isCurrent,
                currency: currency,
                ownerUserId: ownerUserId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BusinessesTable, BusinessesData>(table),
                  $$BusinessesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                accountsRefs = false,
                journalEntriesRefs = false,
                categoriesRefs = false,
                customersRefs = false,
                incomeTransactionsRefs = false,
                receivablePaymentsRefs = false,
                suppliersRefs = false,
                supplierPurchasesRefs = false,
                payablePaymentsRefs = false,
                expensesRefs = false,
                suppliesRefs = false,
                shoppingCartsRefs = false,
                accountTransfersRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (accountsRefs) db.accounts,
                    if (journalEntriesRefs) db.journalEntries,
                    if (categoriesRefs) db.categories,
                    if (customersRefs) db.customers,
                    if (incomeTransactionsRefs) db.incomeTransactions,
                    if (receivablePaymentsRefs) db.receivablePayments,
                    if (suppliersRefs) db.suppliers,
                    if (supplierPurchasesRefs) db.supplierPurchases,
                    if (payablePaymentsRefs) db.payablePayments,
                    if (expensesRefs) db.expenses,
                    if (suppliesRefs) db.supplies,
                    if (shoppingCartsRefs) db.shoppingCarts,
                    if (accountTransfersRefs) db.accountTransfers,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (accountsRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          Account
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._accountsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).accountsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (journalEntriesRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          JournalEntry
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._journalEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).journalEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (categoriesRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          Category
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._categoriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).categoriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (customersRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          Customer
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._customersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).customersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (incomeTransactionsRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          IncomeTransaction
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._incomeTransactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).incomeTransactionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (receivablePaymentsRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          ReceivablePayment
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._receivablePaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).receivablePaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (suppliersRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          Supplier
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._suppliersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).suppliersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (supplierPurchasesRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          SupplierPurchase
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._supplierPurchasesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).supplierPurchasesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (payablePaymentsRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          PayablePayment
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._payablePaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).payablePaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (expensesRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          Expense
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._expensesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).expensesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (suppliesRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          Supply
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._suppliesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).suppliesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (shoppingCartsRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          ShoppingCart
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._shoppingCartsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).shoppingCartsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (accountTransfersRefs)
                        await $_getPrefetchedData<
                          BusinessesData,
                          $BusinessesTable,
                          AccountTransfer
                        >(
                          currentTable: table,
                          referencedTable: $$BusinessesTableReferences
                              ._accountTransfersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BusinessesTableReferences(
                                db,
                                table,
                                p0,
                              ).accountTransfersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.businessId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BusinessesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BusinessesTable,
      BusinessesData,
      $$BusinessesTableFilterComposer,
      $$BusinessesTableOrderingComposer,
      $$BusinessesTableAnnotationComposer,
      $$BusinessesTableCreateCompanionBuilder,
      $$BusinessesTableUpdateCompanionBuilder,
      (BusinessesData, $$BusinessesTableReferences),
      BusinessesData,
      PrefetchHooks Function({
        bool accountsRefs,
        bool journalEntriesRefs,
        bool categoriesRefs,
        bool customersRefs,
        bool incomeTransactionsRefs,
        bool receivablePaymentsRefs,
        bool suppliersRefs,
        bool supplierPurchasesRefs,
        bool payablePaymentsRefs,
        bool expensesRefs,
        bool suppliesRefs,
        bool shoppingCartsRefs,
        bool accountTransfersRefs,
      })
    >;
typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      required String id,
      required String businessId,
      required String name,
      required String type,
      Value<bool> isPaymentAccount,
      Value<int> startingBalance,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> name,
      Value<String> type,
      Value<bool> isPaymentAccount,
      Value<int> startingBalance,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$AccountsTableReferences
    extends BaseReferences<_$AppDatabase, $AccountsTable, Account> {
  $$AccountsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BusinessesTable _businessIdTable(_$AppDatabase db) =>
      db.businesses.createAlias('accounts__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$LedgerLinesTable, List<LedgerLine>>
  _ledgerLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ledgerLines,
    aliasName: 'accounts__id__ledger_lines__account_id',
  );

  $$LedgerLinesTableProcessedTableManager get ledgerLinesRefs {
    final manager = $$LedgerLinesTableTableManager(
      $_db,
      $_db.ledgerLines,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_ledgerLinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CategoriesTable, List<Category>>
  _categoriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.categories,
    aliasName: 'accounts__id__categories__ledger_account_id',
  );

  $$CategoriesTableProcessedTableManager get categoriesRefs {
    final manager = $$CategoriesTableTableManager($_db, $_db.categories).filter(
      (f) => f.ledgerAccountId.id.sqlEquals($_itemColumn<String>('id')!),
    );

    final cache = $_typedResult.readTableOrNull(_categoriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$IncomeTransactionsTable, List<IncomeTransaction>>
  _incomeTransactionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.incomeTransactions,
        aliasName: 'accounts__id__income_transactions__payment_account_id',
      );

  $$IncomeTransactionsTableProcessedTableManager get incomeTransactionsRefs {
    final manager =
        $$IncomeTransactionsTableTableManager(
          $_db,
          $_db.incomeTransactions,
        ).filter(
          (f) => f.paymentAccountId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _incomeTransactionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReceivablePaymentsTable, List<ReceivablePayment>>
  _receivablePaymentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.receivablePayments,
        aliasName: 'accounts__id__receivable_payments__payment_account_id',
      );

  $$ReceivablePaymentsTableProcessedTableManager get receivablePaymentsRefs {
    final manager =
        $$ReceivablePaymentsTableTableManager(
          $_db,
          $_db.receivablePayments,
        ).filter(
          (f) => f.paymentAccountId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _receivablePaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SupplierPurchasesTable, List<SupplierPurchase>>
  _supplierPurchasesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.supplierPurchases,
        aliasName: 'accounts__id__supplier_purchases__payment_account_id',
      );

  $$SupplierPurchasesTableProcessedTableManager get supplierPurchasesRefs {
    final manager =
        $$SupplierPurchasesTableTableManager(
          $_db,
          $_db.supplierPurchases,
        ).filter(
          (f) => f.paymentAccountId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _supplierPurchasesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PayablePaymentsTable, List<PayablePayment>>
  _payablePaymentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.payablePayments,
    aliasName: 'accounts__id__payable_payments__payment_account_id',
  );

  $$PayablePaymentsTableProcessedTableManager get payablePaymentsRefs {
    final manager =
        $$PayablePaymentsTableTableManager($_db, $_db.payablePayments).filter(
          (f) => f.paymentAccountId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _payablePaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ExpensesTable, List<Expense>> _expensesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.expenses,
    aliasName: 'accounts__id__expenses__payment_account_id',
  );

  $$ExpensesTableProcessedTableManager get expensesRefs {
    final manager = $$ExpensesTableTableManager($_db, $_db.expenses).filter(
      (f) => f.paymentAccountId.id.sqlEquals($_itemColumn<String>('id')!),
    );

    final cache = $_typedResult.readTableOrNull(_expensesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AccountsTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPaymentAccount => $composableBuilder(
    column: $table.isPaymentAccount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startingBalance => $composableBuilder(
    column: $table.startingBalance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> ledgerLinesRefs(
    Expression<bool> Function($$LedgerLinesTableFilterComposer f) f,
  ) {
    final $$LedgerLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ledgerLines,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LedgerLinesTableFilterComposer(
            $db: $db,
            $table: $db.ledgerLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> categoriesRefs(
    Expression<bool> Function($$CategoriesTableFilterComposer f) f,
  ) {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.ledgerAccountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> incomeTransactionsRefs(
    Expression<bool> Function($$IncomeTransactionsTableFilterComposer f) f,
  ) {
    final $$IncomeTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.incomeTransactions,
      getReferencedColumn: (t) => t.paymentAccountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IncomeTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.incomeTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> receivablePaymentsRefs(
    Expression<bool> Function($$ReceivablePaymentsTableFilterComposer f) f,
  ) {
    final $$ReceivablePaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.receivablePayments,
      getReferencedColumn: (t) => t.paymentAccountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceivablePaymentsTableFilterComposer(
            $db: $db,
            $table: $db.receivablePayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> supplierPurchasesRefs(
    Expression<bool> Function($$SupplierPurchasesTableFilterComposer f) f,
  ) {
    final $$SupplierPurchasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.supplierPurchases,
      getReferencedColumn: (t) => t.paymentAccountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SupplierPurchasesTableFilterComposer(
            $db: $db,
            $table: $db.supplierPurchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> payablePaymentsRefs(
    Expression<bool> Function($$PayablePaymentsTableFilterComposer f) f,
  ) {
    final $$PayablePaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payablePayments,
      getReferencedColumn: (t) => t.paymentAccountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PayablePaymentsTableFilterComposer(
            $db: $db,
            $table: $db.payablePayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> expensesRefs(
    Expression<bool> Function($$ExpensesTableFilterComposer f) f,
  ) {
    final $$ExpensesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.paymentAccountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableFilterComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPaymentAccount => $composableBuilder(
    column: $table.isPaymentAccount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startingBalance => $composableBuilder(
    column: $table.startingBalance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<bool> get isPaymentAccount => $composableBuilder(
    column: $table.isPaymentAccount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startingBalance => $composableBuilder(
    column: $table.startingBalance,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> ledgerLinesRefs<T extends Object>(
    Expression<T> Function($$LedgerLinesTableAnnotationComposer a) f,
  ) {
    final $$LedgerLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ledgerLines,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LedgerLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.ledgerLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> categoriesRefs<T extends Object>(
    Expression<T> Function($$CategoriesTableAnnotationComposer a) f,
  ) {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.ledgerAccountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> incomeTransactionsRefs<T extends Object>(
    Expression<T> Function($$IncomeTransactionsTableAnnotationComposer a) f,
  ) {
    final $$IncomeTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.incomeTransactions,
          getReferencedColumn: (t) => t.paymentAccountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$IncomeTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.incomeTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> receivablePaymentsRefs<T extends Object>(
    Expression<T> Function($$ReceivablePaymentsTableAnnotationComposer a) f,
  ) {
    final $$ReceivablePaymentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.receivablePayments,
          getReferencedColumn: (t) => t.paymentAccountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReceivablePaymentsTableAnnotationComposer(
                $db: $db,
                $table: $db.receivablePayments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> supplierPurchasesRefs<T extends Object>(
    Expression<T> Function($$SupplierPurchasesTableAnnotationComposer a) f,
  ) {
    final $$SupplierPurchasesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.supplierPurchases,
          getReferencedColumn: (t) => t.paymentAccountId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SupplierPurchasesTableAnnotationComposer(
                $db: $db,
                $table: $db.supplierPurchases,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> payablePaymentsRefs<T extends Object>(
    Expression<T> Function($$PayablePaymentsTableAnnotationComposer a) f,
  ) {
    final $$PayablePaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payablePayments,
      getReferencedColumn: (t) => t.paymentAccountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PayablePaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.payablePayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> expensesRefs<T extends Object>(
    Expression<T> Function($$ExpensesTableAnnotationComposer a) f,
  ) {
    final $$ExpensesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.paymentAccountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableAnnotationComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          Account,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (Account, $$AccountsTableReferences),
          Account,
          PrefetchHooks Function({
            bool businessId,
            bool ledgerLinesRefs,
            bool categoriesRefs,
            bool incomeTransactionsRefs,
            bool receivablePaymentsRefs,
            bool supplierPurchasesRefs,
            bool payablePaymentsRefs,
            bool expensesRefs,
          })
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<bool> isPaymentAccount = const Value.absent(),
                Value<int> startingBalance = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                businessId: businessId,
                name: name,
                type: type,
                isPaymentAccount: isPaymentAccount,
                startingBalance: startingBalance,
                isActive: isActive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String name,
                required String type,
                Value<bool> isPaymentAccount = const Value.absent(),
                Value<int> startingBalance = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                businessId: businessId,
                name: name,
                type: type,
                isPaymentAccount: isPaymentAccount,
                startingBalance: startingBalance,
                isActive: isActive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AccountsTable, Account>(table),
                  $$AccountsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                ledgerLinesRefs = false,
                categoriesRefs = false,
                incomeTransactionsRefs = false,
                receivablePaymentsRefs = false,
                supplierPurchasesRefs = false,
                payablePaymentsRefs = false,
                expensesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (ledgerLinesRefs) db.ledgerLines,
                    if (categoriesRefs) db.categories,
                    if (incomeTransactionsRefs) db.incomeTransactions,
                    if (receivablePaymentsRefs) db.receivablePayments,
                    if (supplierPurchasesRefs) db.supplierPurchases,
                    if (payablePaymentsRefs) db.payablePayments,
                    if (expensesRefs) db.expenses,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable: $$AccountsTableReferences
                                        ._businessIdTable(db),
                                    referencedColumn: $$AccountsTableReferences
                                        ._businessIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (ledgerLinesRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          LedgerLine
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._ledgerLinesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).ledgerLinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.accountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (categoriesRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          Category
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._categoriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).categoriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ledgerAccountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (incomeTransactionsRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          IncomeTransaction
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._incomeTransactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).incomeTransactionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.paymentAccountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (receivablePaymentsRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          ReceivablePayment
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._receivablePaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).receivablePaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.paymentAccountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (supplierPurchasesRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          SupplierPurchase
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._supplierPurchasesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).supplierPurchasesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.paymentAccountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (payablePaymentsRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          PayablePayment
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._payablePaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).payablePaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.paymentAccountId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (expensesRefs)
                        await $_getPrefetchedData<
                          Account,
                          $AccountsTable,
                          Expense
                        >(
                          currentTable: table,
                          referencedTable: $$AccountsTableReferences
                              ._expensesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AccountsTableReferences(
                                db,
                                table,
                                p0,
                              ).expensesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.paymentAccountId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      Account,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (Account, $$AccountsTableReferences),
      Account,
      PrefetchHooks Function({
        bool businessId,
        bool ledgerLinesRefs,
        bool categoriesRefs,
        bool incomeTransactionsRefs,
        bool receivablePaymentsRefs,
        bool supplierPurchasesRefs,
        bool payablePaymentsRefs,
        bool expensesRefs,
      })
    >;
typedef $$JournalEntriesTableCreateCompanionBuilder =
    JournalEntriesCompanion Function({
      required String id,
      required String businessId,
      required DateTime entryDate,
      Value<String?> description,
      required String sourceType,
      Value<String?> sourceId,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$JournalEntriesTableUpdateCompanionBuilder =
    JournalEntriesCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<DateTime> entryDate,
      Value<String?> description,
      Value<String> sourceType,
      Value<String?> sourceId,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$JournalEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $JournalEntriesTable, JournalEntry> {
  $$JournalEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BusinessesTable _businessIdTable(_$AppDatabase db) =>
      db.businesses.createAlias('journal_entries__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$LedgerLinesTable, List<LedgerLine>>
  _ledgerLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ledgerLines,
    aliasName: 'journal_entries__id__ledger_lines__journal_entry_id',
  );

  $$LedgerLinesTableProcessedTableManager get ledgerLinesRefs {
    final manager = $$LedgerLinesTableTableManager(
      $_db,
      $_db.ledgerLines,
    ).filter((f) => f.journalEntryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_ledgerLinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$IncomeTransactionsTable, List<IncomeTransaction>>
  _incomeTransactionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.incomeTransactions,
        aliasName: 'journal_entries__id__income_transactions__journal_entry_id',
      );

  $$IncomeTransactionsTableProcessedTableManager get incomeTransactionsRefs {
    final manager = $$IncomeTransactionsTableTableManager(
      $_db,
      $_db.incomeTransactions,
    ).filter((f) => f.journalEntryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _incomeTransactionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ExpensesTable, List<Expense>> _expensesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.expenses,
    aliasName: 'journal_entries__id__expenses__journal_entry_id',
  );

  $$ExpensesTableProcessedTableManager get expensesRefs {
    final manager = $$ExpensesTableTableManager(
      $_db,
      $_db.expenses,
    ).filter((f) => f.journalEntryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_expensesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$JournalEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $JournalEntriesTable> {
  $$JournalEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> ledgerLinesRefs(
    Expression<bool> Function($$LedgerLinesTableFilterComposer f) f,
  ) {
    final $$LedgerLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ledgerLines,
      getReferencedColumn: (t) => t.journalEntryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LedgerLinesTableFilterComposer(
            $db: $db,
            $table: $db.ledgerLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> incomeTransactionsRefs(
    Expression<bool> Function($$IncomeTransactionsTableFilterComposer f) f,
  ) {
    final $$IncomeTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.incomeTransactions,
      getReferencedColumn: (t) => t.journalEntryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IncomeTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.incomeTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> expensesRefs(
    Expression<bool> Function($$ExpensesTableFilterComposer f) f,
  ) {
    final $$ExpensesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.journalEntryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableFilterComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$JournalEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $JournalEntriesTable> {
  $$JournalEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JournalEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $JournalEntriesTable> {
  $$JournalEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get entryDate =>
      $composableBuilder(column: $table.entryDate, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> ledgerLinesRefs<T extends Object>(
    Expression<T> Function($$LedgerLinesTableAnnotationComposer a) f,
  ) {
    final $$LedgerLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ledgerLines,
      getReferencedColumn: (t) => t.journalEntryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LedgerLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.ledgerLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> incomeTransactionsRefs<T extends Object>(
    Expression<T> Function($$IncomeTransactionsTableAnnotationComposer a) f,
  ) {
    final $$IncomeTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.incomeTransactions,
          getReferencedColumn: (t) => t.journalEntryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$IncomeTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.incomeTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> expensesRefs<T extends Object>(
    Expression<T> Function($$ExpensesTableAnnotationComposer a) f,
  ) {
    final $$ExpensesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.journalEntryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableAnnotationComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$JournalEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $JournalEntriesTable,
          JournalEntry,
          $$JournalEntriesTableFilterComposer,
          $$JournalEntriesTableOrderingComposer,
          $$JournalEntriesTableAnnotationComposer,
          $$JournalEntriesTableCreateCompanionBuilder,
          $$JournalEntriesTableUpdateCompanionBuilder,
          (JournalEntry, $$JournalEntriesTableReferences),
          JournalEntry,
          PrefetchHooks Function({
            bool businessId,
            bool ledgerLinesRefs,
            bool incomeTransactionsRefs,
            bool expensesRefs,
          })
        > {
  $$JournalEntriesTableTableManager(
    _$AppDatabase db,
    $JournalEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JournalEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JournalEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JournalEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<DateTime> entryDate = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> sourceType = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesCompanion(
                id: id,
                businessId: businessId,
                entryDate: entryDate,
                description: description,
                sourceType: sourceType,
                sourceId: sourceId,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required DateTime entryDate,
                Value<String?> description = const Value.absent(),
                required String sourceType,
                Value<String?> sourceId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JournalEntriesCompanion.insert(
                id: id,
                businessId: businessId,
                entryDate: entryDate,
                description: description,
                sourceType: sourceType,
                sourceId: sourceId,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$JournalEntriesTable, JournalEntry>(table),
                  $$JournalEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                ledgerLinesRefs = false,
                incomeTransactionsRefs = false,
                expensesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (ledgerLinesRefs) db.ledgerLines,
                    if (incomeTransactionsRefs) db.incomeTransactions,
                    if (expensesRefs) db.expenses,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable:
                                        $$JournalEntriesTableReferences
                                            ._businessIdTable(db),
                                    referencedColumn:
                                        $$JournalEntriesTableReferences
                                            ._businessIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (ledgerLinesRefs)
                        await $_getPrefetchedData<
                          JournalEntry,
                          $JournalEntriesTable,
                          LedgerLine
                        >(
                          currentTable: table,
                          referencedTable: $$JournalEntriesTableReferences
                              ._ledgerLinesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$JournalEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).ledgerLinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.journalEntryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (incomeTransactionsRefs)
                        await $_getPrefetchedData<
                          JournalEntry,
                          $JournalEntriesTable,
                          IncomeTransaction
                        >(
                          currentTable: table,
                          referencedTable: $$JournalEntriesTableReferences
                              ._incomeTransactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$JournalEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).incomeTransactionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.journalEntryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (expensesRefs)
                        await $_getPrefetchedData<
                          JournalEntry,
                          $JournalEntriesTable,
                          Expense
                        >(
                          currentTable: table,
                          referencedTable: $$JournalEntriesTableReferences
                              ._expensesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$JournalEntriesTableReferences(
                                db,
                                table,
                                p0,
                              ).expensesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.journalEntryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$JournalEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $JournalEntriesTable,
      JournalEntry,
      $$JournalEntriesTableFilterComposer,
      $$JournalEntriesTableOrderingComposer,
      $$JournalEntriesTableAnnotationComposer,
      $$JournalEntriesTableCreateCompanionBuilder,
      $$JournalEntriesTableUpdateCompanionBuilder,
      (JournalEntry, $$JournalEntriesTableReferences),
      JournalEntry,
      PrefetchHooks Function({
        bool businessId,
        bool ledgerLinesRefs,
        bool incomeTransactionsRefs,
        bool expensesRefs,
      })
    >;
typedef $$LedgerLinesTableCreateCompanionBuilder =
    LedgerLinesCompanion Function({
      required String id,
      required String journalEntryId,
      required String accountId,
      Value<int> debit,
      Value<int> credit,
      Value<int> rowid,
    });
typedef $$LedgerLinesTableUpdateCompanionBuilder =
    LedgerLinesCompanion Function({
      Value<String> id,
      Value<String> journalEntryId,
      Value<String> accountId,
      Value<int> debit,
      Value<int> credit,
      Value<int> rowid,
    });

final class $$LedgerLinesTableReferences
    extends BaseReferences<_$AppDatabase, $LedgerLinesTable, LedgerLine> {
  $$LedgerLinesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $JournalEntriesTable _journalEntryIdTable(_$AppDatabase db) => db
      .journalEntries
      .createAlias('ledger_lines__journal_entry_id__journal_entries__id');

  $$JournalEntriesTableProcessedTableManager get journalEntryId {
    final $_column = $_itemColumn<String>('journal_entry_id')!;

    final manager = $$JournalEntriesTableTableManager(
      $_db,
      $_db.journalEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_journalEntryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _accountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('ledger_lines__account_id__accounts__id');

  $$AccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<String>('account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LedgerLinesTableFilterComposer
    extends Composer<_$AppDatabase, $LedgerLinesTable> {
  $$LedgerLinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get debit => $composableBuilder(
    column: $table.debit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get credit => $composableBuilder(
    column: $table.credit,
    builder: (column) => ColumnFilters(column),
  );

  $$JournalEntriesTableFilterComposer get journalEntryId {
    final $$JournalEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journalEntryId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableFilterComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get accountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LedgerLinesTableOrderingComposer
    extends Composer<_$AppDatabase, $LedgerLinesTable> {
  $$LedgerLinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get debit => $composableBuilder(
    column: $table.debit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get credit => $composableBuilder(
    column: $table.credit,
    builder: (column) => ColumnOrderings(column),
  );

  $$JournalEntriesTableOrderingComposer get journalEntryId {
    final $$JournalEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journalEntryId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get accountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LedgerLinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LedgerLinesTable> {
  $$LedgerLinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get debit =>
      $composableBuilder(column: $table.debit, builder: (column) => column);

  GeneratedColumn<int> get credit =>
      $composableBuilder(column: $table.credit, builder: (column) => column);

  $$JournalEntriesTableAnnotationComposer get journalEntryId {
    final $$JournalEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journalEntryId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get accountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LedgerLinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LedgerLinesTable,
          LedgerLine,
          $$LedgerLinesTableFilterComposer,
          $$LedgerLinesTableOrderingComposer,
          $$LedgerLinesTableAnnotationComposer,
          $$LedgerLinesTableCreateCompanionBuilder,
          $$LedgerLinesTableUpdateCompanionBuilder,
          (LedgerLine, $$LedgerLinesTableReferences),
          LedgerLine,
          PrefetchHooks Function({bool journalEntryId, bool accountId})
        > {
  $$LedgerLinesTableTableManager(_$AppDatabase db, $LedgerLinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LedgerLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LedgerLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LedgerLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> journalEntryId = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<int> debit = const Value.absent(),
                Value<int> credit = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LedgerLinesCompanion(
                id: id,
                journalEntryId: journalEntryId,
                accountId: accountId,
                debit: debit,
                credit: credit,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String journalEntryId,
                required String accountId,
                Value<int> debit = const Value.absent(),
                Value<int> credit = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LedgerLinesCompanion.insert(
                id: id,
                journalEntryId: journalEntryId,
                accountId: accountId,
                debit: debit,
                credit: credit,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LedgerLinesTable, LedgerLine>(table),
                  $$LedgerLinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({journalEntryId = false, accountId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (journalEntryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.journalEntryId,
                                referencedTable: $$LedgerLinesTableReferences
                                    ._journalEntryIdTable(db),
                                referencedColumn: $$LedgerLinesTableReferences
                                    ._journalEntryIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (accountId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.accountId,
                                referencedTable: $$LedgerLinesTableReferences
                                    ._accountIdTable(db),
                                referencedColumn: $$LedgerLinesTableReferences
                                    ._accountIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LedgerLinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LedgerLinesTable,
      LedgerLine,
      $$LedgerLinesTableFilterComposer,
      $$LedgerLinesTableOrderingComposer,
      $$LedgerLinesTableAnnotationComposer,
      $$LedgerLinesTableCreateCompanionBuilder,
      $$LedgerLinesTableUpdateCompanionBuilder,
      (LedgerLine, $$LedgerLinesTableReferences),
      LedgerLine,
      PrefetchHooks Function({bool journalEntryId, bool accountId})
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required String id,
      required String businessId,
      required String name,
      required String txnType,
      required String ledgerAccountId,
      Value<bool> isCustom,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> name,
      Value<String> txnType,
      Value<String> ledgerAccountId,
      Value<bool> isCustom,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $CategoriesTable, Category> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BusinessesTable _businessIdTable(_$AppDatabase db) =>
      db.businesses.createAlias('categories__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _ledgerAccountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('categories__ledger_account_id__accounts__id');

  $$AccountsTableProcessedTableManager get ledgerAccountId {
    final $_column = $_itemColumn<String>('ledger_account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ledgerAccountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$IncomeTransactionsTable, List<IncomeTransaction>>
  _incomeTransactionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.incomeTransactions,
        aliasName: 'categories__id__income_transactions__category_id',
      );

  $$IncomeTransactionsTableProcessedTableManager get incomeTransactionsRefs {
    final manager = $$IncomeTransactionsTableTableManager(
      $_db,
      $_db.incomeTransactions,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _incomeTransactionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ExpensesTable, List<Expense>> _expensesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.expenses,
    aliasName: 'categories__id__expenses__category_id',
  );

  $$ExpensesTableProcessedTableManager get expensesRefs {
    final manager = $$ExpensesTableTableManager(
      $_db,
      $_db.expenses,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_expensesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get txnType => $composableBuilder(
    column: $table.txnType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCustom => $composableBuilder(
    column: $table.isCustom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get ledgerAccountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ledgerAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> incomeTransactionsRefs(
    Expression<bool> Function($$IncomeTransactionsTableFilterComposer f) f,
  ) {
    final $$IncomeTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.incomeTransactions,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IncomeTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.incomeTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> expensesRefs(
    Expression<bool> Function($$ExpensesTableFilterComposer f) f,
  ) {
    final $$ExpensesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableFilterComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get txnType => $composableBuilder(
    column: $table.txnType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCustom => $composableBuilder(
    column: $table.isCustom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get ledgerAccountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ledgerAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get txnType =>
      $composableBuilder(column: $table.txnType, builder: (column) => column);

  GeneratedColumn<bool> get isCustom =>
      $composableBuilder(column: $table.isCustom, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get ledgerAccountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ledgerAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> incomeTransactionsRefs<T extends Object>(
    Expression<T> Function($$IncomeTransactionsTableAnnotationComposer a) f,
  ) {
    final $$IncomeTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.incomeTransactions,
          getReferencedColumn: (t) => t.categoryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$IncomeTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.incomeTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> expensesRefs<T extends Object>(
    Expression<T> Function($$ExpensesTableAnnotationComposer a) f,
  ) {
    final $$ExpensesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableAnnotationComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, $$CategoriesTableReferences),
          Category,
          PrefetchHooks Function({
            bool businessId,
            bool ledgerAccountId,
            bool incomeTransactionsRefs,
            bool expensesRefs,
          })
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> txnType = const Value.absent(),
                Value<String> ledgerAccountId = const Value.absent(),
                Value<bool> isCustom = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                businessId: businessId,
                name: name,
                txnType: txnType,
                ledgerAccountId: ledgerAccountId,
                isCustom: isCustom,
                isActive: isActive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String name,
                required String txnType,
                required String ledgerAccountId,
                Value<bool> isCustom = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                businessId: businessId,
                name: name,
                txnType: txnType,
                ledgerAccountId: ledgerAccountId,
                isCustom: isCustom,
                isActive: isActive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoriesTable, Category>(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                ledgerAccountId = false,
                incomeTransactionsRefs = false,
                expensesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (incomeTransactionsRefs) db.incomeTransactions,
                    if (expensesRefs) db.expenses,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable: $$CategoriesTableReferences
                                        ._businessIdTable(db),
                                    referencedColumn:
                                        $$CategoriesTableReferences
                                            ._businessIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (ledgerAccountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ledgerAccountId,
                                    referencedTable: $$CategoriesTableReferences
                                        ._ledgerAccountIdTable(db),
                                    referencedColumn:
                                        $$CategoriesTableReferences
                                            ._ledgerAccountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (incomeTransactionsRefs)
                        await $_getPrefetchedData<
                          Category,
                          $CategoriesTable,
                          IncomeTransaction
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._incomeTransactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).incomeTransactionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (expensesRefs)
                        await $_getPrefetchedData<
                          Category,
                          $CategoriesTable,
                          Expense
                        >(
                          currentTable: table,
                          referencedTable: $$CategoriesTableReferences
                              ._expensesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoriesTableReferences(
                                db,
                                table,
                                p0,
                              ).expensesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, $$CategoriesTableReferences),
      Category,
      PrefetchHooks Function({
        bool businessId,
        bool ledgerAccountId,
        bool incomeTransactionsRefs,
        bool expensesRefs,
      })
    >;
typedef $$CustomersTableCreateCompanionBuilder =
    CustomersCompanion Function({
      required String id,
      required String businessId,
      required String name,
      Value<String?> phone,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$CustomersTableUpdateCompanionBuilder =
    CustomersCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> name,
      Value<String?> phone,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$CustomersTableReferences
    extends BaseReferences<_$AppDatabase, $CustomersTable, Customer> {
  $$CustomersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BusinessesTable _businessIdTable(_$AppDatabase db) =>
      db.businesses.createAlias('customers__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$IncomeTransactionsTable, List<IncomeTransaction>>
  _incomeTransactionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.incomeTransactions,
        aliasName: 'customers__id__income_transactions__customer_id',
      );

  $$IncomeTransactionsTableProcessedTableManager get incomeTransactionsRefs {
    final manager = $$IncomeTransactionsTableTableManager(
      $_db,
      $_db.incomeTransactions,
    ).filter((f) => f.customerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _incomeTransactionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReceivablePaymentsTable, List<ReceivablePayment>>
  _receivablePaymentsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.receivablePayments,
        aliasName: 'customers__id__receivable_payments__customer_id',
      );

  $$ReceivablePaymentsTableProcessedTableManager get receivablePaymentsRefs {
    final manager = $$ReceivablePaymentsTableTableManager(
      $_db,
      $_db.receivablePayments,
    ).filter((f) => f.customerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _receivablePaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CustomersTableFilterComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> incomeTransactionsRefs(
    Expression<bool> Function($$IncomeTransactionsTableFilterComposer f) f,
  ) {
    final $$IncomeTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.incomeTransactions,
      getReferencedColumn: (t) => t.customerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IncomeTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.incomeTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> receivablePaymentsRefs(
    Expression<bool> Function($$ReceivablePaymentsTableFilterComposer f) f,
  ) {
    final $$ReceivablePaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.receivablePayments,
      getReferencedColumn: (t) => t.customerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReceivablePaymentsTableFilterComposer(
            $db: $db,
            $table: $db.receivablePayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CustomersTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CustomersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> incomeTransactionsRefs<T extends Object>(
    Expression<T> Function($$IncomeTransactionsTableAnnotationComposer a) f,
  ) {
    final $$IncomeTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.incomeTransactions,
          getReferencedColumn: (t) => t.customerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$IncomeTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.incomeTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> receivablePaymentsRefs<T extends Object>(
    Expression<T> Function($$ReceivablePaymentsTableAnnotationComposer a) f,
  ) {
    final $$ReceivablePaymentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.receivablePayments,
          getReferencedColumn: (t) => t.customerId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReceivablePaymentsTableAnnotationComposer(
                $db: $db,
                $table: $db.receivablePayments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CustomersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomersTable,
          Customer,
          $$CustomersTableFilterComposer,
          $$CustomersTableOrderingComposer,
          $$CustomersTableAnnotationComposer,
          $$CustomersTableCreateCompanionBuilder,
          $$CustomersTableUpdateCompanionBuilder,
          (Customer, $$CustomersTableReferences),
          Customer,
          PrefetchHooks Function({
            bool businessId,
            bool incomeTransactionsRefs,
            bool receivablePaymentsRefs,
          })
        > {
  $$CustomersTableTableManager(_$AppDatabase db, $CustomersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomersCompanion(
                id: id,
                businessId: businessId,
                name: name,
                phone: phone,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String name,
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomersCompanion.insert(
                id: id,
                businessId: businessId,
                name: name,
                phone: phone,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CustomersTable, Customer>(table),
                  $$CustomersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                incomeTransactionsRefs = false,
                receivablePaymentsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (incomeTransactionsRefs) db.incomeTransactions,
                    if (receivablePaymentsRefs) db.receivablePayments,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable: $$CustomersTableReferences
                                        ._businessIdTable(db),
                                    referencedColumn: $$CustomersTableReferences
                                        ._businessIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (incomeTransactionsRefs)
                        await $_getPrefetchedData<
                          Customer,
                          $CustomersTable,
                          IncomeTransaction
                        >(
                          currentTable: table,
                          referencedTable: $$CustomersTableReferences
                              ._incomeTransactionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CustomersTableReferences(
                                db,
                                table,
                                p0,
                              ).incomeTransactionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.customerId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (receivablePaymentsRefs)
                        await $_getPrefetchedData<
                          Customer,
                          $CustomersTable,
                          ReceivablePayment
                        >(
                          currentTable: table,
                          referencedTable: $$CustomersTableReferences
                              ._receivablePaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CustomersTableReferences(
                                db,
                                table,
                                p0,
                              ).receivablePaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.customerId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomersTable,
      Customer,
      $$CustomersTableFilterComposer,
      $$CustomersTableOrderingComposer,
      $$CustomersTableAnnotationComposer,
      $$CustomersTableCreateCompanionBuilder,
      $$CustomersTableUpdateCompanionBuilder,
      (Customer, $$CustomersTableReferences),
      Customer,
      PrefetchHooks Function({
        bool businessId,
        bool incomeTransactionsRefs,
        bool receivablePaymentsRefs,
      })
    >;
typedef $$IncomeTransactionsTableCreateCompanionBuilder =
    IncomeTransactionsCompanion Function({
      required String id,
      required String businessId,
      required DateTime txnDate,
      Value<String?> description,
      required String categoryId,
      required int amount,
      Value<String?> customerId,
      Value<String?> paymentAccountId,
      Value<String?> reference,
      Value<String?> notes,
      Value<String> status,
      Value<String?> journalEntryId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$IncomeTransactionsTableUpdateCompanionBuilder =
    IncomeTransactionsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<DateTime> txnDate,
      Value<String?> description,
      Value<String> categoryId,
      Value<int> amount,
      Value<String?> customerId,
      Value<String?> paymentAccountId,
      Value<String?> reference,
      Value<String?> notes,
      Value<String> status,
      Value<String?> journalEntryId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$IncomeTransactionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $IncomeTransactionsTable,
          IncomeTransaction
        > {
  $$IncomeTransactionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BusinessesTable _businessIdTable(_$AppDatabase db) => db.businesses
      .createAlias('income_transactions__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) => db.categories
      .createAlias('income_transactions__category_id__categories__id');

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<String>('category_id')!;

    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CustomersTable _customerIdTable(_$AppDatabase db) => db.customers
      .createAlias('income_transactions__customer_id__customers__id');

  $$CustomersTableProcessedTableManager? get customerId {
    final $_column = $_itemColumn<String>('customer_id');
    if ($_column == null) return null;
    final manager = $$CustomersTableTableManager(
      $_db,
      $_db.customers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_customerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _paymentAccountIdTable(_$AppDatabase db) => db.accounts
      .createAlias('income_transactions__payment_account_id__accounts__id');

  $$AccountsTableProcessedTableManager? get paymentAccountId {
    final $_column = $_itemColumn<String>('payment_account_id');
    if ($_column == null) return null;
    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_paymentAccountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $JournalEntriesTable _journalEntryIdTable(_$AppDatabase db) =>
      db.journalEntries.createAlias(
        'income_transactions__journal_entry_id__journal_entries__id',
      );

  $$JournalEntriesTableProcessedTableManager? get journalEntryId {
    final $_column = $_itemColumn<String>('journal_entry_id');
    if ($_column == null) return null;
    final manager = $$JournalEntriesTableTableManager(
      $_db,
      $_db.journalEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_journalEntryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$IncomeTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $IncomeTransactionsTable> {
  $$IncomeTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get txnDate => $composableBuilder(
    column: $table.txnDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableFilterComposer get customerId {
    final $$CustomersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableFilterComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get paymentAccountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$JournalEntriesTableFilterComposer get journalEntryId {
    final $$JournalEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journalEntryId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableFilterComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IncomeTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $IncomeTransactionsTable> {
  $$IncomeTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get txnDate => $composableBuilder(
    column: $table.txnDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableOrderingComposer get customerId {
    final $$CustomersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableOrderingComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get paymentAccountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$JournalEntriesTableOrderingComposer get journalEntryId {
    final $$JournalEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journalEntryId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IncomeTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $IncomeTransactionsTable> {
  $$IncomeTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get txnDate =>
      $composableBuilder(column: $table.txnDate, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableAnnotationComposer get customerId {
    final $$CustomersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableAnnotationComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get paymentAccountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$JournalEntriesTableAnnotationComposer get journalEntryId {
    final $$JournalEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journalEntryId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IncomeTransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IncomeTransactionsTable,
          IncomeTransaction,
          $$IncomeTransactionsTableFilterComposer,
          $$IncomeTransactionsTableOrderingComposer,
          $$IncomeTransactionsTableAnnotationComposer,
          $$IncomeTransactionsTableCreateCompanionBuilder,
          $$IncomeTransactionsTableUpdateCompanionBuilder,
          (IncomeTransaction, $$IncomeTransactionsTableReferences),
          IncomeTransaction,
          PrefetchHooks Function({
            bool businessId,
            bool categoryId,
            bool customerId,
            bool paymentAccountId,
            bool journalEntryId,
          })
        > {
  $$IncomeTransactionsTableTableManager(
    _$AppDatabase db,
    $IncomeTransactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IncomeTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IncomeTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IncomeTransactionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<DateTime> txnDate = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                Value<String?> paymentAccountId = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> journalEntryId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IncomeTransactionsCompanion(
                id: id,
                businessId: businessId,
                txnDate: txnDate,
                description: description,
                categoryId: categoryId,
                amount: amount,
                customerId: customerId,
                paymentAccountId: paymentAccountId,
                reference: reference,
                notes: notes,
                status: status,
                journalEntryId: journalEntryId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required DateTime txnDate,
                Value<String?> description = const Value.absent(),
                required String categoryId,
                required int amount,
                Value<String?> customerId = const Value.absent(),
                Value<String?> paymentAccountId = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> journalEntryId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IncomeTransactionsCompanion.insert(
                id: id,
                businessId: businessId,
                txnDate: txnDate,
                description: description,
                categoryId: categoryId,
                amount: amount,
                customerId: customerId,
                paymentAccountId: paymentAccountId,
                reference: reference,
                notes: notes,
                status: status,
                journalEntryId: journalEntryId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IncomeTransactionsTable, IncomeTransaction>(
                    table,
                  ),
                  $$IncomeTransactionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                categoryId = false,
                customerId = false,
                paymentAccountId = false,
                journalEntryId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable:
                                        $$IncomeTransactionsTableReferences
                                            ._businessIdTable(db),
                                    referencedColumn:
                                        $$IncomeTransactionsTableReferences
                                            ._businessIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable:
                                        $$IncomeTransactionsTableReferences
                                            ._categoryIdTable(db),
                                    referencedColumn:
                                        $$IncomeTransactionsTableReferences
                                            ._categoryIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (customerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.customerId,
                                    referencedTable:
                                        $$IncomeTransactionsTableReferences
                                            ._customerIdTable(db),
                                    referencedColumn:
                                        $$IncomeTransactionsTableReferences
                                            ._customerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (paymentAccountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.paymentAccountId,
                                    referencedTable:
                                        $$IncomeTransactionsTableReferences
                                            ._paymentAccountIdTable(db),
                                    referencedColumn:
                                        $$IncomeTransactionsTableReferences
                                            ._paymentAccountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (journalEntryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.journalEntryId,
                                    referencedTable:
                                        $$IncomeTransactionsTableReferences
                                            ._journalEntryIdTable(db),
                                    referencedColumn:
                                        $$IncomeTransactionsTableReferences
                                            ._journalEntryIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$IncomeTransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IncomeTransactionsTable,
      IncomeTransaction,
      $$IncomeTransactionsTableFilterComposer,
      $$IncomeTransactionsTableOrderingComposer,
      $$IncomeTransactionsTableAnnotationComposer,
      $$IncomeTransactionsTableCreateCompanionBuilder,
      $$IncomeTransactionsTableUpdateCompanionBuilder,
      (IncomeTransaction, $$IncomeTransactionsTableReferences),
      IncomeTransaction,
      PrefetchHooks Function({
        bool businessId,
        bool categoryId,
        bool customerId,
        bool paymentAccountId,
        bool journalEntryId,
      })
    >;
typedef $$ReceivablePaymentsTableCreateCompanionBuilder =
    ReceivablePaymentsCompanion Function({
      required String id,
      required String businessId,
      required String customerId,
      required int amount,
      required String paymentAccountId,
      required DateTime paymentDate,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ReceivablePaymentsTableUpdateCompanionBuilder =
    ReceivablePaymentsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> customerId,
      Value<int> amount,
      Value<String> paymentAccountId,
      Value<DateTime> paymentDate,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ReceivablePaymentsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReceivablePaymentsTable,
          ReceivablePayment
        > {
  $$ReceivablePaymentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BusinessesTable _businessIdTable(_$AppDatabase db) => db.businesses
      .createAlias('receivable_payments__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CustomersTable _customerIdTable(_$AppDatabase db) => db.customers
      .createAlias('receivable_payments__customer_id__customers__id');

  $$CustomersTableProcessedTableManager get customerId {
    final $_column = $_itemColumn<String>('customer_id')!;

    final manager = $$CustomersTableTableManager(
      $_db,
      $_db.customers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_customerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _paymentAccountIdTable(_$AppDatabase db) => db.accounts
      .createAlias('receivable_payments__payment_account_id__accounts__id');

  $$AccountsTableProcessedTableManager get paymentAccountId {
    final $_column = $_itemColumn<String>('payment_account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_paymentAccountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReceivablePaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $ReceivablePaymentsTable> {
  $$ReceivablePaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableFilterComposer get customerId {
    final $$CustomersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableFilterComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get paymentAccountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReceivablePaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReceivablePaymentsTable> {
  $$ReceivablePaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableOrderingComposer get customerId {
    final $$CustomersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableOrderingComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get paymentAccountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReceivablePaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReceivablePaymentsTable> {
  $$ReceivablePaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<DateTime> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CustomersTableAnnotationComposer get customerId {
    final $$CustomersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.customerId,
      referencedTable: $db.customers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CustomersTableAnnotationComposer(
            $db: $db,
            $table: $db.customers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get paymentAccountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReceivablePaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReceivablePaymentsTable,
          ReceivablePayment,
          $$ReceivablePaymentsTableFilterComposer,
          $$ReceivablePaymentsTableOrderingComposer,
          $$ReceivablePaymentsTableAnnotationComposer,
          $$ReceivablePaymentsTableCreateCompanionBuilder,
          $$ReceivablePaymentsTableUpdateCompanionBuilder,
          (ReceivablePayment, $$ReceivablePaymentsTableReferences),
          ReceivablePayment,
          PrefetchHooks Function({
            bool businessId,
            bool customerId,
            bool paymentAccountId,
          })
        > {
  $$ReceivablePaymentsTableTableManager(
    _$AppDatabase db,
    $ReceivablePaymentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReceivablePaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReceivablePaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReceivablePaymentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> customerId = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<String> paymentAccountId = const Value.absent(),
                Value<DateTime> paymentDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceivablePaymentsCompanion(
                id: id,
                businessId: businessId,
                customerId: customerId,
                amount: amount,
                paymentAccountId: paymentAccountId,
                paymentDate: paymentDate,
                notes: notes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String customerId,
                required int amount,
                required String paymentAccountId,
                required DateTime paymentDate,
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReceivablePaymentsCompanion.insert(
                id: id,
                businessId: businessId,
                customerId: customerId,
                amount: amount,
                paymentAccountId: paymentAccountId,
                paymentDate: paymentDate,
                notes: notes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReceivablePaymentsTable, ReceivablePayment>(
                    table,
                  ),
                  $$ReceivablePaymentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                customerId = false,
                paymentAccountId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable:
                                        $$ReceivablePaymentsTableReferences
                                            ._businessIdTable(db),
                                    referencedColumn:
                                        $$ReceivablePaymentsTableReferences
                                            ._businessIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (customerId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.customerId,
                                    referencedTable:
                                        $$ReceivablePaymentsTableReferences
                                            ._customerIdTable(db),
                                    referencedColumn:
                                        $$ReceivablePaymentsTableReferences
                                            ._customerIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (paymentAccountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.paymentAccountId,
                                    referencedTable:
                                        $$ReceivablePaymentsTableReferences
                                            ._paymentAccountIdTable(db),
                                    referencedColumn:
                                        $$ReceivablePaymentsTableReferences
                                            ._paymentAccountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$ReceivablePaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReceivablePaymentsTable,
      ReceivablePayment,
      $$ReceivablePaymentsTableFilterComposer,
      $$ReceivablePaymentsTableOrderingComposer,
      $$ReceivablePaymentsTableAnnotationComposer,
      $$ReceivablePaymentsTableCreateCompanionBuilder,
      $$ReceivablePaymentsTableUpdateCompanionBuilder,
      (ReceivablePayment, $$ReceivablePaymentsTableReferences),
      ReceivablePayment,
      PrefetchHooks Function({
        bool businessId,
        bool customerId,
        bool paymentAccountId,
      })
    >;
typedef $$SuppliersTableCreateCompanionBuilder =
    SuppliersCompanion Function({
      required String id,
      required String businessId,
      required String name,
      Value<String?> phone,
      Value<String?> address,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$SuppliersTableUpdateCompanionBuilder =
    SuppliersCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> name,
      Value<String?> phone,
      Value<String?> address,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$SuppliersTableReferences
    extends BaseReferences<_$AppDatabase, $SuppliersTable, Supplier> {
  $$SuppliersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BusinessesTable _businessIdTable(_$AppDatabase db) =>
      db.businesses.createAlias('suppliers__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SupplierPurchasesTable, List<SupplierPurchase>>
  _supplierPurchasesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.supplierPurchases,
        aliasName: 'suppliers__id__supplier_purchases__supplier_id',
      );

  $$SupplierPurchasesTableProcessedTableManager get supplierPurchasesRefs {
    final manager = $$SupplierPurchasesTableTableManager(
      $_db,
      $_db.supplierPurchases,
    ).filter((f) => f.supplierId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _supplierPurchasesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PayablePaymentsTable, List<PayablePayment>>
  _payablePaymentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.payablePayments,
    aliasName: 'suppliers__id__payable_payments__supplier_id',
  );

  $$PayablePaymentsTableProcessedTableManager get payablePaymentsRefs {
    final manager = $$PayablePaymentsTableTableManager(
      $_db,
      $_db.payablePayments,
    ).filter((f) => f.supplierId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _payablePaymentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $SupplyPriceHistoryTable,
    List<SupplyPriceHistoryData>
  >
  _supplyPriceHistoryRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.supplyPriceHistory,
        aliasName: 'suppliers__id__supply_price_history__supplier_id',
      );

  $$SupplyPriceHistoryTableProcessedTableManager get supplyPriceHistoryRefs {
    final manager = $$SupplyPriceHistoryTableTableManager(
      $_db,
      $_db.supplyPriceHistory,
    ).filter((f) => f.supplierId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _supplyPriceHistoryRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SuppliersTableFilterComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> supplierPurchasesRefs(
    Expression<bool> Function($$SupplierPurchasesTableFilterComposer f) f,
  ) {
    final $$SupplierPurchasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.supplierPurchases,
      getReferencedColumn: (t) => t.supplierId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SupplierPurchasesTableFilterComposer(
            $db: $db,
            $table: $db.supplierPurchases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> payablePaymentsRefs(
    Expression<bool> Function($$PayablePaymentsTableFilterComposer f) f,
  ) {
    final $$PayablePaymentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payablePayments,
      getReferencedColumn: (t) => t.supplierId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PayablePaymentsTableFilterComposer(
            $db: $db,
            $table: $db.payablePayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> supplyPriceHistoryRefs(
    Expression<bool> Function($$SupplyPriceHistoryTableFilterComposer f) f,
  ) {
    final $$SupplyPriceHistoryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.supplyPriceHistory,
      getReferencedColumn: (t) => t.supplierId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SupplyPriceHistoryTableFilterComposer(
            $db: $db,
            $table: $db.supplyPriceHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SuppliersTableOrderingComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SuppliersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SuppliersTable> {
  $$SuppliersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> supplierPurchasesRefs<T extends Object>(
    Expression<T> Function($$SupplierPurchasesTableAnnotationComposer a) f,
  ) {
    final $$SupplierPurchasesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.supplierPurchases,
          getReferencedColumn: (t) => t.supplierId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SupplierPurchasesTableAnnotationComposer(
                $db: $db,
                $table: $db.supplierPurchases,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> payablePaymentsRefs<T extends Object>(
    Expression<T> Function($$PayablePaymentsTableAnnotationComposer a) f,
  ) {
    final $$PayablePaymentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.payablePayments,
      getReferencedColumn: (t) => t.supplierId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PayablePaymentsTableAnnotationComposer(
            $db: $db,
            $table: $db.payablePayments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> supplyPriceHistoryRefs<T extends Object>(
    Expression<T> Function($$SupplyPriceHistoryTableAnnotationComposer a) f,
  ) {
    final $$SupplyPriceHistoryTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.supplyPriceHistory,
          getReferencedColumn: (t) => t.supplierId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SupplyPriceHistoryTableAnnotationComposer(
                $db: $db,
                $table: $db.supplyPriceHistory,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SuppliersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SuppliersTable,
          Supplier,
          $$SuppliersTableFilterComposer,
          $$SuppliersTableOrderingComposer,
          $$SuppliersTableAnnotationComposer,
          $$SuppliersTableCreateCompanionBuilder,
          $$SuppliersTableUpdateCompanionBuilder,
          (Supplier, $$SuppliersTableReferences),
          Supplier,
          PrefetchHooks Function({
            bool businessId,
            bool supplierPurchasesRefs,
            bool payablePaymentsRefs,
            bool supplyPriceHistoryRefs,
          })
        > {
  $$SuppliersTableTableManager(_$AppDatabase db, $SuppliersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SuppliersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SuppliersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SuppliersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SuppliersCompanion(
                id: id,
                businessId: businessId,
                name: name,
                phone: phone,
                address: address,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String name,
                Value<String?> phone = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SuppliersCompanion.insert(
                id: id,
                businessId: businessId,
                name: name,
                phone: phone,
                address: address,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SuppliersTable, Supplier>(table),
                  $$SuppliersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                supplierPurchasesRefs = false,
                payablePaymentsRefs = false,
                supplyPriceHistoryRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (supplierPurchasesRefs) db.supplierPurchases,
                    if (payablePaymentsRefs) db.payablePayments,
                    if (supplyPriceHistoryRefs) db.supplyPriceHistory,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable: $$SuppliersTableReferences
                                        ._businessIdTable(db),
                                    referencedColumn: $$SuppliersTableReferences
                                        ._businessIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (supplierPurchasesRefs)
                        await $_getPrefetchedData<
                          Supplier,
                          $SuppliersTable,
                          SupplierPurchase
                        >(
                          currentTable: table,
                          referencedTable: $$SuppliersTableReferences
                              ._supplierPurchasesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SuppliersTableReferences(
                                db,
                                table,
                                p0,
                              ).supplierPurchasesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.supplierId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (payablePaymentsRefs)
                        await $_getPrefetchedData<
                          Supplier,
                          $SuppliersTable,
                          PayablePayment
                        >(
                          currentTable: table,
                          referencedTable: $$SuppliersTableReferences
                              ._payablePaymentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SuppliersTableReferences(
                                db,
                                table,
                                p0,
                              ).payablePaymentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.supplierId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (supplyPriceHistoryRefs)
                        await $_getPrefetchedData<
                          Supplier,
                          $SuppliersTable,
                          SupplyPriceHistoryData
                        >(
                          currentTable: table,
                          referencedTable: $$SuppliersTableReferences
                              ._supplyPriceHistoryRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SuppliersTableReferences(
                                db,
                                table,
                                p0,
                              ).supplyPriceHistoryRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.supplierId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SuppliersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SuppliersTable,
      Supplier,
      $$SuppliersTableFilterComposer,
      $$SuppliersTableOrderingComposer,
      $$SuppliersTableAnnotationComposer,
      $$SuppliersTableCreateCompanionBuilder,
      $$SuppliersTableUpdateCompanionBuilder,
      (Supplier, $$SuppliersTableReferences),
      Supplier,
      PrefetchHooks Function({
        bool businessId,
        bool supplierPurchasesRefs,
        bool payablePaymentsRefs,
        bool supplyPriceHistoryRefs,
      })
    >;
typedef $$SupplierPurchasesTableCreateCompanionBuilder =
    SupplierPurchasesCompanion Function({
      required String id,
      required String businessId,
      required String supplierId,
      required DateTime purchaseDate,
      required int amount,
      Value<bool> isOnCredit,
      Value<String?> paymentAccountId,
      Value<String?> notes,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$SupplierPurchasesTableUpdateCompanionBuilder =
    SupplierPurchasesCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> supplierId,
      Value<DateTime> purchaseDate,
      Value<int> amount,
      Value<bool> isOnCredit,
      Value<String?> paymentAccountId,
      Value<String?> notes,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$SupplierPurchasesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $SupplierPurchasesTable,
          SupplierPurchase
        > {
  $$SupplierPurchasesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BusinessesTable _businessIdTable(_$AppDatabase db) => db.businesses
      .createAlias('supplier_purchases__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SuppliersTable _supplierIdTable(_$AppDatabase db) => db.suppliers
      .createAlias('supplier_purchases__supplier_id__suppliers__id');

  $$SuppliersTableProcessedTableManager get supplierId {
    final $_column = $_itemColumn<String>('supplier_id')!;

    final manager = $$SuppliersTableTableManager(
      $_db,
      $_db.suppliers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_supplierIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _paymentAccountIdTable(_$AppDatabase db) => db.accounts
      .createAlias('supplier_purchases__payment_account_id__accounts__id');

  $$AccountsTableProcessedTableManager? get paymentAccountId {
    final $_column = $_itemColumn<String>('payment_account_id');
    if ($_column == null) return null;
    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_paymentAccountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SupplierPurchasesTableFilterComposer
    extends Composer<_$AppDatabase, $SupplierPurchasesTable> {
  $$SupplierPurchasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOnCredit => $composableBuilder(
    column: $table.isOnCredit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableFilterComposer get supplierId {
    final $$SuppliersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableFilterComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get paymentAccountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SupplierPurchasesTableOrderingComposer
    extends Composer<_$AppDatabase, $SupplierPurchasesTable> {
  $$SupplierPurchasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOnCredit => $composableBuilder(
    column: $table.isOnCredit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableOrderingComposer get supplierId {
    final $$SuppliersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableOrderingComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get paymentAccountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SupplierPurchasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SupplierPurchasesTable> {
  $$SupplierPurchasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<bool> get isOnCredit => $composableBuilder(
    column: $table.isOnCredit,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableAnnotationComposer get supplierId {
    final $$SuppliersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableAnnotationComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get paymentAccountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SupplierPurchasesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SupplierPurchasesTable,
          SupplierPurchase,
          $$SupplierPurchasesTableFilterComposer,
          $$SupplierPurchasesTableOrderingComposer,
          $$SupplierPurchasesTableAnnotationComposer,
          $$SupplierPurchasesTableCreateCompanionBuilder,
          $$SupplierPurchasesTableUpdateCompanionBuilder,
          (SupplierPurchase, $$SupplierPurchasesTableReferences),
          SupplierPurchase,
          PrefetchHooks Function({
            bool businessId,
            bool supplierId,
            bool paymentAccountId,
          })
        > {
  $$SupplierPurchasesTableTableManager(
    _$AppDatabase db,
    $SupplierPurchasesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SupplierPurchasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SupplierPurchasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SupplierPurchasesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> supplierId = const Value.absent(),
                Value<DateTime> purchaseDate = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<bool> isOnCredit = const Value.absent(),
                Value<String?> paymentAccountId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SupplierPurchasesCompanion(
                id: id,
                businessId: businessId,
                supplierId: supplierId,
                purchaseDate: purchaseDate,
                amount: amount,
                isOnCredit: isOnCredit,
                paymentAccountId: paymentAccountId,
                notes: notes,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String supplierId,
                required DateTime purchaseDate,
                required int amount,
                Value<bool> isOnCredit = const Value.absent(),
                Value<String?> paymentAccountId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SupplierPurchasesCompanion.insert(
                id: id,
                businessId: businessId,
                supplierId: supplierId,
                purchaseDate: purchaseDate,
                amount: amount,
                isOnCredit: isOnCredit,
                paymentAccountId: paymentAccountId,
                notes: notes,
                status: status,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SupplierPurchasesTable, SupplierPurchase>(table),
                  $$SupplierPurchasesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                supplierId = false,
                paymentAccountId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable:
                                        $$SupplierPurchasesTableReferences
                                            ._businessIdTable(db),
                                    referencedColumn:
                                        $$SupplierPurchasesTableReferences
                                            ._businessIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (supplierId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.supplierId,
                                    referencedTable:
                                        $$SupplierPurchasesTableReferences
                                            ._supplierIdTable(db),
                                    referencedColumn:
                                        $$SupplierPurchasesTableReferences
                                            ._supplierIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (paymentAccountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.paymentAccountId,
                                    referencedTable:
                                        $$SupplierPurchasesTableReferences
                                            ._paymentAccountIdTable(db),
                                    referencedColumn:
                                        $$SupplierPurchasesTableReferences
                                            ._paymentAccountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$SupplierPurchasesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SupplierPurchasesTable,
      SupplierPurchase,
      $$SupplierPurchasesTableFilterComposer,
      $$SupplierPurchasesTableOrderingComposer,
      $$SupplierPurchasesTableAnnotationComposer,
      $$SupplierPurchasesTableCreateCompanionBuilder,
      $$SupplierPurchasesTableUpdateCompanionBuilder,
      (SupplierPurchase, $$SupplierPurchasesTableReferences),
      SupplierPurchase,
      PrefetchHooks Function({
        bool businessId,
        bool supplierId,
        bool paymentAccountId,
      })
    >;
typedef $$PayablePaymentsTableCreateCompanionBuilder =
    PayablePaymentsCompanion Function({
      required String id,
      required String businessId,
      required String supplierId,
      required int amount,
      required String paymentAccountId,
      required DateTime paymentDate,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$PayablePaymentsTableUpdateCompanionBuilder =
    PayablePaymentsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> supplierId,
      Value<int> amount,
      Value<String> paymentAccountId,
      Value<DateTime> paymentDate,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$PayablePaymentsTableReferences
    extends
        BaseReferences<_$AppDatabase, $PayablePaymentsTable, PayablePayment> {
  $$PayablePaymentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BusinessesTable _businessIdTable(_$AppDatabase db) => db.businesses
      .createAlias('payable_payments__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SuppliersTable _supplierIdTable(_$AppDatabase db) =>
      db.suppliers.createAlias('payable_payments__supplier_id__suppliers__id');

  $$SuppliersTableProcessedTableManager get supplierId {
    final $_column = $_itemColumn<String>('supplier_id')!;

    final manager = $$SuppliersTableTableManager(
      $_db,
      $_db.suppliers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_supplierIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _paymentAccountIdTable(_$AppDatabase db) => db.accounts
      .createAlias('payable_payments__payment_account_id__accounts__id');

  $$AccountsTableProcessedTableManager get paymentAccountId {
    final $_column = $_itemColumn<String>('payment_account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_paymentAccountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PayablePaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $PayablePaymentsTable> {
  $$PayablePaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableFilterComposer get supplierId {
    final $$SuppliersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableFilterComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get paymentAccountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PayablePaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $PayablePaymentsTable> {
  $$PayablePaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableOrderingComposer get supplierId {
    final $$SuppliersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableOrderingComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get paymentAccountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PayablePaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PayablePaymentsTable> {
  $$PayablePaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<DateTime> get paymentDate => $composableBuilder(
    column: $table.paymentDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableAnnotationComposer get supplierId {
    final $$SuppliersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableAnnotationComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get paymentAccountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PayablePaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PayablePaymentsTable,
          PayablePayment,
          $$PayablePaymentsTableFilterComposer,
          $$PayablePaymentsTableOrderingComposer,
          $$PayablePaymentsTableAnnotationComposer,
          $$PayablePaymentsTableCreateCompanionBuilder,
          $$PayablePaymentsTableUpdateCompanionBuilder,
          (PayablePayment, $$PayablePaymentsTableReferences),
          PayablePayment,
          PrefetchHooks Function({
            bool businessId,
            bool supplierId,
            bool paymentAccountId,
          })
        > {
  $$PayablePaymentsTableTableManager(
    _$AppDatabase db,
    $PayablePaymentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PayablePaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PayablePaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PayablePaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> supplierId = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<String> paymentAccountId = const Value.absent(),
                Value<DateTime> paymentDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PayablePaymentsCompanion(
                id: id,
                businessId: businessId,
                supplierId: supplierId,
                amount: amount,
                paymentAccountId: paymentAccountId,
                paymentDate: paymentDate,
                notes: notes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String supplierId,
                required int amount,
                required String paymentAccountId,
                required DateTime paymentDate,
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PayablePaymentsCompanion.insert(
                id: id,
                businessId: businessId,
                supplierId: supplierId,
                amount: amount,
                paymentAccountId: paymentAccountId,
                paymentDate: paymentDate,
                notes: notes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PayablePaymentsTable, PayablePayment>(table),
                  $$PayablePaymentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                supplierId = false,
                paymentAccountId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable:
                                        $$PayablePaymentsTableReferences
                                            ._businessIdTable(db),
                                    referencedColumn:
                                        $$PayablePaymentsTableReferences
                                            ._businessIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (supplierId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.supplierId,
                                    referencedTable:
                                        $$PayablePaymentsTableReferences
                                            ._supplierIdTable(db),
                                    referencedColumn:
                                        $$PayablePaymentsTableReferences
                                            ._supplierIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (paymentAccountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.paymentAccountId,
                                    referencedTable:
                                        $$PayablePaymentsTableReferences
                                            ._paymentAccountIdTable(db),
                                    referencedColumn:
                                        $$PayablePaymentsTableReferences
                                            ._paymentAccountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$PayablePaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PayablePaymentsTable,
      PayablePayment,
      $$PayablePaymentsTableFilterComposer,
      $$PayablePaymentsTableOrderingComposer,
      $$PayablePaymentsTableAnnotationComposer,
      $$PayablePaymentsTableCreateCompanionBuilder,
      $$PayablePaymentsTableUpdateCompanionBuilder,
      (PayablePayment, $$PayablePaymentsTableReferences),
      PayablePayment,
      PrefetchHooks Function({
        bool businessId,
        bool supplierId,
        bool paymentAccountId,
      })
    >;
typedef $$ExpensesTableCreateCompanionBuilder =
    ExpensesCompanion Function({
      required String id,
      required String businessId,
      required DateTime expenseDate,
      Value<String?> description,
      required String categoryId,
      required int amount,
      Value<String?> paymentAccountId,
      Value<String?> receiptPhotoPath,
      Value<String?> reference,
      Value<String?> notes,
      Value<String> status,
      Value<String?> journalEntryId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ExpensesTableUpdateCompanionBuilder =
    ExpensesCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<DateTime> expenseDate,
      Value<String?> description,
      Value<String> categoryId,
      Value<int> amount,
      Value<String?> paymentAccountId,
      Value<String?> receiptPhotoPath,
      Value<String?> reference,
      Value<String?> notes,
      Value<String> status,
      Value<String?> journalEntryId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ExpensesTableReferences
    extends BaseReferences<_$AppDatabase, $ExpensesTable, Expense> {
  $$ExpensesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BusinessesTable _businessIdTable(_$AppDatabase db) =>
      db.businesses.createAlias('expenses__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias('expenses__category_id__categories__id');

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<String>('category_id')!;

    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _paymentAccountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('expenses__payment_account_id__accounts__id');

  $$AccountsTableProcessedTableManager? get paymentAccountId {
    final $_column = $_itemColumn<String>('payment_account_id');
    if ($_column == null) return null;
    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_paymentAccountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $JournalEntriesTable _journalEntryIdTable(_$AppDatabase db) => db
      .journalEntries
      .createAlias('expenses__journal_entry_id__journal_entries__id');

  $$JournalEntriesTableProcessedTableManager? get journalEntryId {
    final $_column = $_itemColumn<String>('journal_entry_id');
    if ($_column == null) return null;
    final manager = $$JournalEntriesTableTableManager(
      $_db,
      $_db.journalEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_journalEntryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ShoppingCartsTable, List<ShoppingCart>>
  _shoppingCartsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.shoppingCarts,
    aliasName: 'expenses__id__shopping_carts__expense_id',
  );

  $$ShoppingCartsTableProcessedTableManager get shoppingCartsRefs {
    final manager = $$ShoppingCartsTableTableManager(
      $_db,
      $_db.shoppingCarts,
    ).filter((f) => f.expenseId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_shoppingCartsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ExpensesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptPhotoPath => $composableBuilder(
    column: $table.receiptPhotoPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get paymentAccountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$JournalEntriesTableFilterComposer get journalEntryId {
    final $$JournalEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journalEntryId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableFilterComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> shoppingCartsRefs(
    Expression<bool> Function($$ShoppingCartsTableFilterComposer f) f,
  ) {
    final $$ShoppingCartsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingCarts,
      getReferencedColumn: (t) => t.expenseId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingCartsTableFilterComposer(
            $db: $db,
            $table: $db.shoppingCarts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExpensesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptPhotoPath => $composableBuilder(
    column: $table.receiptPhotoPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get paymentAccountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$JournalEntriesTableOrderingComposer get journalEntryId {
    final $$JournalEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journalEntryId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExpensesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get receiptPhotoPath => $composableBuilder(
    column: $table.receiptPhotoPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get paymentAccountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.paymentAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$JournalEntriesTableAnnotationComposer get journalEntryId {
    final $$JournalEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.journalEntryId,
      referencedTable: $db.journalEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JournalEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.journalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> shoppingCartsRefs<T extends Object>(
    Expression<T> Function($$ShoppingCartsTableAnnotationComposer a) f,
  ) {
    final $$ShoppingCartsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingCarts,
      getReferencedColumn: (t) => t.expenseId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingCartsTableAnnotationComposer(
            $db: $db,
            $table: $db.shoppingCarts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExpensesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpensesTable,
          Expense,
          $$ExpensesTableFilterComposer,
          $$ExpensesTableOrderingComposer,
          $$ExpensesTableAnnotationComposer,
          $$ExpensesTableCreateCompanionBuilder,
          $$ExpensesTableUpdateCompanionBuilder,
          (Expense, $$ExpensesTableReferences),
          Expense,
          PrefetchHooks Function({
            bool businessId,
            bool categoryId,
            bool paymentAccountId,
            bool journalEntryId,
            bool shoppingCartsRefs,
          })
        > {
  $$ExpensesTableTableManager(_$AppDatabase db, $ExpensesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<DateTime> expenseDate = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<String?> paymentAccountId = const Value.absent(),
                Value<String?> receiptPhotoPath = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> journalEntryId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpensesCompanion(
                id: id,
                businessId: businessId,
                expenseDate: expenseDate,
                description: description,
                categoryId: categoryId,
                amount: amount,
                paymentAccountId: paymentAccountId,
                receiptPhotoPath: receiptPhotoPath,
                reference: reference,
                notes: notes,
                status: status,
                journalEntryId: journalEntryId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required DateTime expenseDate,
                Value<String?> description = const Value.absent(),
                required String categoryId,
                required int amount,
                Value<String?> paymentAccountId = const Value.absent(),
                Value<String?> receiptPhotoPath = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> journalEntryId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpensesCompanion.insert(
                id: id,
                businessId: businessId,
                expenseDate: expenseDate,
                description: description,
                categoryId: categoryId,
                amount: amount,
                paymentAccountId: paymentAccountId,
                receiptPhotoPath: receiptPhotoPath,
                reference: reference,
                notes: notes,
                status: status,
                journalEntryId: journalEntryId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExpensesTable, Expense>(table),
                  $$ExpensesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                categoryId = false,
                paymentAccountId = false,
                journalEntryId = false,
                shoppingCartsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (shoppingCartsRefs) db.shoppingCarts,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable: $$ExpensesTableReferences
                                        ._businessIdTable(db),
                                    referencedColumn: $$ExpensesTableReferences
                                        ._businessIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable: $$ExpensesTableReferences
                                        ._categoryIdTable(db),
                                    referencedColumn: $$ExpensesTableReferences
                                        ._categoryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (paymentAccountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.paymentAccountId,
                                    referencedTable: $$ExpensesTableReferences
                                        ._paymentAccountIdTable(db),
                                    referencedColumn: $$ExpensesTableReferences
                                        ._paymentAccountIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (journalEntryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.journalEntryId,
                                    referencedTable: $$ExpensesTableReferences
                                        ._journalEntryIdTable(db),
                                    referencedColumn: $$ExpensesTableReferences
                                        ._journalEntryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (shoppingCartsRefs)
                        await $_getPrefetchedData<
                          Expense,
                          $ExpensesTable,
                          ShoppingCart
                        >(
                          currentTable: table,
                          referencedTable: $$ExpensesTableReferences
                              ._shoppingCartsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExpensesTableReferences(
                                db,
                                table,
                                p0,
                              ).shoppingCartsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.expenseId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ExpensesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpensesTable,
      Expense,
      $$ExpensesTableFilterComposer,
      $$ExpensesTableOrderingComposer,
      $$ExpensesTableAnnotationComposer,
      $$ExpensesTableCreateCompanionBuilder,
      $$ExpensesTableUpdateCompanionBuilder,
      (Expense, $$ExpensesTableReferences),
      Expense,
      PrefetchHooks Function({
        bool businessId,
        bool categoryId,
        bool paymentAccountId,
        bool journalEntryId,
        bool shoppingCartsRefs,
      })
    >;
typedef $$SuppliesTableCreateCompanionBuilder =
    SuppliesCompanion Function({
      required String id,
      required String businessId,
      required String name,
      Value<String?> brand,
      Value<double?> unitQuantity,
      Value<String?> unit,
      Value<String?> lastStoreName,
      Value<String?> lastStoreAddress,
      required int currentPrice,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SuppliesTableUpdateCompanionBuilder =
    SuppliesCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> name,
      Value<String?> brand,
      Value<double?> unitQuantity,
      Value<String?> unit,
      Value<String?> lastStoreName,
      Value<String?> lastStoreAddress,
      Value<int> currentPrice,
      Value<String?> notes,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$SuppliesTableReferences
    extends BaseReferences<_$AppDatabase, $SuppliesTable, Supply> {
  $$SuppliesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BusinessesTable _businessIdTable(_$AppDatabase db) =>
      db.businesses.createAlias('supplies__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $SupplyPriceHistoryTable,
    List<SupplyPriceHistoryData>
  >
  _supplyPriceHistoryRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.supplyPriceHistory,
        aliasName: 'supplies__id__supply_price_history__supply_id',
      );

  $$SupplyPriceHistoryTableProcessedTableManager get supplyPriceHistoryRefs {
    final manager = $$SupplyPriceHistoryTableTableManager(
      $_db,
      $_db.supplyPriceHistory,
    ).filter((f) => f.supplyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _supplyPriceHistoryRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ShoppingCartItemsTable, List<ShoppingCartItem>>
  _shoppingCartItemsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.shoppingCartItems,
        aliasName: 'supplies__id__shopping_cart_items__supply_id',
      );

  $$ShoppingCartItemsTableProcessedTableManager get shoppingCartItemsRefs {
    final manager = $$ShoppingCartItemsTableTableManager(
      $_db,
      $_db.shoppingCartItems,
    ).filter((f) => f.supplyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _shoppingCartItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SuppliesTableFilterComposer
    extends Composer<_$AppDatabase, $SuppliesTable> {
  $$SuppliesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitQuantity => $composableBuilder(
    column: $table.unitQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastStoreName => $composableBuilder(
    column: $table.lastStoreName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastStoreAddress => $composableBuilder(
    column: $table.lastStoreAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentPrice => $composableBuilder(
    column: $table.currentPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> supplyPriceHistoryRefs(
    Expression<bool> Function($$SupplyPriceHistoryTableFilterComposer f) f,
  ) {
    final $$SupplyPriceHistoryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.supplyPriceHistory,
      getReferencedColumn: (t) => t.supplyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SupplyPriceHistoryTableFilterComposer(
            $db: $db,
            $table: $db.supplyPriceHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> shoppingCartItemsRefs(
    Expression<bool> Function($$ShoppingCartItemsTableFilterComposer f) f,
  ) {
    final $$ShoppingCartItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingCartItems,
      getReferencedColumn: (t) => t.supplyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingCartItemsTableFilterComposer(
            $db: $db,
            $table: $db.shoppingCartItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SuppliesTableOrderingComposer
    extends Composer<_$AppDatabase, $SuppliesTable> {
  $$SuppliesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitQuantity => $composableBuilder(
    column: $table.unitQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastStoreName => $composableBuilder(
    column: $table.lastStoreName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastStoreAddress => $composableBuilder(
    column: $table.lastStoreAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentPrice => $composableBuilder(
    column: $table.currentPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SuppliesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SuppliesTable> {
  $$SuppliesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<double> get unitQuantity => $composableBuilder(
    column: $table.unitQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get lastStoreName => $composableBuilder(
    column: $table.lastStoreName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastStoreAddress => $composableBuilder(
    column: $table.lastStoreAddress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentPrice => $composableBuilder(
    column: $table.currentPrice,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> supplyPriceHistoryRefs<T extends Object>(
    Expression<T> Function($$SupplyPriceHistoryTableAnnotationComposer a) f,
  ) {
    final $$SupplyPriceHistoryTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.supplyPriceHistory,
          getReferencedColumn: (t) => t.supplyId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SupplyPriceHistoryTableAnnotationComposer(
                $db: $db,
                $table: $db.supplyPriceHistory,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> shoppingCartItemsRefs<T extends Object>(
    Expression<T> Function($$ShoppingCartItemsTableAnnotationComposer a) f,
  ) {
    final $$ShoppingCartItemsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.shoppingCartItems,
          getReferencedColumn: (t) => t.supplyId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ShoppingCartItemsTableAnnotationComposer(
                $db: $db,
                $table: $db.shoppingCartItems,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SuppliesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SuppliesTable,
          Supply,
          $$SuppliesTableFilterComposer,
          $$SuppliesTableOrderingComposer,
          $$SuppliesTableAnnotationComposer,
          $$SuppliesTableCreateCompanionBuilder,
          $$SuppliesTableUpdateCompanionBuilder,
          (Supply, $$SuppliesTableReferences),
          Supply,
          PrefetchHooks Function({
            bool businessId,
            bool supplyPriceHistoryRefs,
            bool shoppingCartItemsRefs,
          })
        > {
  $$SuppliesTableTableManager(_$AppDatabase db, $SuppliesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SuppliesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SuppliesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SuppliesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> brand = const Value.absent(),
                Value<double?> unitQuantity = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<String?> lastStoreName = const Value.absent(),
                Value<String?> lastStoreAddress = const Value.absent(),
                Value<int> currentPrice = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SuppliesCompanion(
                id: id,
                businessId: businessId,
                name: name,
                brand: brand,
                unitQuantity: unitQuantity,
                unit: unit,
                lastStoreName: lastStoreName,
                lastStoreAddress: lastStoreAddress,
                currentPrice: currentPrice,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String name,
                Value<String?> brand = const Value.absent(),
                Value<double?> unitQuantity = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<String?> lastStoreName = const Value.absent(),
                Value<String?> lastStoreAddress = const Value.absent(),
                required int currentPrice,
                Value<String?> notes = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SuppliesCompanion.insert(
                id: id,
                businessId: businessId,
                name: name,
                brand: brand,
                unitQuantity: unitQuantity,
                unit: unit,
                lastStoreName: lastStoreName,
                lastStoreAddress: lastStoreAddress,
                currentPrice: currentPrice,
                notes: notes,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SuppliesTable, Supply>(table),
                  $$SuppliesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                supplyPriceHistoryRefs = false,
                shoppingCartItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (supplyPriceHistoryRefs) db.supplyPriceHistory,
                    if (shoppingCartItemsRefs) db.shoppingCartItems,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable: $$SuppliesTableReferences
                                        ._businessIdTable(db),
                                    referencedColumn: $$SuppliesTableReferences
                                        ._businessIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (supplyPriceHistoryRefs)
                        await $_getPrefetchedData<
                          Supply,
                          $SuppliesTable,
                          SupplyPriceHistoryData
                        >(
                          currentTable: table,
                          referencedTable: $$SuppliesTableReferences
                              ._supplyPriceHistoryRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SuppliesTableReferences(
                                db,
                                table,
                                p0,
                              ).supplyPriceHistoryRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.supplyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (shoppingCartItemsRefs)
                        await $_getPrefetchedData<
                          Supply,
                          $SuppliesTable,
                          ShoppingCartItem
                        >(
                          currentTable: table,
                          referencedTable: $$SuppliesTableReferences
                              ._shoppingCartItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SuppliesTableReferences(
                                db,
                                table,
                                p0,
                              ).shoppingCartItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.supplyId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SuppliesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SuppliesTable,
      Supply,
      $$SuppliesTableFilterComposer,
      $$SuppliesTableOrderingComposer,
      $$SuppliesTableAnnotationComposer,
      $$SuppliesTableCreateCompanionBuilder,
      $$SuppliesTableUpdateCompanionBuilder,
      (Supply, $$SuppliesTableReferences),
      Supply,
      PrefetchHooks Function({
        bool businessId,
        bool supplyPriceHistoryRefs,
        bool shoppingCartItemsRefs,
      })
    >;
typedef $$SupplyPriceHistoryTableCreateCompanionBuilder =
    SupplyPriceHistoryCompanion Function({
      required String id,
      required String supplyId,
      required int price,
      required String storeName,
      Value<String?> storeAddress,
      Value<String?> supplierId,
      required DateTime recordedDate,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$SupplyPriceHistoryTableUpdateCompanionBuilder =
    SupplyPriceHistoryCompanion Function({
      Value<String> id,
      Value<String> supplyId,
      Value<int> price,
      Value<String> storeName,
      Value<String?> storeAddress,
      Value<String?> supplierId,
      Value<DateTime> recordedDate,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$SupplyPriceHistoryTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $SupplyPriceHistoryTable,
          SupplyPriceHistoryData
        > {
  $$SupplyPriceHistoryTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SuppliesTable _supplyIdTable(_$AppDatabase db) =>
      db.supplies.createAlias('supply_price_history__supply_id__supplies__id');

  $$SuppliesTableProcessedTableManager get supplyId {
    final $_column = $_itemColumn<String>('supply_id')!;

    final manager = $$SuppliesTableTableManager(
      $_db,
      $_db.supplies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_supplyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SuppliersTable _supplierIdTable(_$AppDatabase db) => db.suppliers
      .createAlias('supply_price_history__supplier_id__suppliers__id');

  $$SuppliersTableProcessedTableManager? get supplierId {
    final $_column = $_itemColumn<String>('supplier_id');
    if ($_column == null) return null;
    final manager = $$SuppliersTableTableManager(
      $_db,
      $_db.suppliers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_supplierIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SupplyPriceHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $SupplyPriceHistoryTable> {
  $$SupplyPriceHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeName => $composableBuilder(
    column: $table.storeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeAddress => $composableBuilder(
    column: $table.storeAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordedDate => $composableBuilder(
    column: $table.recordedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SuppliesTableFilterComposer get supplyId {
    final $$SuppliesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplyId,
      referencedTable: $db.supplies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliesTableFilterComposer(
            $db: $db,
            $table: $db.supplies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableFilterComposer get supplierId {
    final $$SuppliersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableFilterComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SupplyPriceHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $SupplyPriceHistoryTable> {
  $$SupplyPriceHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeName => $composableBuilder(
    column: $table.storeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeAddress => $composableBuilder(
    column: $table.storeAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordedDate => $composableBuilder(
    column: $table.recordedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SuppliesTableOrderingComposer get supplyId {
    final $$SuppliesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplyId,
      referencedTable: $db.supplies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliesTableOrderingComposer(
            $db: $db,
            $table: $db.supplies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableOrderingComposer get supplierId {
    final $$SuppliersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableOrderingComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SupplyPriceHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $SupplyPriceHistoryTable> {
  $$SupplyPriceHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get storeName =>
      $composableBuilder(column: $table.storeName, builder: (column) => column);

  GeneratedColumn<String> get storeAddress => $composableBuilder(
    column: $table.storeAddress,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get recordedDate => $composableBuilder(
    column: $table.recordedDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SuppliesTableAnnotationComposer get supplyId {
    final $$SuppliesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplyId,
      referencedTable: $db.supplies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliesTableAnnotationComposer(
            $db: $db,
            $table: $db.supplies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliersTableAnnotationComposer get supplierId {
    final $$SuppliersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplierId,
      referencedTable: $db.suppliers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliersTableAnnotationComposer(
            $db: $db,
            $table: $db.suppliers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SupplyPriceHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SupplyPriceHistoryTable,
          SupplyPriceHistoryData,
          $$SupplyPriceHistoryTableFilterComposer,
          $$SupplyPriceHistoryTableOrderingComposer,
          $$SupplyPriceHistoryTableAnnotationComposer,
          $$SupplyPriceHistoryTableCreateCompanionBuilder,
          $$SupplyPriceHistoryTableUpdateCompanionBuilder,
          (SupplyPriceHistoryData, $$SupplyPriceHistoryTableReferences),
          SupplyPriceHistoryData,
          PrefetchHooks Function({bool supplyId, bool supplierId})
        > {
  $$SupplyPriceHistoryTableTableManager(
    _$AppDatabase db,
    $SupplyPriceHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SupplyPriceHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SupplyPriceHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SupplyPriceHistoryTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> supplyId = const Value.absent(),
                Value<int> price = const Value.absent(),
                Value<String> storeName = const Value.absent(),
                Value<String?> storeAddress = const Value.absent(),
                Value<String?> supplierId = const Value.absent(),
                Value<DateTime> recordedDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SupplyPriceHistoryCompanion(
                id: id,
                supplyId: supplyId,
                price: price,
                storeName: storeName,
                storeAddress: storeAddress,
                supplierId: supplierId,
                recordedDate: recordedDate,
                notes: notes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String supplyId,
                required int price,
                required String storeName,
                Value<String?> storeAddress = const Value.absent(),
                Value<String?> supplierId = const Value.absent(),
                required DateTime recordedDate,
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SupplyPriceHistoryCompanion.insert(
                id: id,
                supplyId: supplyId,
                price: price,
                storeName: storeName,
                storeAddress: storeAddress,
                supplierId: supplierId,
                recordedDate: recordedDate,
                notes: notes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SupplyPriceHistoryTable, SupplyPriceHistoryData>(
                    table,
                  ),
                  $$SupplyPriceHistoryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({supplyId = false, supplierId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (supplyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.supplyId,
                                referencedTable:
                                    $$SupplyPriceHistoryTableReferences
                                        ._supplyIdTable(db),
                                referencedColumn:
                                    $$SupplyPriceHistoryTableReferences
                                        ._supplyIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (supplierId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.supplierId,
                                referencedTable:
                                    $$SupplyPriceHistoryTableReferences
                                        ._supplierIdTable(db),
                                referencedColumn:
                                    $$SupplyPriceHistoryTableReferences
                                        ._supplierIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SupplyPriceHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SupplyPriceHistoryTable,
      SupplyPriceHistoryData,
      $$SupplyPriceHistoryTableFilterComposer,
      $$SupplyPriceHistoryTableOrderingComposer,
      $$SupplyPriceHistoryTableAnnotationComposer,
      $$SupplyPriceHistoryTableCreateCompanionBuilder,
      $$SupplyPriceHistoryTableUpdateCompanionBuilder,
      (SupplyPriceHistoryData, $$SupplyPriceHistoryTableReferences),
      SupplyPriceHistoryData,
      PrefetchHooks Function({bool supplyId, bool supplierId})
    >;
typedef $$ShoppingCartsTableCreateCompanionBuilder =
    ShoppingCartsCompanion Function({
      required String id,
      required String businessId,
      required DateTime cartDate,
      Value<String?> storeName,
      Value<String?> storeAddress,
      required int totalAmount,
      Value<String?> expenseId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ShoppingCartsTableUpdateCompanionBuilder =
    ShoppingCartsCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<DateTime> cartDate,
      Value<String?> storeName,
      Value<String?> storeAddress,
      Value<int> totalAmount,
      Value<String?> expenseId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ShoppingCartsTableReferences
    extends BaseReferences<_$AppDatabase, $ShoppingCartsTable, ShoppingCart> {
  $$ShoppingCartsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BusinessesTable _businessIdTable(_$AppDatabase db) =>
      db.businesses.createAlias('shopping_carts__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ExpensesTable _expenseIdTable(_$AppDatabase db) =>
      db.expenses.createAlias('shopping_carts__expense_id__expenses__id');

  $$ExpensesTableProcessedTableManager? get expenseId {
    final $_column = $_itemColumn<String>('expense_id');
    if ($_column == null) return null;
    final manager = $$ExpensesTableTableManager(
      $_db,
      $_db.expenses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_expenseIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ShoppingCartItemsTable, List<ShoppingCartItem>>
  _shoppingCartItemsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.shoppingCartItems,
        aliasName: 'shopping_carts__id__shopping_cart_items__cart_id',
      );

  $$ShoppingCartItemsTableProcessedTableManager get shoppingCartItemsRefs {
    final manager = $$ShoppingCartItemsTableTableManager(
      $_db,
      $_db.shoppingCartItems,
    ).filter((f) => f.cartId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _shoppingCartItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ShoppingCartsTableFilterComposer
    extends Composer<_$AppDatabase, $ShoppingCartsTable> {
  $$ShoppingCartsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cartDate => $composableBuilder(
    column: $table.cartDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeName => $composableBuilder(
    column: $table.storeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeAddress => $composableBuilder(
    column: $table.storeAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalAmount => $composableBuilder(
    column: $table.totalAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ExpensesTableFilterComposer get expenseId {
    final $$ExpensesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableFilterComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> shoppingCartItemsRefs(
    Expression<bool> Function($$ShoppingCartItemsTableFilterComposer f) f,
  ) {
    final $$ShoppingCartItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shoppingCartItems,
      getReferencedColumn: (t) => t.cartId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingCartItemsTableFilterComposer(
            $db: $db,
            $table: $db.shoppingCartItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ShoppingCartsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShoppingCartsTable> {
  $$ShoppingCartsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cartDate => $composableBuilder(
    column: $table.cartDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeName => $composableBuilder(
    column: $table.storeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeAddress => $composableBuilder(
    column: $table.storeAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalAmount => $composableBuilder(
    column: $table.totalAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ExpensesTableOrderingComposer get expenseId {
    final $$ExpensesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableOrderingComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShoppingCartsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShoppingCartsTable> {
  $$ShoppingCartsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get cartDate =>
      $composableBuilder(column: $table.cartDate, builder: (column) => column);

  GeneratedColumn<String> get storeName =>
      $composableBuilder(column: $table.storeName, builder: (column) => column);

  GeneratedColumn<String> get storeAddress => $composableBuilder(
    column: $table.storeAddress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalAmount => $composableBuilder(
    column: $table.totalAmount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ExpensesTableAnnotationComposer get expenseId {
    final $$ExpensesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.expenseId,
      referencedTable: $db.expenses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExpensesTableAnnotationComposer(
            $db: $db,
            $table: $db.expenses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> shoppingCartItemsRefs<T extends Object>(
    Expression<T> Function($$ShoppingCartItemsTableAnnotationComposer a) f,
  ) {
    final $$ShoppingCartItemsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.shoppingCartItems,
          getReferencedColumn: (t) => t.cartId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ShoppingCartItemsTableAnnotationComposer(
                $db: $db,
                $table: $db.shoppingCartItems,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ShoppingCartsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShoppingCartsTable,
          ShoppingCart,
          $$ShoppingCartsTableFilterComposer,
          $$ShoppingCartsTableOrderingComposer,
          $$ShoppingCartsTableAnnotationComposer,
          $$ShoppingCartsTableCreateCompanionBuilder,
          $$ShoppingCartsTableUpdateCompanionBuilder,
          (ShoppingCart, $$ShoppingCartsTableReferences),
          ShoppingCart,
          PrefetchHooks Function({
            bool businessId,
            bool expenseId,
            bool shoppingCartItemsRefs,
          })
        > {
  $$ShoppingCartsTableTableManager(_$AppDatabase db, $ShoppingCartsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShoppingCartsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShoppingCartsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShoppingCartsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<DateTime> cartDate = const Value.absent(),
                Value<String?> storeName = const Value.absent(),
                Value<String?> storeAddress = const Value.absent(),
                Value<int> totalAmount = const Value.absent(),
                Value<String?> expenseId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingCartsCompanion(
                id: id,
                businessId: businessId,
                cartDate: cartDate,
                storeName: storeName,
                storeAddress: storeAddress,
                totalAmount: totalAmount,
                expenseId: expenseId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required DateTime cartDate,
                Value<String?> storeName = const Value.absent(),
                Value<String?> storeAddress = const Value.absent(),
                required int totalAmount,
                Value<String?> expenseId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingCartsCompanion.insert(
                id: id,
                businessId: businessId,
                cartDate: cartDate,
                storeName: storeName,
                storeAddress: storeAddress,
                totalAmount: totalAmount,
                expenseId: expenseId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShoppingCartsTable, ShoppingCart>(table),
                  $$ShoppingCartsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                expenseId = false,
                shoppingCartItemsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (shoppingCartItemsRefs) db.shoppingCartItems,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable:
                                        $$ShoppingCartsTableReferences
                                            ._businessIdTable(db),
                                    referencedColumn:
                                        $$ShoppingCartsTableReferences
                                            ._businessIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (expenseId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.expenseId,
                                    referencedTable:
                                        $$ShoppingCartsTableReferences
                                            ._expenseIdTable(db),
                                    referencedColumn:
                                        $$ShoppingCartsTableReferences
                                            ._expenseIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (shoppingCartItemsRefs)
                        await $_getPrefetchedData<
                          ShoppingCart,
                          $ShoppingCartsTable,
                          ShoppingCartItem
                        >(
                          currentTable: table,
                          referencedTable: $$ShoppingCartsTableReferences
                              ._shoppingCartItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ShoppingCartsTableReferences(
                                db,
                                table,
                                p0,
                              ).shoppingCartItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.cartId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ShoppingCartsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShoppingCartsTable,
      ShoppingCart,
      $$ShoppingCartsTableFilterComposer,
      $$ShoppingCartsTableOrderingComposer,
      $$ShoppingCartsTableAnnotationComposer,
      $$ShoppingCartsTableCreateCompanionBuilder,
      $$ShoppingCartsTableUpdateCompanionBuilder,
      (ShoppingCart, $$ShoppingCartsTableReferences),
      ShoppingCart,
      PrefetchHooks Function({
        bool businessId,
        bool expenseId,
        bool shoppingCartItemsRefs,
      })
    >;
typedef $$ShoppingCartItemsTableCreateCompanionBuilder =
    ShoppingCartItemsCompanion Function({
      required String id,
      required String cartId,
      Value<String?> supplyId,
      required String itemName,
      Value<String?> brand,
      Value<double?> unitQuantity,
      Value<String?> unit,
      required int unitPrice,
      Value<int> quantity,
      required int lineTotal,
      Value<int> rowid,
    });
typedef $$ShoppingCartItemsTableUpdateCompanionBuilder =
    ShoppingCartItemsCompanion Function({
      Value<String> id,
      Value<String> cartId,
      Value<String?> supplyId,
      Value<String> itemName,
      Value<String?> brand,
      Value<double?> unitQuantity,
      Value<String?> unit,
      Value<int> unitPrice,
      Value<int> quantity,
      Value<int> lineTotal,
      Value<int> rowid,
    });

final class $$ShoppingCartItemsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ShoppingCartItemsTable,
          ShoppingCartItem
        > {
  $$ShoppingCartItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ShoppingCartsTable _cartIdTable(_$AppDatabase db) => db.shoppingCarts
      .createAlias('shopping_cart_items__cart_id__shopping_carts__id');

  $$ShoppingCartsTableProcessedTableManager get cartId {
    final $_column = $_itemColumn<String>('cart_id')!;

    final manager = $$ShoppingCartsTableTableManager(
      $_db,
      $_db.shoppingCarts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_cartIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SuppliesTable _supplyIdTable(_$AppDatabase db) =>
      db.supplies.createAlias('shopping_cart_items__supply_id__supplies__id');

  $$SuppliesTableProcessedTableManager? get supplyId {
    final $_column = $_itemColumn<String>('supply_id');
    if ($_column == null) return null;
    final manager = $$SuppliesTableTableManager(
      $_db,
      $_db.supplies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_supplyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ShoppingCartItemsTableFilterComposer
    extends Composer<_$AppDatabase, $ShoppingCartItemsTable> {
  $$ShoppingCartItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemName => $composableBuilder(
    column: $table.itemName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitQuantity => $composableBuilder(
    column: $table.unitQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unitPrice => $composableBuilder(
    column: $table.unitPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineTotal => $composableBuilder(
    column: $table.lineTotal,
    builder: (column) => ColumnFilters(column),
  );

  $$ShoppingCartsTableFilterComposer get cartId {
    final $$ShoppingCartsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cartId,
      referencedTable: $db.shoppingCarts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingCartsTableFilterComposer(
            $db: $db,
            $table: $db.shoppingCarts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliesTableFilterComposer get supplyId {
    final $$SuppliesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplyId,
      referencedTable: $db.supplies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliesTableFilterComposer(
            $db: $db,
            $table: $db.supplies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShoppingCartItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ShoppingCartItemsTable> {
  $$ShoppingCartItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemName => $composableBuilder(
    column: $table.itemName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitQuantity => $composableBuilder(
    column: $table.unitQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unitPrice => $composableBuilder(
    column: $table.unitPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineTotal => $composableBuilder(
    column: $table.lineTotal,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShoppingCartsTableOrderingComposer get cartId {
    final $$ShoppingCartsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cartId,
      referencedTable: $db.shoppingCarts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingCartsTableOrderingComposer(
            $db: $db,
            $table: $db.shoppingCarts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliesTableOrderingComposer get supplyId {
    final $$SuppliesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplyId,
      referencedTable: $db.supplies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliesTableOrderingComposer(
            $db: $db,
            $table: $db.supplies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShoppingCartItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShoppingCartItemsTable> {
  $$ShoppingCartItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get itemName =>
      $composableBuilder(column: $table.itemName, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<double> get unitQuantity => $composableBuilder(
    column: $table.unitQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<int> get unitPrice =>
      $composableBuilder(column: $table.unitPrice, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get lineTotal =>
      $composableBuilder(column: $table.lineTotal, builder: (column) => column);

  $$ShoppingCartsTableAnnotationComposer get cartId {
    final $$ShoppingCartsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cartId,
      referencedTable: $db.shoppingCarts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShoppingCartsTableAnnotationComposer(
            $db: $db,
            $table: $db.shoppingCarts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SuppliesTableAnnotationComposer get supplyId {
    final $$SuppliesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supplyId,
      referencedTable: $db.supplies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SuppliesTableAnnotationComposer(
            $db: $db,
            $table: $db.supplies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShoppingCartItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShoppingCartItemsTable,
          ShoppingCartItem,
          $$ShoppingCartItemsTableFilterComposer,
          $$ShoppingCartItemsTableOrderingComposer,
          $$ShoppingCartItemsTableAnnotationComposer,
          $$ShoppingCartItemsTableCreateCompanionBuilder,
          $$ShoppingCartItemsTableUpdateCompanionBuilder,
          (ShoppingCartItem, $$ShoppingCartItemsTableReferences),
          ShoppingCartItem,
          PrefetchHooks Function({bool cartId, bool supplyId})
        > {
  $$ShoppingCartItemsTableTableManager(
    _$AppDatabase db,
    $ShoppingCartItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShoppingCartItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShoppingCartItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShoppingCartItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> cartId = const Value.absent(),
                Value<String?> supplyId = const Value.absent(),
                Value<String> itemName = const Value.absent(),
                Value<String?> brand = const Value.absent(),
                Value<double?> unitQuantity = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<int> unitPrice = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<int> lineTotal = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShoppingCartItemsCompanion(
                id: id,
                cartId: cartId,
                supplyId: supplyId,
                itemName: itemName,
                brand: brand,
                unitQuantity: unitQuantity,
                unit: unit,
                unitPrice: unitPrice,
                quantity: quantity,
                lineTotal: lineTotal,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String cartId,
                Value<String?> supplyId = const Value.absent(),
                required String itemName,
                Value<String?> brand = const Value.absent(),
                Value<double?> unitQuantity = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                required int unitPrice,
                Value<int> quantity = const Value.absent(),
                required int lineTotal,
                Value<int> rowid = const Value.absent(),
              }) => ShoppingCartItemsCompanion.insert(
                id: id,
                cartId: cartId,
                supplyId: supplyId,
                itemName: itemName,
                brand: brand,
                unitQuantity: unitQuantity,
                unit: unit,
                unitPrice: unitPrice,
                quantity: quantity,
                lineTotal: lineTotal,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShoppingCartItemsTable, ShoppingCartItem>(table),
                  $$ShoppingCartItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({cartId = false, supplyId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (cartId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.cartId,
                                referencedTable:
                                    $$ShoppingCartItemsTableReferences
                                        ._cartIdTable(db),
                                referencedColumn:
                                    $$ShoppingCartItemsTableReferences
                                        ._cartIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (supplyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.supplyId,
                                referencedTable:
                                    $$ShoppingCartItemsTableReferences
                                        ._supplyIdTable(db),
                                referencedColumn:
                                    $$ShoppingCartItemsTableReferences
                                        ._supplyIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ShoppingCartItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShoppingCartItemsTable,
      ShoppingCartItem,
      $$ShoppingCartItemsTableFilterComposer,
      $$ShoppingCartItemsTableOrderingComposer,
      $$ShoppingCartItemsTableAnnotationComposer,
      $$ShoppingCartItemsTableCreateCompanionBuilder,
      $$ShoppingCartItemsTableUpdateCompanionBuilder,
      (ShoppingCartItem, $$ShoppingCartItemsTableReferences),
      ShoppingCartItem,
      PrefetchHooks Function({bool cartId, bool supplyId})
    >;
typedef $$AccountTransfersTableCreateCompanionBuilder =
    AccountTransfersCompanion Function({
      required String id,
      required String businessId,
      required String fromAccountId,
      required String toAccountId,
      required int amount,
      required DateTime transferDate,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$AccountTransfersTableUpdateCompanionBuilder =
    AccountTransfersCompanion Function({
      Value<String> id,
      Value<String> businessId,
      Value<String> fromAccountId,
      Value<String> toAccountId,
      Value<int> amount,
      Value<DateTime> transferDate,
      Value<String?> notes,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$AccountTransfersTableReferences
    extends
        BaseReferences<_$AppDatabase, $AccountTransfersTable, AccountTransfer> {
  $$AccountTransfersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BusinessesTable _businessIdTable(_$AppDatabase db) => db.businesses
      .createAlias('account_transfers__business_id__businesses__id');

  $$BusinessesTableProcessedTableManager get businessId {
    final $_column = $_itemColumn<String>('business_id')!;

    final manager = $$BusinessesTableTableManager(
      $_db,
      $_db.businesses,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_businessIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _fromAccountIdTable(_$AppDatabase db) => db.accounts
      .createAlias('account_transfers__from_account_id__accounts__id');

  $$AccountsTableProcessedTableManager get fromAccountId {
    final $_column = $_itemColumn<String>('from_account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fromAccountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AccountsTable _toAccountIdTable(_$AppDatabase db) =>
      db.accounts.createAlias('account_transfers__to_account_id__accounts__id');

  $$AccountsTableProcessedTableManager get toAccountId {
    final $_column = $_itemColumn<String>('to_account_id')!;

    final manager = $$AccountsTableTableManager(
      $_db,
      $_db.accounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_toAccountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AccountTransfersTableFilterComposer
    extends Composer<_$AppDatabase, $AccountTransfersTable> {
  $$AccountTransfersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get transferDate => $composableBuilder(
    column: $table.transferDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BusinessesTableFilterComposer get businessId {
    final $$BusinessesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableFilterComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get fromAccountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fromAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableFilterComposer get toAccountId {
    final $$AccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.toAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableFilterComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AccountTransfersTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountTransfersTable> {
  $$AccountTransfersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get transferDate => $composableBuilder(
    column: $table.transferDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BusinessesTableOrderingComposer get businessId {
    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableOrderingComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get fromAccountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fromAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableOrderingComposer get toAccountId {
    final $$AccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.toAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableOrderingComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AccountTransfersTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountTransfersTable> {
  $$AccountTransfersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<DateTime> get transferDate => $composableBuilder(
    column: $table.transferDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$BusinessesTableAnnotationComposer get businessId {
    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.businessId,
      referencedTable: $db.businesses,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BusinessesTableAnnotationComposer(
            $db: $db,
            $table: $db.businesses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get fromAccountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fromAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AccountsTableAnnotationComposer get toAccountId {
    final $$AccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.toAccountId,
      referencedTable: $db.accounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.accounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AccountTransfersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountTransfersTable,
          AccountTransfer,
          $$AccountTransfersTableFilterComposer,
          $$AccountTransfersTableOrderingComposer,
          $$AccountTransfersTableAnnotationComposer,
          $$AccountTransfersTableCreateCompanionBuilder,
          $$AccountTransfersTableUpdateCompanionBuilder,
          (AccountTransfer, $$AccountTransfersTableReferences),
          AccountTransfer,
          PrefetchHooks Function({
            bool businessId,
            bool fromAccountId,
            bool toAccountId,
          })
        > {
  $$AccountTransfersTableTableManager(
    _$AppDatabase db,
    $AccountTransfersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountTransfersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountTransfersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountTransfersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> fromAccountId = const Value.absent(),
                Value<String> toAccountId = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<DateTime> transferDate = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountTransfersCompanion(
                id: id,
                businessId: businessId,
                fromAccountId: fromAccountId,
                toAccountId: toAccountId,
                amount: amount,
                transferDate: transferDate,
                notes: notes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String businessId,
                required String fromAccountId,
                required String toAccountId,
                required int amount,
                required DateTime transferDate,
                Value<String?> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountTransfersCompanion.insert(
                id: id,
                businessId: businessId,
                fromAccountId: fromAccountId,
                toAccountId: toAccountId,
                amount: amount,
                transferDate: transferDate,
                notes: notes,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AccountTransfersTable, AccountTransfer>(table),
                  $$AccountTransfersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                businessId = false,
                fromAccountId = false,
                toAccountId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (businessId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.businessId,
                                    referencedTable:
                                        $$AccountTransfersTableReferences
                                            ._businessIdTable(db),
                                    referencedColumn:
                                        $$AccountTransfersTableReferences
                                            ._businessIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (fromAccountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.fromAccountId,
                                    referencedTable:
                                        $$AccountTransfersTableReferences
                                            ._fromAccountIdTable(db),
                                    referencedColumn:
                                        $$AccountTransfersTableReferences
                                            ._fromAccountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (toAccountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.toAccountId,
                                    referencedTable:
                                        $$AccountTransfersTableReferences
                                            ._toAccountIdTable(db),
                                    referencedColumn:
                                        $$AccountTransfersTableReferences
                                            ._toAccountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$AccountTransfersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountTransfersTable,
      AccountTransfer,
      $$AccountTransfersTableFilterComposer,
      $$AccountTransfersTableOrderingComposer,
      $$AccountTransfersTableAnnotationComposer,
      $$AccountTransfersTableCreateCompanionBuilder,
      $$AccountTransfersTableUpdateCompanionBuilder,
      (AccountTransfer, $$AccountTransfersTableReferences),
      AccountTransfer,
      PrefetchHooks Function({
        bool businessId,
        bool fromAccountId,
        bool toAccountId,
      })
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BusinessesTableTableManager get businesses =>
      $$BusinessesTableTableManager(_db, _db.businesses);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$JournalEntriesTableTableManager get journalEntries =>
      $$JournalEntriesTableTableManager(_db, _db.journalEntries);
  $$LedgerLinesTableTableManager get ledgerLines =>
      $$LedgerLinesTableTableManager(_db, _db.ledgerLines);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db, _db.customers);
  $$IncomeTransactionsTableTableManager get incomeTransactions =>
      $$IncomeTransactionsTableTableManager(_db, _db.incomeTransactions);
  $$ReceivablePaymentsTableTableManager get receivablePayments =>
      $$ReceivablePaymentsTableTableManager(_db, _db.receivablePayments);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db, _db.suppliers);
  $$SupplierPurchasesTableTableManager get supplierPurchases =>
      $$SupplierPurchasesTableTableManager(_db, _db.supplierPurchases);
  $$PayablePaymentsTableTableManager get payablePayments =>
      $$PayablePaymentsTableTableManager(_db, _db.payablePayments);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db, _db.expenses);
  $$SuppliesTableTableManager get supplies =>
      $$SuppliesTableTableManager(_db, _db.supplies);
  $$SupplyPriceHistoryTableTableManager get supplyPriceHistory =>
      $$SupplyPriceHistoryTableTableManager(_db, _db.supplyPriceHistory);
  $$ShoppingCartsTableTableManager get shoppingCarts =>
      $$ShoppingCartsTableTableManager(_db, _db.shoppingCarts);
  $$ShoppingCartItemsTableTableManager get shoppingCartItems =>
      $$ShoppingCartItemsTableTableManager(_db, _db.shoppingCartItems);
  $$AccountTransfersTableTableManager get accountTransfers =>
      $$AccountTransfersTableTableManager(_db, _db.accountTransfers);
}
