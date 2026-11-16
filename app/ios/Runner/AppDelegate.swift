import Flutter
import UIKit
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PHPhotoLibraryChangeObserver {
  private var cameraRollChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    // Register change observer for automatic real-time camera roll detection
    PHPhotoLibrary.shared().register(self)
    
    // Fallback channel initialization if needed
    if cameraRollChannel == nil, let controller = window?.rootViewController as? FlutterViewController {
      setupCameraRollChannel(binaryMessenger: controller.binaryMessenger)
    }
    
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "P2PmeCameraRoll") {
      setupCameraRollChannel(binaryMessenger: registrar.messenger())
    }
  }

  private func setupCameraRollChannel(binaryMessenger: FlutterBinaryMessenger) {
    if cameraRollChannel != nil { return }
    let channel = FlutterMethodChannel(name: "net.p2pme/camera_roll", binaryMessenger: binaryMessenger)
    cameraRollChannel = channel

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      switch call.method {
      case "requestPermission":
        PHPhotoLibrary.requestAuthorization { status in
          DispatchQueue.main.async {
            result(status == .authorized || status == .limited)
          }
        }
      case "checkPermission":
        let status = PHPhotoLibrary.authorizationStatus()
        result(status == .authorized || status == .limited)
      case "getAssetCount":
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "(mediaSubtype & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        result(fetchResult.count)
      case "getAssets":
        let args = call.arguments as? [String: Any]
        let limit = args?["limit"] as? Int ?? 0
        let sinceTimestamp = args?["since"] as? Double
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var predicates: [NSPredicate] = [
          NSPredicate(format: "(mediaSubtype & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        ]
        if let since = sinceTimestamp, since > 0 {
          let date = Date(timeIntervalSince1970: since / 1000.0)
          predicates.append(NSPredicate(format: "creationDate > %@", date as NSDate))
        }
        fetchOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        var items: [[String: Any]] = []
        let count = (limit > 0) ? min(fetchResult.count, limit) : fetchResult.count
        for i in 0..<count {
          let asset = fetchResult.object(at: i)
          let resources = PHAssetResource.assetResources(for: asset)
          let filename = resources.first?.originalFilename ?? "IMG_\(asset.localIdentifier.prefix(8)).jpg"
          var fileSize: Int64 = 0
          if let res = resources.first {
            if let sizeVal = res.value(forKey: "fileSize") as? CLong {
              fileSize = Int64(sizeVal)
            }
          }
          let item: [String: Any] = [
            "id": asset.localIdentifier,
            "filename": filename,
            "created": (asset.creationDate?.timeIntervalSince1970 ?? 0) * 1000.0,
            "mediaType": asset.mediaType == .video ? "video" : "image",
            "duration": asset.duration,
            "pixelWidth": asset.pixelWidth,
            "pixelHeight": asset.pixelHeight,
            "fileSize": fileSize,
          ]
          items.append(item)
        }
        result(items)
      case "exportAsset":
        guard let args = call.arguments as? [String: Any],
              let assetId = args["id"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "asset id missing", details: nil))
          return
        }
        self.exportAssetToFile(assetId: assetId, result: result)
      case "openUrl":
        guard let args = call.arguments as? [String: Any],
              let urlStr = args["url"] as? String,
              let url = URL(string: urlStr) else {
          result(false)
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        }
      case "getStorageSpace":
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
          let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
          let freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
          let totalBytes = Int64(values.volumeTotalCapacity ?? 0)
          result([
            "free_bytes": freeBytes,
            "total_bytes": totalBytes,
          ])
        } catch {
          result([
            "free_bytes": Int64(0),
            "total_bytes": Int64(0),
          ])
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // PHPhotoLibraryChangeObserver callback - triggers whenever a photo or video is added/modified
  func photoLibraryDidChange(_ changeInstance: PHChange) {
    DispatchQueue.main.async { [weak self] in
      self?.cameraRollChannel?.invokeMethod("onCameraRollChanged", arguments: nil)
    }
  }

  private func exportAssetToFile(assetId: String, result: @escaping FlutterResult) {
    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
    guard let asset = fetchResult.firstObject else {
      result(FlutterError(code: "NOT_FOUND", message: "Asset not found", details: nil))
      return
    }

    let resources = PHAssetResource.assetResources(for: asset)
    guard let resource = resources.first else {
      result(FlutterError(code: "NO_RESOURCE", message: "No resource for asset", details: nil))
      return
    }

    let filename = resource.originalFilename
    let tempDir = FileManager.default.temporaryDirectory
    let safeName = filename.replacingOccurrences(of: " ", with: "_")
    let targetUrl = tempDir.appendingPathComponent("p2pme_\(safeName)")

    // Clean up old file if exists
    try? FileManager.default.removeItem(at: targetUrl)

    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = true

    PHAssetResourceManager.default().writeData(for: resource, toFile: targetUrl, options: options) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "EXPORT_FAILED", message: error.localizedDescription, details: nil))
        } else {
          result(targetUrl.path)
        }
      }
    }
  }
}
