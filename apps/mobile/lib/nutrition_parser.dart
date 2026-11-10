/// Turns raw OCR text from a nutrition facts table (English, Hebrew or both)
/// into per-100 g / per-100 ml values. Pure Dart so it can be unit-tested
/// without a camera.
///
/// Labels list a per-serving column (30 g, 60 g, 80 g...) next to a per-100
/// column. We always take the per-100 value, and we use the ratio between the
/// two columns (value100 * serving / 100 == value per serving) both to find
/// the right column and to catch OCR misreads such as a dropped decimal point.
library;

class NutritionScan {
  const NutritionScan({
    this.calories,
    this.protein,
    this.carbohydrates,
    this.fat,
    this.fiber,
    this.sugars,
    this.sodium,
    this.liquid = false,
    this.fromServing = false,
    this.raw = '',
  });

  final num? calories;
  final num? protein;
  final num? carbohydrates;
  final num? fat;
  final num? fiber;
  final num? sugars;

  /// Milligrams.
  final num? sodium;

  /// The table is per 100 ml rather than per 100 g.
  final bool liquid;

  /// No per-100 column was found, so values were scaled from a serving.
  final bool fromServing;

  /// The OCR text this was parsed from (for the "show text" debug view).
  final String raw;

  int get found => [
    calories,
    protein,
    carbohydrates,
    fat,
    fiber,
    sugars,
    sodium,
  ].where((v) => v != null).length;

  /// Enough to be worth prefilling the form with.
  bool get usable => found >= 2;

  NutritionScan withRaw(String text) => NutritionScan(
    calories: calories,
    protein: protein,
    carbohydrates: carbohydrates,
    fat: fat,
    fiber: fiber,
    sugars: sugars,
    sodium: sodium,
    liquid: liquid,
    fromServing: fromServing,
    raw: text,
  );
}

enum _Field { calories, protein, carbs, fat, fiber, sugars, sodium, salt }

const _keywords = <_Field, List<String>>{
  _Field.calories: [
    'energy', 'calories', 'calorie', 'kcal',
    'אנרגיה', 'קלוריות', 'קלוריה', 'קקל',
  ],
  _Field.protein: ['protein', 'proteins', 'חלבון', 'חלבונים'],
  _Field.carbs: [
    'carbohydrate', 'carbohydrates', 'carbs', 'פחמימות', 'פחמימה',
  ],
  _Field.sugars: ['sugars', 'sugar', 'סוכרים', 'סוכר'],
  _Field.fat: ['fat', 'fats', 'שומן', 'שומנים'],
  _Field.fiber: ['fiber', 'fibre', 'fibres', 'סיבים', 'סיב'],
  _Field.sodium: ['sodium', 'נתרן'],
  _Field.salt: ['salt', 'מלח'],
};

/// Lines about these are sub-nutrients we don't track.
const _skipEnglish = [
  'saturated', 'saturates', 'trans', 'mono', 'poly',
  'monounsaturated', 'polyunsaturated', 'cholesterol',
];
const _skipHebrew = [
  'רווי', 'רוויים', 'רוויות', 'טראנס', 'טרנס', 'כולסטרול', 'חד', 'רב',
];

/// "Sugars (teaspoons)" and friends repeat a nutrient in another unit.
const _skipAnywhere = [
  'teaspoons', 'teaspoon', 'tsp', 'tablespoon', 'tablespoons', 'כפיות', 'כפית',
];

final _niqqud = RegExp('[֑-ׇ]');
final _quoteMarks = RegExp('["״\'׳`“”]');
final _hebrewLetter = RegExp('[א-ת]');
final _word = RegExp('[a-zא-ת]+');
final _qty = RegExp(
  r'(<|פחות מ)?\s*(\d+(?:[.,]\d+)?)\s*(%|[a-zא-ת]+)?',
);
final _massUnit = RegExp(r'^(?:g|gr|ml|גרם|מל)$');

String _normalize(String text) {
  const finals = {'ך': 'כ', 'ם': 'מ', 'ן': 'נ', 'ף': 'פ', 'ץ': 'צ'};
  var out = text
      .toLowerCase()
      .replaceAll(_niqqud, '')
      .replaceAll(_quoteMarks, '');
  finals.forEach((from, to) => out = out.replaceAll(from, to));
  // Tesseract reads digits inside Hebrew lines backwards ("ל-100" -> "001",
  // "30 גרם" -> "03"). A leading zero never appears in real serving sizes, so
  // flip those back.
  return out
      .split('\n')
      .map((line) {
        if (!_hebrewLetter.hasMatch(line)) return line;
        return line.replaceAllMapped(
          RegExp(r'(?<![\d.,])0\d{1,3}(?=\s*(?:g|gr|ml|גרם|מל)(?![a-zא-ת]))'),
          (m) => m.group(0)!.split('').reversed.join(),
        );
      })
      .join('\n');
}

