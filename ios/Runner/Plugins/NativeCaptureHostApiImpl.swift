import Flutter
import UIKit
import PhotosUI
import Vision
import Security
import CommonCrypto

class NativeCaptureHostApiImpl: NSObject, NativeCaptureHostApi {

    private weak var controller: FlutterViewController?
    private let appGroupId = "group.com.singwallet.app"
    private let keychainService = "com.singwallet.app.keychain"
    private let dbKeyAccount = "master_db_key_v1"
    private let safeIdRegex = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_-]+$")

    init(controller: FlutterViewController?) {
        self.controller = controller
        super.init()
    }

    private var appGroupDirectoryURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    fileprivate var pendingCapturesURL: URL? {
        guard let baseURL = appGroupDirectoryURL else { return nil }
        let dir = baseURL.appendingPathComponent("PendingCaptures", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - NativeCaptureHostApi

    func pickSingleImage(completion: @escaping (Result<CaptureResult?, Error>) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let rootVC = self.controller else {
                completion(.success(nil))
                return
            }

            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1

            let picker = PHPickerViewController(configuration: config)
            let delegateWrapper = PickerDelegateWrapper(impl: self, completion: completion)
            picker.delegate = delegateWrapper
            objc_setAssociatedObject(picker, "PickerDelegateKey", delegateWrapper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            rootVC.present(picker, animated: true)
        }
    }

    func fetchPendingExternalCaptures() throws -> [CaptureResult] {
        guard let capturesDir = pendingCapturesURL else { return [] }
        var results: [CaptureResult] = []

        let fileURLs = (try? FileManager.default.contentsOfDirectory(at: capturesDir, includingPropertiesForKeys: nil)) ?? []
        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "jpg" || fileURL.pathExtension.lowercased() == "png" {
            let captureId = fileURL.deletingPathExtension().lastPathComponent
            if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                let hash = calculateSha256(fileURL: fileURL)
                results.append(CaptureResult(
                    captureId: captureId,
                    localFilePath: fileURL.path,
                    imageWidth: Int64(width),
                    imageHeight: Int64(height),
                    contentHash: hash,
                    sourceKind: .systemShare
                ))
            }
        }
        return results
    }

    func recognizeCapture(captureId: String, completion: @escaping (Result<OcrDocument, Error>) -> Void) {
        let startTime = Date()
        let range = NSRange(location: 0, length: captureId.utf16.count)
        guard safeIdRegex.firstMatch(in: captureId, options: [], range: range) != nil else {
            completion(.failure(NSError(domain: "SingWallet", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid captureId format: \(captureId)"])))
            return
        }

        guard let capturesDir = pendingCapturesURL else {
            completion(.failure(NSError(domain: "SingWallet", code: 500, userInfo: [NSLocalizedDescriptionKey: "Captures directory unavailable"])))
            return
        }

        let jpgURL = capturesDir.appendingPathComponent("\(captureId).jpg")
        let pngURL = capturesDir.appendingPathComponent("\(captureId).png")
        let imageURL = FileManager.default.fileExists(atPath: jpgURL.path) ? jpgURL : pngURL

        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            completion(.failure(NSError(domain: "SingWallet", code: 404, userInfo: [NSLocalizedDescriptionKey: "FILE_NOT_FOUND: \(captureId)"])))
            return
        }

        guard let ciImage = CIImage(contentsOf: imageURL) else {
            completion(.failure(NSError(domain: "SingWallet", code: 422, userInfo: [NSLocalizedDescriptionKey: "UNREADABLE_IMAGE: \(captureId)"])))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                let doc = OcrDocument(
                    captureId: captureId,
                    lines: [],
                    engineIdentifier: "AppleVision_iOS_17",
                    processTimeMs: Int64(Date().timeIntervalSince(startTime) * 1000)
                )
                completion(.success(doc))
                return
            }

            var textLines: [OcrTextLine] = []
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let visionBox = observation.boundingBox

                // Apple Vision coordinate inversion to Top-Left origin [0.0, 1.0]
                let flutterLeft = max(0.0, min(1.0, Double(visionBox.origin.x)))
                let flutterTop = max(0.0, min(1.0, Double(1.0 - visionBox.origin.y - visionBox.size.height)))
                let flutterWidth = max(0.0, min(1.0, Double(visionBox.size.width)))
                let flutterHeight = max(0.0, min(1.0, Double(visionBox.size.height)))

                let boundingBox = OcrBoundingBox(
                    left: flutterLeft,
                    top: flutterTop,
                    width: flutterWidth,
                    height: flutterHeight
                )

                textLines.append(OcrTextLine(
                    text: candidate.string,
                    boundingBox: boundingBox,
                    confidence: Double(candidate.confidence)
                ))
            }

            let latency = Int64(Date().timeIntervalSince(startTime) * 1000)
            let document = OcrDocument(
                captureId: captureId,
                lines: textLines,
                engineIdentifier: "AppleVision_iOS_17",
                processTimeMs: max(1, latency)
            )
            completion(.success(document))
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }

    func deleteCaptureImage(captureId: String) throws -> Bool {
        let range = NSRange(location: 0, length: captureId.utf16.count)
        guard safeIdRegex.firstMatch(in: captureId, options: [], range: range) != nil else {
            return false
        }
        guard let capturesDir = pendingCapturesURL else { return false }
        let jpgURL = capturesDir.appendingPathComponent("\(captureId).jpg")
        let pngURL = capturesDir.appendingPathComponent("\(captureId).png")
        var deleted = false
        if FileManager.default.fileExists(atPath: jpgURL.path) {
            try? FileManager.default.removeItem(at: jpgURL)
            deleted = true
        }
        if FileManager.default.fileExists(atPath: pngURL.path) {
            try? FileManager.default.removeItem(at: pngURL)
            deleted = true
        }
        return deleted || (!FileManager.default.fileExists(atPath: jpgURL.path) && !FileManager.default.fileExists(atPath: pngURL.path))
    }

    func readImageFromClipboard() throws -> CaptureResult? {
        guard let image = UIPasteboard.general.image,
              let data = image.jpegData(compressionQuality: 0.95),
              let capturesDir = pendingCapturesURL else {
            return nil
        }

        let captureId = "clip_\(Int64(Date().timeIntervalSince1970 * 1000))"
        let targetURL = capturesDir.appendingPathComponent("\(captureId).jpg")
        try data.write(to: targetURL)

        return CaptureResult(
            captureId: captureId,
            localFilePath: targetURL.path,
            imageWidth: Int64(image.size.width * image.scale),
            imageHeight: Int64(image.size.height * image.scale),
            contentHash: calculateSha256(data: data),
            sourceKind: .clipboard
        )
    }

    func startOneShotScreenCapture(completion: @escaping (Result<CaptureResult?, Error>) -> Void) {
        // iOS sandboxing permanently prohibits background/third-party screen capture
        completion(.success(nil))
    }

    func getOrCreateDatabaseKey(completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: dbKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let keyData = item as? Data, keyData.count == 32 {
            completion(.success(FlutterStandardTypedData(bytes: keyData)))
            return
        }

        // Generate 32 cryptographically secure random bytes
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let randStatus = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        guard randStatus == errSecSuccess else {
            completion(.failure(NSError(domain: "SingWallet", code: Int(randStatus), userInfo: [NSLocalizedDescriptionKey: "SecRandomCopyBytes failed"])))
            return
        }

        let newKeyData = Data(keyBytes)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: dbKeyAccount,
            kSecValueData as String: newKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            completion(.failure(NSError(domain: "SingWallet", code: Int(addStatus), userInfo: [NSLocalizedDescriptionKey: "SecItemAdd failed: \(addStatus)"])))
            return
        }

        completion(.success(FlutterStandardTypedData(bytes: newKeyData)))
    }

    // MARK: - Utilities

    private func calculateSha256(fileURL: URL) -> String {
        guard let data = try? Data(contentsOf: fileURL) else { return "" }
        return calculateSha256(data: data)
    }

    fileprivate func calculateSha256(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - PHPicker Delegate Helper
private class PickerDelegateWrapper: NSObject, PHPickerViewControllerDelegate {
    private let impl: NativeCaptureHostApiImpl
    private let completion: (Result<CaptureResult?, Error>) -> Void

    init(impl: NativeCaptureHostApiImpl, completion: @escaping (Result<CaptureResult?, Error>) -> Void) {
        self.impl = impl
        self.completion = completion
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let itemProvider = results.first?.itemProvider,
              itemProvider.canLoadObject(ofClass: UIImage.self) else {
            completion(.success(nil))
            return
        }

        itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            if let error = error {
                self?.completion(.failure(error))
                return
            }
            guard let image = object as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.95),
                  let capturesDir = self?.impl.pendingCapturesURL else {
                self?.completion(.success(nil))
                return
            }

            let captureId = "picker_\(Int64(Date().timeIntervalSince1970 * 1000))"
            let targetURL = capturesDir.appendingPathComponent("\(captureId).jpg")
            do {
                try data.write(to: targetURL)
                let hash = self?.impl.calculateSha256(data: data) ?? ""
                let result = CaptureResult(
                    captureId: captureId,
                    localFilePath: targetURL.path,
                    imageWidth: Int64(image.size.width * image.scale),
                    imageHeight: Int64(image.size.height * image.scale),
                    contentHash: hash,
                    sourceKind: .photoPicker
                )
                self?.completion(.success(result))
            } catch {
                self?.completion(.failure(error))
            }
        }
    }
}
