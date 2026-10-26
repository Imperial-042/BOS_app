import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/format/money.dart';
import 'package:bos_application/core/settings/app_settings.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    MoneyFormatting.currencyCode = 'PHP';
  });

  test('formats amounts using the selected currency symbol', () {
    expect(formatPeso(125050), '₱1,250.50');

    MoneyFormatting.currencyCode = 'USD';
    expect(formatPeso(125050), r'$1,250.50');
    expect(formatPeso(-125050), r'-$1,250.50');
  });

  test('provides branded light and dark theme data', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
    final defaultTheme = AppTheme.light();
    final customTheme = AppTheme.light(
      seedColor: AppTheme.colorOptions[1].color,
      fontFamily: 'serif',
    );
    expect(
      customTheme.colorScheme.primary,
      isNot(defaultTheme.colorScheme.primary),
    );
    expect(customTheme.textTheme.bodyMedium?.fontFamily, 'serif');
  });

  test('loads and persists theme and currency preferences', () async {
    SharedPreferences.setMockInitialValues({
      'appearance.dark_mode': true,
      'appearance.font_family': 'serif',
      'appearance.color_id': 'violet',
      'appearance.text_scale': 1.15,
      'format.currency_code': 'EUR',
    });
    final preferences = await SharedPreferences.getInstance();
    final initialSettings = AppSettingsController.load(preferences);
    final controller = AppSettingsController(
      preferences: preferences,
      initialSettings: initialSettings,
    );
    addTearDown(controller.dispose);

    expect(initialSettings.isDarkMode, isTrue);
    expect(initialSettings.currencyCode, 'EUR');
    expect(initialSettings.fontFamily, 'serif');
    expect(initialSettings.colorId, 'violet');
    expect(initialSettings.textScale, 1.15);

    await controller.setDarkMode(false);
    await controller.setCurrencyCode('SGD');
    await controller.setFontFamily('monospace');
    await controller.setColorId('emerald');
    await controller.setTextScale(1.3);

    expect(preferences.getBool('appearance.dark_mode'), isFalse);
    expect(preferences.getString('format.currency_code'), 'SGD');
    expect(preferences.getString('appearance.font_family'), 'monospace');
    expect(preferences.getString('appearance.color_id'), 'emerald');
    expect(preferences.getDouble('appearance.text_scale'), 1.3);
    expect(controller.state.currencyCode, 'SGD');
    expect(controller.state.fontFamily, 'monospace');
    expect(controller.state.colorId, 'emerald');
    expect(controller.state.textScale, 1.3);
    expect(formatPeso(125050), r'S$1,250.50');
  });

  test('falls back to PHP when stored currency is unsupported', () async {
    SharedPreferences.setMockInitialValues({'format.currency_code': 'XYZ'});
    final preferences = await SharedPreferences.getInstance();

    expect(AppSettingsController.load(preferences).currencyCode, 'PHP');
  });
}