int _distance(String a, String b) {
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce(
        (x, y) => x < y ? x : y,
      );
    }
    prev = cur;
  }
  return prev[b.length];
}

bool _matches(String word, String keyword) {
  final key = _normalize(keyword);
  // Hebrew attaches ה/ו/ב/ל/מ to the front of words.
  final candidates = {word};
  if (word.length > 3 && 'הובלמ'.contains(word[0])) {
    candidates.add(word.substring(1));
  }
  for (final w in candidates) {
    if (w == key) return true;
    if (key.length >= 5 &&
        (w.length - key.length).abs() <= 1 &&
        _distance(w, key) <= 1) {
      return true;
    }
  }
  return false;
}

/// Language of a keyword: Hebrew if it has any Hebrew letter.
bool _isHebrewWord(String w) => _hebrewLetter.hasMatch(w);

/// [language] is 'he', 'en', or null for both. A bilingual label repeats every
/// row in two languages; reading one language avoids mixing them up.
({_Field field, int index})? _detect(List<String> words, [String? language]) {
  int? skipEnglish;
  var skipHebrew = false;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (_skipAnywhere.contains(w)) return null;
    if (_skipEnglish.contains(w)) skipEnglish ??= i;
    if (_skipHebrew.contains(w)) skipHebrew = true;
  }
  for (var i = 0; i < words.length; i++) {
    if (language == 'he' && !_isHebrewWord(words[i])) continue;
    if (language == 'en' && _isHebrewWord(words[i])) continue;
    for (final entry in _keywords.entries) {
      if (entry.value.any((k) => _matches(words[i], k))) {
        if (skipHebrew) return null;
        if (skipEnglish != null && skipEnglish < i) return null;
        return (field: entry.key, index: i);
      }
    }
  }
  return null;
}

class _Qty {
  _Qty(this.value, this.unit, this.hasDecimal, this.start);
  double value;
  final String unit;

  /// Offset of the number in its line, to tell what sits before or after a label.
  final int start;

  /// False when the OCR text had no decimal point, which is where lost
  /// decimals ("1.8" read as "18") can hide.
  final bool hasDecimal;
}

List<_Qty> _quantities(String line) {
  final all = <_Qty>[];
  for (final m in _qty.allMatches(line)) {
    final unit = m.group(3) ?? '';
    if (unit == '%') continue;
    final text = m.group(2)!;
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null) continue;
    // "(0)" / ")9(" is OCR junk for a unit like "(g)", never a value.
    final from = m.start + m.group(0)!.indexOf(text);
    final to = from + text.length;
    if (from > 0 &&
        '()'.contains(line[from - 1]) &&
        to < line.length &&
        '()'.contains(line[to])) {
      continue;
    }
    all.add(_Qty(value, unit, RegExp(r'[.,]').hasMatch(text), from));
  }
  // "per 100 g" in the label itself isn't a value.
  final real = all
      .where((q) => !(q.value == 100 && _massUnit.hasMatch(q.unit)))
      .toList();
  return real.isEmpty ? all : real;
}

bool _isKcal(String unit) =>
    const {'kcal', 'cal', 'קקל', 'קלוריות'}.contains(unit);

bool _isKj(String unit) => const {'kj', 'קג'}.contains(unit);

/// Fallback when the serving size is unknown: which column of a two-column
/// table holds the per-100 values, judged from header order.
int _per100Column(List<String> lines) {
  final per100 = RegExp(r'100\s*(g|gr|ml|גרם|מל)(?![a-zא-ת])');
  final other = RegExp(
    r'(serving|portion|per\s+(?:pack|unit)|מנה|יחידה|ליחידה|מנת)|(?<![\d.])(?!100(?!\d))\d+\s*(g|gr|ml|גרם|מל)(?![a-zא-ת])',
  );
  for (final line in lines) {
    final a = per100.firstMatch(line);
    if (a == null) continue;
    for (final b in other.allMatches(line)) {
      if (b.start == a.start) continue;
      return a.start < b.start ? 0 : 1;
    }
  }
  return 0;
}

/// The serving size (grams or ml) from a header line such as
/// "Per 100 g  Per serving (60 g)" or "ל-100 גרם  למנה (30 גרם)".
double? _servingSize(List<String> lines) {
  final amount = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:g|gr|ml|גרם|מל)(?![a-zא-ת])');
  for (final line in lines) {
    final words = _word.allMatches(line).map((m) => m.group(0)!).toList();
    // Only header lines: data rows name a nutrient.
    if (_detect(words) != null) continue;
    if (!RegExp(r'per|serving|portion|מנה|למנה|יחידה|ל-|^\s*\d')
        .hasMatch(line)) {
      continue;
    }
    for (final m in amount.allMatches(line)) {
      final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
      if (v != null && v > 0 && v != 100) return v;
    }
  }
  return null;
}

