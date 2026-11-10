import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'copy.dart';
import 'nutrition_parser.dart';
import 'theme.dart';

/// Fixes EXIF orientation and downscales a phone photo. Deliberately no
/// grayscale/contrast tweaks: on real labels (white text on a green panel)
/// they made Tesseract lose decimals and whole rows, and nearest-neighbour
/// resizing (the `image` package default) erases decimal points, so use
/// averaging. Runs off the UI isolate.
Future<String> _prepare(String path) async {
  final dir = (await getTemporaryDirectory()).path;
  final out = '$dir/nutrition_base.png';
  await compute(_preprocess, [path, out]);
  return out;
}

void _preprocess(List<String> args) {
  final decoded = img.decodeImage(File(args[0]).readAsBytesSync());
  if (decoded == null) throw const FormatException('bad image');
  var image = img.bakeOrientation(decoded);
  image = _fit(image, 2400);
  File(args[1]).writeAsBytesSync(img.encodePng(image));
}

img.Image _fit(img.Image image, int longSide) {
  if (image.width >= image.height) {
    return image.width <= longSide
        ? image
        : img.copyResize(image,
            width: longSide, interpolation: img.Interpolation.average);
  }
  return image.height <= longSide
      ? image
      : img.copyResize(image,
          height: longSide, interpolation: img.Interpolation.average);
}

/// [base] rotated by [degrees] and fitted into [longSide] pixels.
Future<String> _variant(String base, int degrees, int longSide) async {
  final dir = (await getTemporaryDirectory()).path;
  final out = '$dir/nutrition_${degrees}_$longSide.png';
  await compute(_rotateResize, [base, out, '$degrees', '$longSide']);
  return out;
}

void _rotateResize(List<String> args) {
  var image = img.decodePng(File(args[0]).readAsBytesSync())!;
  final degrees = int.parse(args[2]);
  final longSide = int.parse(args[3]);
  if (degrees != 0) image = img.copyRotate(image, angle: degrees);
  image = _fit(image, longSide);
  File(args[1]).writeAsBytesSync(img.encodePng(image));
}

Future<NutritionScan> _read(String file, String psm, bool preferHebrew) async {
  final text = await FlutterTesseractOcr.extractText(
    file,
    language: 'heb+eng',
    args: {'psm': psm},
  );
  return parseNutritionText(text, preferHebrew: preferHebrew).withRaw(text);
}

/// Reads a photo of a nutrition table. The photo may be sideways or upside
/// down, so a quick low-resolution pass is tried at each rotation first and
/// the rotation where the most values can be read wins. On a label that has
/// both Hebrew and English, [preferHebrew] picks the language.
Future<NutritionScan> scanNutritionImage(
  String path, {
  bool preferHebrew = false,
}) async {
  final base = await _prepare(path);

  var rotation = 0;
  var bestFound = -1;
  for (final degrees in [0, 90, 270, 180]) {
    final small = await _variant(base, degrees, 1000);
    final scan = await _read(small, '6', preferHebrew);
    if (scan.found > bestFound) {
      bestFound = scan.found;
      rotation = degrees;
    }
    if (scan.found >= 4) break;
  }

  // Block modes keep each table row (label + its numbers) on one line. Mode 6
  // suits a tidy table; 4 copes better with uneven text sizes, so try it when
  // the first pass comes back thin and keep whichever read more.
  final full = await _variant(base, rotation, 2400);
  NutritionScan? best;
  for (final psm in ['6', '4']) {
    final scan = await _read(full, psm, preferHebrew);
    if (best == null || scan.found > best.found) best = scan;
    if (best.found >= 5) break;
  }
  return best!.withPhoto(full);
}

/// A report photo: JPEG, at most 1600 px on the long side, as base64. Phone
/// photos are several MB; this keeps an upload to a few hundred KB.
Future<String> _reportPhoto(String path) => compute(_encodeReportPhoto, path);

String _encodeReportPhoto(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) throw const FormatException('bad image');
  return base64Encode(img.encodeJpg(_fit(decoded, 1600), quality: 80));
}

