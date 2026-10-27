import Flutter
import HealthKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Vo2MaxBridge") {
      Vo2MaxBridge.register(with: registrar)
    }
  }
}

/// The health plugin has no VO2 max type, so this reads it straight from HealthKit.
final class Vo2MaxBridge: NSObject, FlutterPlugin {
  private let store = HKHealthStore()
  private let vo2Max = HKQuantityType.quantityType(forIdentifier: .vo2Max)!
  private let unit = HKUnit.literUnit(with: .milli)
    .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "newme/vo2max", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(Vo2MaxBridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(nil)
      return
    }
    switch call.method {
    case "requestAccess":
      store.requestAuthorization(toShare: nil, read: [vo2Max]) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "latest":
      guard let args = call.arguments as? [String: Any],
        let startMs = args["startMs"] as? NSNumber,
        let endMs = args["endMs"] as? NSNumber
      else {
        result(FlutterError(code: "bad_args", message: "startMs and endMs are required", details: nil))
        return
      }
      let predicate = HKQuery.predicateForSamples(
        withStart: Date(timeIntervalSince1970: startMs.doubleValue / 1000),
        end: Date(timeIntervalSince1970: endMs.doubleValue / 1000),
        options: .strictStartDate)
      let newestFirst = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
      let query = HKSampleQuery(
        sampleType: vo2Max, predicate: predicate, limit: 1, sortDescriptors: [newestFirst]
      ) { [unit] _, samples, error in
        let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "query_failed", message: error.localizedDescription, details: nil))
          } else {
            result(value)
          }
        }
      }
      store.execute(query)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
