import Flutter
import HealthKit
import flutter_local_notifications
import Security
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Without this the evening reminder is dropped while the app is in the foreground.
    UNUserNotificationCenter.current().delegate = self
    // A Watch tap with no network of its own wakes the phone in the background, before any
    // Flutter engine exists, so the session has to be live from launch.
    WatchRelay.shared.activate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // The Done and Snooze actions on a habit reminder run Dart in a second engine, which needs
    // the plugins (secure storage for the session, notifications for the snooze) registered.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Vo2MaxBridge") {
      Vo2MaxBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundHealth") {
      BackgroundHealth.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PushBridge") {
      PushBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CompanionBridge") {
      CompanionBridge.register(with: registrar)
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

struct BackgroundHealthConfig: Codable {
  let baseUrl: String
  let token: String
  let appKey: String
  let clientVersion: String
}

/// Its own Keychain item, readable after the first unlock so a locked phone can still push.
enum BackgroundHealthKeychain {
  private static let service = "top.npcserver.newme.background-health"
  private static let account = "config"

  private static var identity: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func save(_ config: BackgroundHealthConfig) -> Bool {
    guard let data = try? JSONEncoder().encode(config) else { return false }
    SecItemDelete(identity as CFDictionary)
    var item = identity
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
  }

  static func load() -> BackgroundHealthConfig? {
    var query = identity
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
      let data = out as? Data
    else { return nil }
    return try? JSONDecoder().decode(BackgroundHealthConfig.self, from: data)
  }

  static func delete() {
    SecItemDelete(identity as CFDictionary)
  }
}

/// Pushes daily Health totals when HealthKit wakes the app, without Flutter running.
final class BackgroundHealth: NSObject, FlutterPlugin {
  static let shared = BackgroundHealth()

  private struct Metric {
    let identifier: HKQuantityTypeIdentifier
    let key: String
    let unit: HKUnit
  }

  private struct Reading {
    let date: String
    let metric: String
    let value: Double
  }

  private let metrics = [
    Metric(identifier: .stepCount, key: "steps", unit: .count()),
    Metric(identifier: .activeEnergyBurned, key: "active_energy", unit: .kilocalorie()),
    Metric(identifier: .basalEnergyBurned, key: "basal_energy", unit: .kilocalorie()),
    Metric(identifier: .appleExerciseTime, key: "exercise_minutes", unit: .minute()),
    Metric(identifier: .distanceWalkingRunning, key: "distance_m", unit: .meter()),
    Metric(identifier: .flightsClimbed, key: "flights", unit: .count()),
  ]

  private let store = HKHealthStore()
  private let defaults = UserDefaults.standard
  private let enabledKey = "newme.background.enabled"
  private let pushedKey = "newme.background.pushed"
  private let yesterdayGraceHour = 10
  private let session = URLSession(configuration: .ephemeral)