bool _close(double actual, double expected) =>
    (actual - expected).abs() <= 0.15 ||
    (actual - expected).abs() <= expected.abs() * 0.08;

class _Pick {
  _Pick(this.value, this.hasDecimal, {this.verified = false});
  double value;
  bool hasDecimal;

  /// Confirmed by the serving column (value * serving / 100 matched).
  bool verified;
}

/// Chooses the per-100 number from a row of columns. With the serving size
/// known, the per-100 value is the one whose scaled twin appears in the row;
/// OCR often drops decimal points, so tenth-scaled variants are tried too.
_Pick _pick(List<_Qty> qtys, double? serving, int column) {
  if (qtys.length == 1) return _Pick(qtys[0].value, qtys[0].hasDecimal);
  if (serving != null) {
    _Pick? best;
    var bestRepairs = 99;
    for (var i = 0; i < qtys.length; i++) {
      for (var j = 0; j < qtys.length; j++) {
        if (i == j) continue;
        for (final ri in [false, true]) {
          for (final rj in [false, true]) {
            final a = qtys[i];
            final b = qtys[j];
            if ((ri && (a.hasDecimal || a.value < 10)) ||
                (rj && (b.hasDecimal || b.value < 10))) {
              continue;
            }
            final va = ri ? a.value / 10 : a.value;
            final vb = rj ? b.value / 10 : b.value;
            if (!_close(vb, va * serving / 100)) continue;
            // Zeros match every ratio and prove nothing.
            final repairs = (ri ? 1 : 0) + (rj ? 1 : 0);
            if (repairs < bestRepairs) {
              bestRepairs = repairs;
              best = _Pick(va, a.hasDecimal || ri, verified: va != 0);
            }
          }
        }
      }
    }
    if (best != null) return best;
  }
  final q = qtys[column < qtys.length ? column : qtys.length - 1];
  return _Pick(q.value, q.hasDecimal);
}

num? _round(double? v) => v == null ? null : (v * 100).round() / 100;

/// [preferHebrew] decides which language wins when a bilingual label reads
/// equally well in both.
NutritionScan parseNutritionText(String raw, {bool preferHebrew = false}) {
  final he = _parse(raw, 'he');
  final en = _parse(raw, 'en');
  if (he.found != en.found) return he.found > en.found ? he : en;
  return preferHebrew ? he : en;
}

NutritionScan _parse(String raw, String language) {
  final text = _normalize(raw);
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final liquid = RegExp(r'100\s*(ml|מל)').hasMatch(text);
  final hasPer100 = RegExp(
    r'100\s*(g|gr|ml|גרם|מל)(?![a-z\u05D0-\u05EA])',
  ).hasMatch(text);
  final serving = _servingSize(lines);
  final scale = (!hasPer100 && serving != null) ? 100 / serving : 1.0;
  final column = _per100Column(lines);

  // Only trust a serving column if at least one row actually adds up;
  // otherwise this is a single-column table (and a stray "5 g" in the header
  // must not make us discard single numbers).
  var result = _extract(lines, language, hasPer100 ? serving : null, column);
  if (result.verified == 0 && hasPer100 && serving != null) {
    result = _extract(lines, language, null, column);
  }
  final found = result.found;
  _reconcile(found);

  double? at(_Field f) {
    final p = found[f];
    return p == null ? null : p.value * scale;
  }

  var calories = at(_Field.calories);
  if (calories == null && result.kj != null) {
    calories = (result.kj! / 4.184) * scale;
  }
  final sodium = at(_Field.sodium) ?? at(_Field.salt);

  return NutritionScan(
    calories: calories == null ? null : calories.round(),
    protein: _round(at(_Field.protein)),
    carbohydrates: _round(at(_Field.carbs)),
    fat: _round(at(_Field.fat)),
    fiber: _round(at(_Field.fiber)),
    sugars: _round(at(_Field.sugars)),
    sodium: sodium == null ? null : sodium.round(),
    liquid: liquid,
    fromServing: scale != 1.0,
    raw: raw,
  );
}

