import 'package:drop_it/copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t = Copy('en');

  test('unit foods are labelled per unit', () {
    expect(t.unitOf({'basis': 'unit'}), 'units');
    expect(t.perOf({'basis': 'unit'}), '/ 1 unit');
  });

  test('solid and liquid foods stay per 100', () {
    expect(t.perOf({'basis': 'solid'}), '/ 100 grams');
    expect(t.perOf({'basis': 'liquid'}), '/ 100 milliliters');
  });
}
