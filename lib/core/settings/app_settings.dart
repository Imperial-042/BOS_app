import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _darkModeKey = 'appearance.dark_mode';
const _currencyKey = 'format.currency_code';
const _fontFamilyKey = 'appearance.font_family';
const _colorIdKey = 'appearance.color_id';
const _textScaleKey = 'appearance.text_scale';

class AppSettings {
  const AppSettings({
    required this.isDarkMode,
    required this.currencyCode,
    required this.fontFamily,
    required this.colorId,
    required this.textScale,
  });

  final bool isDarkMode;
  final String currencyCode;
  final String fontFamily;
  final String colorId;
  final double textScale;

  AppSettings copyWith({
    bool? isDarkMode,
    String? currencyCode,
    String? fontFamily,
    String? colorId,
    double? textScale,
  }) => AppSettings(
    isDarkMode: isDarkMode ?? this.isDarkMode,
    currencyCode: currencyCode ?? this.currencyCode,
    fontFamily: fontFamily ?? this.fontFamily,
    colorId: colorId ?? this.colorId,
    textScale: textScale ?? this.textScale,
  );
}

class AppSettingsController extends StateNotifier<AppSettings> {
  AppSettingsController({
    required SharedPreferences preferences,
    required AppSettings initialSettings,
  }) : _preferences = preferences,
       super(initialSettings) {
    MoneyFormatting.currencyCode = initialSettings.currencyCode;
  }

  final SharedPreferences _preferences;

  Future<void> setDarkMode(bool enabled) async {
    final saved = await _preferences.setBool(_darkModeKey, enabled);
    if (!saved) throw StateError('Could not save the theme preference.');
    state = state.copyWith(isDarkMode: enabled);
  }

  Future<void> setCurrencyCode(String code) async {
    if (!MoneyFormatting.supportedCurrencies.any(
      (currency) => currency.code == code,
    )) {
      throw ArgumentError.value(code, 'code', 'Unsupported currency');
    }
    final saved = await _preferences.setString(_currencyKey, code);
    if (!saved) throw StateError('Could not save the currency preference.');
    MoneyFormatting.currencyCode = code;
    state = state.copyWith(currencyCode: code);
  }

  Future<void> setFontFamily(String fontFamily) async {
    if (!supportedFontFamilies.contains(fontFamily)) {
      throw ArgumentError.value(
        fontFamily,
        'fontFamily',
        'Unsupported font family',
      );
    }
    final saved = await _preferences.setString(_fontFamilyKey, fontFamily);
    if (!saved) throw StateError('Could not save the font preference.');
    state = state.copyWith(fontFamily: fontFamily);
  }

  Future<void> setColorId(String colorId) async {
    if (!AppTheme.colorOptions.any((option) => option.id == colorId)) {
      throw ArgumentError.value(colorId, 'colorId', 'Unsupported app color');
    }
    final saved = await _preferences.setString(_colorIdKey, colorId);
    if (!saved) throw StateError('Could not save the app color preference.');
    state = state.copyWith(colorId: colorId);
  }

  Future<void> setTextScale(double textScale) async {
    if (!supportedTextScales.contains(textScale)) {
      throw ArgumentError.value(textScale, 'textScale', 'Unsupported text size');
    }
    final saved = await _preferences.setDouble(_textScaleKey, textScale);
    if (!saved) throw StateError('Could not save the text size preference.');
    state = state.copyWith(textScale: textScale);
  }

  static const supportedFontFamilies = <String>[
    'system',
    'serif',
    'monospace',
  ];
  static const supportedTextScales = <double>[0.9, 1, 1.15, 1.3];

  static AppSettings load(SharedPreferences preferences) {
    final savedCode = preferences.getString(_currencyKey);
    final currencyCode = MoneyFormatting.supportedCurrencies.any(
      (currency) => currency.code == savedCode,
    )
        ? savedCode!
        : 'PHP';
    return AppSettings(
      isDarkMode: preferences.getBool(_darkModeKey) ?? false,
      currencyCode: currencyCode,
      fontFamily: supportedFontFamilies.contains(
        preferences.getString(_fontFamilyKey),
      )
          ? preferences.getString(_fontFamilyKey)!
          : 'system',
      colorId: AppTheme.colorOptions.any(
        (option) => option.id == preferences.getString(_colorIdKey),
      )
          ? preferences.getString(_colorIdKey)!
          : 'bos',
      textScale: supportedTextScales.contains(
        preferences.getDouble(_textScaleKey),
      )
          ? preferences.getDouble(_textScaleKey)!
          : 1,
    );
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsController, AppSettings>((ref) {
      throw StateError('AppSettingsController must be initialized at startup.');
    });