  // Everything below is touched on the main queue only.
  private var observers: [HKObserverQuery] = []
  private var running = false
  private var rerun = false
  private var closedDates = Set<String>()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "newme/background", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      guard let args = call.arguments as? [String: Any],
        let baseUrl = args["baseUrl"] as? String,
        let token = args["token"] as? String,
        let appKey = args["appKey"] as? String,
        let clientVersion = args["clientVersion"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "baseUrl, token, appKey and clientVersion are required", details: nil))
        return
      }
      let config = BackgroundHealthConfig(
        baseUrl: baseUrl, token: token, appKey: appKey, clientVersion: clientVersion)
      guard BackgroundHealthKeychain.save(config) else {
        result(FlutterError(code: "keychain_failed", message: "Could not store the background config", details: nil))
        return
      }
      registerObserversIfEnabled()
      result(nil)
    case "enable":
      defaults.set(true, forKey: enabledKey)
      registerObserversIfEnabled()
      result(nil)
    case "clear":
      clear()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func registerObserversIfEnabled() {
    guard HKHealthStore.isHealthDataAvailable(),
      defaults.bool(forKey: enabledKey),
      BackgroundHealthKeychain.load() != nil,
      observers.isEmpty
    else { return }
    for metric in metrics {
      guard let type = HKQuantityType.quantityType(forIdentifier: metric.identifier) else { continue }
      let observer = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
        guard let self = self, error == nil else {
          completion()
          return
        }
        self.wake(completion: completion)
      }
      store.execute(observer)
      observers.append(observer)
      store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
    }
  }

  private func clear() {
    BackgroundHealthKeychain.delete()
    defaults.removeObject(forKey: enabledKey)
    defaults.removeObject(forKey: pushedKey)
    for observer in observers { store.stop(observer) }
    observers.removeAll()
    closedDates.removeAll()
    store.disableAllBackgroundDelivery { _, _ in }
  }

  private func wake(completion: @escaping () -> Void) {
    DispatchQueue.main.async {
      // The running pass reads Health again once it finishes, so this wake is covered.
      if self.running {
        self.rerun = true
        completion()
        return
      }
      self.running = true
      var task = UIBackgroundTaskIdentifier.invalid
      task = UIApplication.shared.beginBackgroundTask(withName: "newme.health") {
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
      }
      self.pass {
        self.running = false
        completion()
        if task != .invalid {
          UIApplication.shared.endBackgroundTask(task)
          task = .invalid
        }
      }
    }
  }

  private func pass(done: @escaping () -> Void) {
    rerun = false
    collectAndPush { [self] in
      if rerun {
        pass(done: done)
      } else {
        done()
      }
    }
  }

  private func collectAndPush(done: @escaping () -> Void) {
    guard let config = BackgroundHealthKeychain.load() else {
      done()
      return
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    let now = Date()
    let midnight = calendar.startOfDay(for: now)
    var days = [(start: midnight, end: now)]
    if calendar.component(.hour, from: now) < yesterdayGraceHour,
      let yesterday = calendar.date(byAdding: .day, value: -1, to: midnight)
    {
      days.append((start: yesterday, end: midnight))
    }

    let dateFormat = DateFormatter()
    dateFormat.calendar = calendar
    dateFormat.timeZone = calendar.timeZone
    dateFormat.locale = Locale(identifier: "en_US_POSIX")
    dateFormat.dateFormat = "yyyy-MM-dd"

    let collected = DispatchQueue(label: "newme.background.collected")
    var readings: [Reading] = []
    let group = DispatchGroup()
    for day in days {
      let date = dateFormat.string(from: day.start)
      let datePredicate = HKQuery.predicateForSamples(
        withStart: day.start, end: day.end, options: .strictStartDate)
      let notUserEntered = HKQuery.predicateForObjects(
        withMetadataKey: HKMetadataKeyWasUserEntered, operatorType: .notEqualTo, value: true)
      let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, notUserEntered])
      for metric in metrics {
        guard let type = HKQuantityType.quantityType(forIdentifier: metric.identifier) else { continue }
        group.enter()
        let query = HKStatisticsQuery(
          quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
        ) { _, statistics, _ in
          if let sum = statistics?.sumQuantity() {
            let value = sum.doubleValue(for: metric.unit).rounded()
            collected.sync { readings.append(Reading(date: date, metric: metric.key, value: value)) }
          }
          group.leave()
        }
        store.execute(query)
      }
    }

    group.notify(queue: .main) { [self] in
      let measuredAt = ISO8601DateFormatter().string(from: now)
      let today = dateFormat.string(from: midnight)
      let pushed = defaults.dictionary(forKey: pushedKey) as? [String: Double] ?? [:]
      let changed = readings.filter {
        !closedDates.contains($0.date) && pushed["\($0.date)|\($0.metric)"] != $0.value
      }
      guard !changed.isEmpty else {
        done()
        return
      }
      push(changed, today: today, measuredAt: measuredAt, config: config, allowFallback: true, done: done)
    }
  }

  private func push(
    _ readings: [Reading], today: String, measuredAt: String, config: BackgroundHealthConfig,
    allowFallback: Bool, done: @escaping () -> Void
  ) {
    let base = config.baseUrl.hasSuffix("/") ? String(config.baseUrl.dropLast()) : config.baseUrl
    guard let url = URL(string: base + "/api/health/daily") else {
      done()
      return
    }
    let items: [[String: Any]] = readings.map {
      [
        "date": $0.date, "metric": $0.metric, "value": $0.value,
        "source": "healthkit", "measuredAt": measuredAt,
      ]
    }
    guard let body = try? JSONSerialization.data(withJSONObject: ["items": items]) else {
      done()
      return
    }
    var request = URLRequest(url: url, timeoutInterval: 25)
    request.httpMethod = "PUT"
    request.httpBody = body
    request.setValue(config.appKey, forHTTPHeaderField: "X-App-Key")
    request.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
    request.setValue(config.clientVersion, forHTTPHeaderField: "X-Client-Version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    session.dataTask(with: request) { data, response, _ in
      DispatchQueue.main.async {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
          self.remember(readings)
        } else if status == 422, allowFallback, self.isDateClosed(data) {
          let todayOnly = readings.filter { $0.date == today }
          self.closedDates.formUnion(readings.map { $0.date }.filter { $0 != today })
          if todayOnly.isEmpty || todayOnly.count == readings.count {
            done()
            return
          }
          self.push(todayOnly, today: today, measuredAt: measuredAt, config: config, allowFallback: false, done: done)
          return
        }
        done()
      }
    }.resume()
  }

  private func isDateClosed(_ data: Data?) -> Bool {
    guard let data = data,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return object["code"] as? String == "date_closed"
  }

  private func remember(_ readings: [Reading]) {
    var pushed = defaults.dictionary(forKey: pushedKey) as? [String: Double] ?? [:]
    for reading in readings { pushed["\(reading.date)|\(reading.metric)"] = reading.value }
    // Dates sort lexically, so anything older than the newest three days can go.
    let newest = pushed.keys.compactMap { $0.split(separator: "|").first.map(String.init) }.sorted().suffix(3)
    let keep = Set(newest)
    pushed = pushed.filter { key, _ in
      guard let date = key.split(separator: "|").first else { return false }
      return keep.contains(String(date))
    }
    defaults.set(pushed, forKey: pushedKey)
  }
}

