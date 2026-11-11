import 'package:drop_it/nutrition_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English table with per 100 g and per serving columns', () {
    final scan = parseNutritionText('''
Nutrition Facts
                 Per 100 g    Per serving (30 g)
Energy           1046 kJ / 250 kcal   314 kJ / 75 kcal
Fat              10.5 g       3.2 g
  of which saturates 4 g      1.2 g
Carbohydrate     30 g         9 g
  of which sugars 12.5 g      3.8 g
Fibre            2,5 g        0.8 g
Protein          6 g          1.8 g
Salt             1.2 g        0.4 g
''');
    expect(scan.calories, 250);
    expect(scan.fat, 10.5);
    expect(scan.carbohydrates, 30);
    expect(scan.sugars, 12.5);
    expect(scan.fiber, 2.5);
    expect(scan.protein, 6);
    expect(scan.sodium, 480);
    expect(scan.liquid, false);
  });

  test('Hebrew table, per 100 g first', () {
    final scan = parseNutritionText('''
ערכים תזונתיים
                  ל-100 גרם     למנה (30 גרם)
אנרגיה (קק"ל)    250           75
חלבונים (גרם)    6.0           1.8
פחמימות (גרם)    30            9
מתוכם סוכרים     12.5          3.8
שומנים (גרם)     10.5          3.2
מתוכם שומן רווי  4             1.2
סיבים תזונתיים   2.5           0.8
נתרן (מ"ג)       480           144
''');
    expect(scan.calories, 250);
    expect(scan.protein, 6);
    expect(scan.carbohydrates, 30);
    expect(scan.sugars, 12.5);
    expect(scan.fat, 10.5);
    expect(scan.fiber, 2.5);
    expect(scan.sodium, 480);
  });

  test('picks the per 100 column when it comes second', () {
    final scan = parseNutritionText('''
Per serving (30 g)   Per 100 g
Energy 75 kcal       250 kcal
Protein 1.8 g        6 g
Fat 3.2 g            10.5 g
''');
    expect(scan.calories, 250);
    expect(scan.protein, 6);
    expect(scan.fat, 10.5);
  });

  test('per 100 ml marks the food as liquid', () {
    final scan = parseNutritionText('''
Per 100 ml
Energy 42 kcal
Carbohydrate 10.6 g
Sugars 10.6 g
Protein 0 g
''');
    expect(scan.liquid, true);
    expect(scan.calories, 42);
    expect(scan.protein, 0);
  });

  test('per-serving-only table is scaled to 100 g', () {
    final scan = parseNutritionText('''
Serving size 25 g
Calories 100
Protein 5 g
Total Fat 2 g
Sodium 150 mg
''');
    expect(scan.fromServing, true);
    expect(scan.calories, 400);
    expect(scan.protein, 20);
    expect(scan.fat, 8);
    expect(scan.sodium, 600);
  });

  test('tolerates OCR typos and percent columns', () {
    final scan = parseNutritionText('''
Energv 120 kcal
Protein 3 g 6%
Carbohydrates 20 g 7%
פחמימוח 20
''');
    expect(scan.calories, 120);
    expect(scan.protein, 3);
    expect(scan.carbohydrates, 20);
  });

  test('converts kJ-only energy and handles less-than values', () {
    final scan = parseNutritionText('''
Energy 418 kJ
Fat < 0.5 g
Protein 2 g
''');
    expect(scan.calories, 100);
    expect(scan.fat, 0.5);
  });

  test('garbage text yields nothing usable', () {
    expect(parseNutritionText('hello world 123').usable, false);
  });

  // Real Tesseract (heb+eng, psm 6) output from rendered labels.
  test('Hebrew OCR: reversed header digits and lost decimals', () {
    final scan = parseNutritionText('''
ערכים תזונתיים | ל-001 גרם | למנה )03 גרם(
אנרגיה )קק"ל( 250 75
חלבונים )גרם( 6.0 18
פחמימות )גרם( 30 9
מתוכם סוכרים )גרם( | 12.5 3.8
שומנים )גרם( 10.5 2
מתוכם שומן רווי )גרם( 4 12
סיבים תזונתיים ‎ )pia(‏ 2.5 0.8
נתרן )מ"ג( 480 144
''');
    expect(scan.fromServing, false);
    expect(scan.calories, 250);
    expect(scan.protein, 6);
    expect(scan.carbohydrates, 30);
    expect(scan.sugars, 12.5);
    expect(scan.fat, 10.5);
    expect(scan.fiber, 2.5);
    expect(scan.sodium, 480);
  });

  test('Hebrew OCR, 80 g serving: repairs dropped decimals', () {
    final scan = parseNutritionText('''
ל-001 גרם ל-08 גרם
אנרגיה )קק"ל( 62 50
חלבון )גרם( 8.5 68
פחמימות )גרם( 42 3.4
שומן )גרם( 15 12
נתרן )מ"ג( 95 76
''');
    expect(scan.calories, 62);
    expect(scan.protein, 8.5);
    expect(scan.carbohydrates, 4.2);
    expect(scan.fat, 1.5);
    expect(scan.sodium, 95);
  });

  test('English OCR, per-100 column second, one unreadable row stays empty', () {
    final scan = parseNutritionText('''
Average values Per 80g Per 100g
Energy (kcal) 90 72
Protein (g) onl 2.5
Carbohydrate (g) 11.0 8.8
Fat (g) 3.5 2.8
''');
    expect(scan.calories, 90);
    expect(scan.carbohydrates, 11);
    expect(scan.fat, 3.5);
    expect(scan.protein, isNull); // ambiguous single number: not guessed
  });

  test('values that do not add up are dropped, not invented', () {
    final scan = parseNutritionText('''
Per 100 g
Energy 120 kcal
Protein 8 g
Carbohydrate 20 g
of which sugars 55 g
Fat 3 g
''');
    expect(scan.sugars, isNull);
    expect(scan.calories, 120);
  });

  // Real photo (Pringles bilingual label, single per-100 column) as read by
  // Tesseract after rotating upright. Includes a stray "70" outside the table,
  // a trans/saturated fat row and a "Sugars (teaspoons)" row.
  const bilingual = r'''
יפס פרינגלס ₪ פרינגלס ירוק רמי לוי | פריו
, : > < סופר-פארם
‎EE A SSS SS‏ סה סנס בכ הננ
‎lergens - contains: Coconut, milk, 7 feu‏
מידע על א :
מכיל: סויה, חלב, קוקוס, חיטה - גלוטן.\ - ‎heat (gluten) 8 soy‏
‎Nutrition Information per 100 = = :‏
ה סימון תזונתי ל-100 גרם מזו| . :
אנרגיה (קלוריות), קק"ל 523 ‎Energy (kcal):‏ -
] סך שומנים, גרם, מתוכם: 31 :(0) ‎Total Fat‏
חומצות שומן רוויות, גרם 8.7 (0) ‎Saturated Fat‏ | |
חומצות שומן טראנס, גרם| פחות מ-0.5 ‎Trans Fat (g):‏
₪ כולסטרול, מ"ג 1 ‎Cholesterol (mg):‏
‎ie‏ נתרן, מ"ג 579 ‎Sodium (mg):‏
] 70 הפחמימות, גרם, מתוכן: 57 ‎Carbohydrate (g):‏
‎HN‏ סוכרים, גרם 2.8 ‎Sugars (g):‏
‎Sugars (teaspoons):| 0.75 DION'S? Ae‏
סיבים תזונתיים, גרם ‏ | 2.4 ‎Fibre (g):‏
‎ee |‏ חלבונים, גרם 4 ‎OF Protein (a):‏
''';

  for (final hebrew in [false, true]) {
    test('bilingual label read as ${hebrew ? 'Hebrew' : 'English'}', () {
      final scan = parseNutritionText(bilingual, preferHebrew: hebrew);
      expect(scan.calories, 523);
      expect(scan.protein, 4);
      expect(scan.carbohydrates, 57);
      expect(scan.sugars, 2.8); // not the 0.75 teaspoons row
      expect(scan.fat, 31); // not saturated 8.7 / trans
      expect(scan.fiber, 2.4);
      expect(scan.sodium, 579);
      expect(scan.fromServing, false);
    });
  }

  test('mirrored-parenthesis OCR junk is not a value', () {
    final scan = parseNutritionText('''
Nutrition Information per 100g
‎ay‏ סוכרים, גר 2.8 :)9( ‎Sugars‏
‎ee‏ חלבונים, גרם 4 ‎Protein (g):‏
פחמימות 57 Carbohydrate (g):
''');
    expect(scan.sugars, 2.8);
    expect(scan.protein, 4);
  });

  test('a scan keeps its photo and exports its values for a report', () {
    final scan = parseNutritionText('Per 100 g\nEnergy 120 kcal\nProtein 8 g')
        .withRaw('text')
        .withPhoto('/tmp/label.png');
    expect(scan.photo, '/tmp/label.png');
    expect(scan.raw, 'text');
    expect(scan.toJson()['calories'], 120);
    expect(scan.toJson()['protein'], 8);
    expect(scan.toJson()['fat'], isNull);
  });
}
