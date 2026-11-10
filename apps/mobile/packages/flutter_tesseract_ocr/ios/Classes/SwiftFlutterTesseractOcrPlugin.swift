import Flutter
import UIKit
import libtesseract

/// Drives libtesseract directly (instead of SwiftyTesseract's wrapper) so we
/// can choose the page segmentation mode. Without a block mode Tesseract
/// splits table columns away from their row labels. Language data is read
/// from the app's Documents/tessdata folder, which the Dart side fills; the
/// original plugin symlinked into the read-only app bundle and crashed.
public class SwiftFlutterTesseractOcrPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_tesseract_ocr", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterTesseractOcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "extractText" else {
            result(FlutterMethodNotImplemented)
            return
        }
        guard let params = call.arguments as? [String: Any],
              let imagePath = params["imagePath"] as? String,
              let image = UIImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage else {
            result(FlutterError(code: "bad_args", message: "Could not read the image", details: nil))
            return
        }
        let language = (params["language"] as? String) ?? "eng"
        let options = params["args"] as? [String: Any] ?? [:]
        let psm = Int(options["psm"] as? String ?? "") ?? 6

        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            result(FlutterError(code: "no_documents", message: "No documents directory", details: nil))
            return
        }
        let tessdata = documents.appendingPathComponent("tessdata").path
        for code in language.split(separator: "+") {
            if !FileManager.default.fileExists(atPath: "\(tessdata)/\(code).traineddata") {
                result(FlutterError(code: "missing_language", message: "Missing \(code).traineddata", details: nil))
                return
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = SwiftFlutterTesseractOcrPlugin.recognize(
                cgImage, tessdata: tessdata, language: language, psm: psm)
            DispatchQueue.main.async {
                switch outcome {
                case .success(let text): result(text)
                case .failure(let message):
                    result(FlutterError(code: "ocr_failed", message: message, details: nil))
                }
            }
        }
    }

    private enum Outcome {
        case success(String)
        case failure(String)
    }

    private static func recognize(_ image: CGImage, tessdata: String, language: String, psm: Int) -> Outcome {
        let width = image.width
        let height = image.height
        // Hand Tesseract the colour pixels: its own thresholding reads
        // coloured table panels far better than a plain grayscale conversion.
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !drawn { return .failure("Could not prepare the image") }

        guard let api = TessBaseAPICreate() else { return .failure("Could not start Tesseract") }
        defer { TessBaseAPIDelete(api) }

        if TessBaseAPIInit2(api, tessdata, language, TessOcrEngineMode(rawValue: 1)) != 0 {
            return .failure("Could not load the language data")
        }
        TessBaseAPISetPageSegMode(api, TessPageSegMode(rawValue: UInt32(psm)))
        TessBaseAPISetVariable(api, "preserve_interword_spaces", "1")
        pixels.withUnsafeBufferPointer { buffer in
            TessBaseAPISetImage(api, buffer.baseAddress, Int32(width), Int32(height), 4, Int32(bytesPerRow))
        }
        TessBaseAPISetSourceResolution(api, 300)
        guard let cString = TessBaseAPIGetUTF8Text(api) else { return .failure("No text returned") }
        defer { TessDeleteText(cString) }
        return .success(String(cString: cString))
    }
}