/// Remote notifications for the partner pushes. Dart decides when to register, once
/// notification permission is granted, and sends the token to the server itself.
final class PushBridge: NSObject, FlutterPlugin {
  static let shared = PushBridge()

  private var channel: FlutterMethodChannel?

  // A push tapped on a cold start arrives before Dart listens, so it waits here to be taken.
  private var pendingTap: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "newme/push", binaryMessenger: registrar.messenger())
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
    registrar.addApplicationDelegate(shared)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "register":
      DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
        result(nil)
      }
    case "unregister":
      DispatchQueue.main.async {
        UIApplication.shared.unregisterForRemoteNotifications()
        result(nil)
      }
    case "takeTap":
      DispatchQueue.main.async {
        let kind = self.pendingTap
        self.pendingTap = nil
        result(kind)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    DispatchQueue.main.async { self.channel?.invokeMethod("token", arguments: hex) }
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    DispatchQueue.main.async {
      self.channel?.invokeMethod("error", arguments: error.localizedDescription)
    }
  }

  // The reminder plugin answers for its own local notifications; a push is told apart by its
  // trigger, so exactly one handler calls the completion block.
  private func isPush(_ notification: UNNotification) -> Bool {
    notification.request.trigger is UNPushNotificationTrigger
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard isPush(notification) else { return }
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard isPush(response.notification) else { return }
    let kind = response.notification.request.content.userInfo["kind"] as? String ?? ""
    DispatchQueue.main.async {
      self.pendingTap = kind
      self.channel?.invokeMethod("tapped", arguments: kind) { [weak self] reply in
        if reply as? Bool == true { self?.pendingTap = nil }
      }
      completionHandler()
    }
  }
}