/// Sends a scan the user flagged as wrong, with its photo, to the server.
Future<void> sendScanReport(
  Api api,
  NutritionScan scan,
  String note,
  String language,
) async {
  final path = scan.photo;
  if (path == null) throw StateError('no photo');
  await api.send(
    'POST',
    '/api/scan-reports',
    body: {
      'photo': await _reportPhoto(path),
      'rawText': scan.raw.length > 20000 ? scan.raw.substring(0, 20000) : scan.raw,
      'parsed': scan.toJson(),
      'note': note.trim(),
      'language': language,
    },
  );
}

/// Asks for an optional note and uploads [scan] as a bad-scan report.
Future<void> reportBadScan(
  BuildContext context,
  Api api,
  Copy t,
  NutritionScan scan,
) async {
  final note = TextEditingController();
  final send = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(t.reportScan),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.reportScanHint),
          const SizedBox(height: Gaps.md),
          TextField(
            controller: note,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(hintText: t.reportScanNote),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t.reportScanSend),
        ),
      ],
    ),
  );
  final text = note.text;
  note.dispose();
  if (send != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await sendScanReport(api, scan, text, t.lang);
    messenger.showSnackBar(SnackBar(content: Text(t.reportScanThanks)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(t.reportScanFailed)));
  }
}

/// Asks for a photo of a nutrition table, reads it, and pops a
/// [NutritionScan] (or nothing if the user backs out).
class NutritionScanScreen extends StatefulWidget {
  const NutritionScanScreen({super.key, required this.api, required this.t});
  final Api api;
  final Copy t;

  @override
  State<NutritionScanScreen> createState() => _NutritionScanScreenState();
}

class _NutritionScanScreenState extends State<NutritionScanScreen> {
  final picker = ImagePicker();
  bool busy = false;
  String error = '';
  String? photo;
  String rawText = '';
  NutritionScan? failed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => pick(ImageSource.camera));
  }

  Future<void> pick(ImageSource source) async {
    setState(() {
      error = '';
      failed = null;
    });
    XFile? file;
    try {
      file = await picker.pickImage(source: source, imageQuality: 95);
    } catch (_) {
      if (mounted) setState(() => error = widget.t.cameraUnavailable);
      return;
    }
    if (file == null || !mounted) return;
    setState(() {
      busy = true;
      photo = file!.path;
    });
    try {
      final scan = await scanNutritionImage(
        file.path,
        preferHebrew: widget.t.he,
      );
      if (!mounted) return;
      if (scan.usable) {
        Navigator.pop(context, scan);
        return;
      }
      setState(() {
        busy = false;
        rawText = scan.raw;
        failed = scan;
        error = widget.t.scanNothingFound;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = widget.t.scanFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    return Scaffold(
      appBar: AppBar(title: Text(t.scanLabel)),
      body: AppList(
        gap: Gaps.md,
        children: [
          Text(t.scanLabelHint, style: TextStyle(color: apple.labelSecondary)),
          if (photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: Image.file(File(photo!), height: 240, fit: BoxFit.cover),
            ),
          if (busy)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: Gaps.md,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                Text(t.scanReading),
              ],
            ),
          if (error.isNotEmpty) ErrorText(error),
          if (rawText.trim().isNotEmpty)
            Text(
              rawText,
              style: TextStyle(fontSize: 12, color: apple.labelSecondary),
              textDirection: TextDirection.ltr,
            ),
          if (!busy && failed != null)
            TextButton(
              onPressed: () => reportBadScan(context, widget.api, t, failed!),
              child: Text(t.reportScan),
            ),
          if (!busy) ...[
            SizedBox(
              height: Gaps.hit,
              child: FilledButton(
                onPressed: () => pick(ImageSource.camera),
                child: Text(photo == null ? t.takePhoto : t.retakePhoto),
              ),
            ),
            SizedBox(
              height: Gaps.hit,
              child: OutlinedButton(
                onPressed: () => pick(ImageSource.gallery),
                child: Text(t.chooseFromLibrary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
