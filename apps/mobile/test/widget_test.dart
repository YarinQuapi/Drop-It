import 'package:drop_it/copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hebrew copy switches with the language', () {
    expect(Copy('en').today, 'Today');
    expect(Copy('he').today, 'היום');
  });
}