({Map<_Field, _Pick> found, double? kj, int verified}) _extract(
  List<String> lines,
  String language,
  double? ratioServing,
  int column,
) {
  final found = <_Field, _Pick>{};
  double? kjFallback;
  var verified = 0;

  for (final line in lines) {
    final matches = _word.allMatches(line).toList();
    final words = matches.map((m) => m.group(0)!).toList();
    final hit = _detect(words, language);
    if (hit == null) continue;
    final keywordEnd = matches[hit.index].end;
    var qtys = _quantities(line);

    // A value follows its label; a number before it is usually noise from
    // outside the table. Fall back to the closest number before the label
    // when the English label comes after its value on a bilingual line.
    final after = qtys.where((q) => q.start >= keywordEnd).toList();
    if (after.isNotEmpty) {
      qtys = after;
    } else {
      final before = qtys.where((q) => q.start < keywordEnd).toList();
      qtys = before.isEmpty ? <_Qty>[] : [before.last];
    }
    if (qtys.isEmpty) continue;

    if (hit.field == _Field.calories) {
      final kcal = qtys.where((q) => _isKcal(q.unit)).toList();
      if (kcal.isEmpty) {
        final kj = qtys.where((q) => _isKj(q.unit)).toList();
        if (kj.isNotEmpty && kjFallback == null) {
          kjFallback = kj[column < kj.length ? column : kj.length - 1].value;
        }
        if (qtys.every((q) => _isKj(q.unit))) continue;
        qtys = qtys.where((q) => !_isKj(q.unit)).toList();
      } else {
        qtys = kcal;
      }
    }

    if (found.containsKey(hit.field) && hit.field != _Field.calories) continue;
    // One number in a two-column table could be either column: leave it empty
    // rather than guess.
    if (ratioServing != null && qtys.length == 1) continue;
    final pick = _pick(qtys, ratioServing, column);
    if (pick.verified) verified++;
    final unit = qtys.first.unit;
    if (hit.field == _Field.sodium && (unit == 'g' || unit == 'גרם')) {
      pick.value *= 1000;
    }
    if (hit.field == _Field.salt) {
      // Salt is ~40% sodium.
      pick.value = (unit == 'mg' || unit == 'מג')
          ? pick.value * 0.4
          : pick.value * 400;
    }
    if (hit.field == _Field.calories &&
        found.containsKey(_Field.calories) &&
        !qtys.any((q) => _isKcal(q.unit))) {
      continue;
    }
    found[hit.field] = pick;
  }
  return (found: found, kj: kjFallback, verified: verified);
}

/// Cross-checks the numbers against each other, repairing lost decimals where
/// that makes the label add up and dropping values that are impossible, so we
/// leave a field empty rather than invent a number.
void _reconcile(Map<_Field, _Pick> found) {
  final macros = [_Field.protein, _Field.carbs, _Field.fat];
  final kcal = found[_Field.calories]?.value;

  // Calories should be ~ 4*protein + 4*carbs + 9*fat (+ a little for fibre
  // and alcohol). Try tenth-scaled variants of unverified, decimal-less values.
  if (kcal != null && kcal > 0 && macros.every(found.containsKey)) {
    double error(Map<_Field, double> v) {
      final est = 4 * v[_Field.protein]! +
          4 * v[_Field.carbs]! +
          9 * v[_Field.fat]!;
      final fiber = found[_Field.fiber]?.value ?? 0;
      final low = est;
      final high = est + 2 * fiber + 0.1 * est;
      if (kcal >= low * 0.8 && kcal <= high * 1.1) return 0;
      return kcal < low ? (low - kcal) / kcal : (kcal - high) / kcal;
    }

    final original = {for (final f in macros) f: found[f]!.value};
    if (error(original) > 0) {
      final fixable = [
        for (final f in macros)
          if (!found[f]!.hasDecimal && found[f]!.value >= 10)
            f,
      ];
      Map<_Field, double>? best;
      var bestError = error(original);
      for (var mask = 1; mask < (1 << fixable.length); mask++) {
        final trial = {...original};
        for (var i = 0; i < fixable.length; i++) {
          if (mask & (1 << i) != 0) trial[fixable[i]] = trial[fixable[i]]! / 10;
        }
        final e = error(trial);
        if (e < bestError) {
          bestError = e;
          best = trial;
        }
      }
      if (best != null && bestError == 0) {
        best.forEach((f, v) => found[f]!.value = v);
      }
    }
  }

  // Sugars are part of the carbohydrates; fibre can't exceed them either.
  final carbs = found[_Field.carbs]?.value;
  for (final f in [_Field.sugars, _Field.fiber]) {
    final p = found[f];
    if (p == null || carbs == null) continue;
    if (p.value > carbs + 0.5) found.remove(f);
  }

  // Impossible per-100 values.
  for (final f in [
    _Field.protein, _Field.carbs, _Field.fat, _Field.fiber, _Field.sugars,
  ]) {
    final p = found[f];
    if (p != null && (p.value > 100 || p.value < 0)) found.remove(f);
  }
  final cal = found[_Field.calories];
  if (cal != null && cal.value > 900) found.remove(_Field.calories);
}
