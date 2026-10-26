import 'package:bos_application/core/branch/branch_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Philippines locations use the preset province list', () {
    expect(isPhilippinesCountry('Philippines'), isTrue);
    expect(isPhilippinesCountry('PH'), isTrue);
    expect(isPhilippinesCountry('United States'), isFalse);
    expect(philippineProvinces, contains('Cebu'));
    expect(philippineProvinces, contains('Metro Manila (NCR)'));
  });

  test('branch address formatter keeps all structured fields', () {
    expect(
      formatBranchAddress(
        country: 'Philippines',
        province: 'Cebu',
        city: 'Cebu City',
        streetBarangay: '123 Main St, Lahug',
        postalCode: '6000',
      ),
      '123 Main St, Lahug, Cebu City, Cebu, 6000, Philippines',
    );
  });

  test('branch address validation requires every location field', () {
    expect(
      () => validateBranchAddress(
        country: 'Philippines',
        province: 'Cebu',
        city: '',
        streetBarangay: 'Lahug',
        postalCode: '6000',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('city'),
        ),
      ),
    );
    expect(
      () => validateBranchAddress(
        country: 'Philippines',
        province: 'Cebu',
        city: 'Cebu City',
        streetBarangay: 'Lahug',
        postalCode: '6000',
      ),
      returnsNormally,
    );
  });
}
