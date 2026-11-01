import Flutter
import HealthKit
import UIKit

/// Reads weight, steps, exercise minutes, and active energy from Apple Health.
///
/// Dart calls this through the `dropit/health` method channel for foreground syncs. HealthKit
/// background delivery wakes the app without booting Flutter, so uploads for that path are made
/// here, with the session token Dart already stores in Application Support/session.json.
final class HealthSync {
  static let shared = HealthSync()

  private static let jerusalem = TimeZone(identifier: "Asia/Jerusalem")!
  private static let windowDays = 35
  private static let chunkSize = 500

  private let store = HKHealthStore()
  private let defaults = UserDefaults.standard
  private let enabledKey = "dropit.health.enabled"
  private let baseUrlKey = "dropit.health.baseUrl"
  private let anchorKey = "dropit.health.weightAnchor"

  private let stateLock = NSLock()
  private var pendingAnchors: [String: HKQueryAnchor] = [:]
  private var observers: [HKObserverQuery] = []
  private var lastBackgroundFinish = Date.distantPast
  private let uploadQueue = DispatchQueue(label: "dropit.health.upload")
  private var channel: FlutterMethodChannel?

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = HealthSync.jerusalem
    return calendar
  }()

  private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }()

  private var weightType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .bodyMass)! }
  private var stepType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .stepCount)! }
  private var exerciseType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)! }
  private var energyType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)! }

  private var readTypes: Set<HKObjectType> { [weightType, stepType, exerciseType, energyType] }

  // MARK: Channel

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dropit/health", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  /// Called on every launch, including background launches caused by HealthKit delivery.
  func resumeIfEnabled() {
    guard HKHealthStore.isHealthDataAvailable(), defaults.bool(forKey: enabledKey) else { return }
    startObservers()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(HKHealthStore.isHealthDataAvailable())
    case "requestAuthorization":
      guard HKHealthStore.isHealthDataAvailable() else {
        result(false)
        return
      }
      // Read access is never reported back by HealthKit, so `success` only means the sheet finished.
      store.requestAuthorization(toShare: nil, read: readTypes) { success, error in
        DispatchQueue.main.async { result(success && error == nil) }
      }
    case "readPayload":
      // After an app update HealthKit treats read access as not determined until this
      // process asks again, even when the Health app still shows access as granted.
      // The sheet only appears if iOS still needs a decision.
      readPayload(prompt: true) { outcome in
        DispatchQueue.main.async {
          switch outcome {
          case .success(let payload):
            result(payload)
          case .failure(let error):
            result(FlutterError(
              code: error == .authorization ? "authorization_denied" : "read_failed",
              message: "Could not read Apple Health",
              details: nil
            ))
          }
        }
      }
    case "commit":
      if let token = (call.arguments as? [String: Any])?["token"] as? String {
        commit(token: token)
      }
      result(nil)
    case "start":
      let baseUrl = (call.arguments as? [String: Any])?["baseUrl"] as? String
      defaults.set(true, forKey: enabledKey)
      if let baseUrl = baseUrl { defaults.set(baseUrl, forKey: baseUrlKey) }
      startObservers()
      result(nil)
    case "stop":
      stopObservers()
      defaults.removeObject(forKey: enabledKey)
      defaults.removeObject(forKey: baseUrlKey)
      defaults.removeObject(forKey: anchorKey)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Reading

  private enum ReadFailure: Equatable {
    case authorization
    case failed
  }

  private final class ReadState {
    private let lock = NSLock()
    private var recorded: ReadFailure?
    var weights: [[String: Any]] = []
    var deleted: [String] = []
    var anchor: HKQueryAnchor?
    var steps: [String: Double] = [:]
    var exercise: [String: Double] = [:]
    var energy: [String: Double] = [:]

    func note(_ failure: ReadFailure) {
      lock.lock()
      if recorded != .authorization { recorded = failure }
      lock.unlock()
    }

    var failure: ReadFailure? {
      lock.lock()
      defer { lock.unlock() }
      return recorded
    }
  }

  /// Collects everything new since the last committed sync. The weight anchor only moves forward
  /// when `commit` is called after a successful upload, so a failed upload is retried.
  ///
  /// `prompt` asks HealthKit to confirm access first. Foreground syncs need this: after an update,
  /// queries fail with "not determined" until `requestAuthorization` runs again.
  private func readPayload(prompt: Bool = false, completion: @escaping (Result<[String: Any], ReadFailure>) -> Void) {
    let read: () -> Void = { [weak self] in
      guard let self = self else {
        completion(.failure(.failed))
        return
      }
      let anchor = self.loadAnchor()
      self.collect(anchor: anchor) { result in
        guard case .failure(let error) = result, error != .authorization, anchor != nil else {
          completion(result)
          return
        }
        // A saved anchor from before the update can make the weight query fail.
        // Read from the beginning once; commit replaces the anchor after a successful upload.
        self.collect(anchor: nil, completion: completion)
      }
    }
    guard prompt else {
      read()
      return
    }
    refreshAuthorization(completion: read)
  }

  private func refreshAuthorization(completion: @escaping () -> Void) {
    let ask = { [weak self] in
      guard let self = self, HKHealthStore.isHealthDataAvailable() else {
        completion()
        return
      }
      self.store.requestAuthorization(toShare: nil, read: self.readTypes) { _, _ in
        DispatchQueue.main.async(execute: completion)
      }
    }
    if Thread.isMainThread {
      ask()
    } else {
      DispatchQueue.main.async(execute: ask)
    }
  }

  private func collect(anchor: HKQueryAnchor?, completion: @escaping (Result<[String: Any], ReadFailure>) -> Void) {
    let group = DispatchGroup()
    let state = ReadState()
    let now = Date()
    // HealthKit aligns day buckets to the device calendar. Label those buckets as Jerusalem
    // days afterwards so the payload matches the server.
    let queryCalendar = Calendar.current
    let anchorDate = queryCalendar.startOfDay(for: now)
    let queryStart = queryCalendar.date(byAdding: .day, value: -HealthSync.windowDays, to: anchorDate) ?? anchorDate
    let dayInterval = DateComponents(day: 1)

    group.enter()
    let weightQuery = HKAnchoredObjectQuery(
      type: weightType,
      predicate: nil,
      anchor: anchor,
      limit: HKObjectQueryNoLimit
    ) { [weak self] _, added, removed, newAnchor, error in
      defer { group.leave() }
      guard let self = self else { return }
      if let failure = self.readFailure(error) {
        state.note(failure)
        return
      }
      var weights: [[String: Any]] = []
      for case let sample as HKQuantitySample in added ?? [] {
        let externalId = sample.uuid.uuidString
        let kilograms = (sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo)) * 100).rounded() / 100
        let loggedAt = self.isoFormatter.string(from: sample.startDate)
        guard externalId.count <= 64, kilograms.isFinite, kilograms > 0, kilograms <= 500, !loggedAt.isEmpty else { continue }
        weights.append([
          "externalId": externalId,
          "weightKg": kilograms,
          "loggedAt": loggedAt,
        ])
      }
      state.weights = weights
      state.deleted = (removed ?? []).map { $0.uuid.uuidString }.filter { !$0.isEmpty && $0.count <= 64 }
      state.anchor = newAnchor
    }
    store.execute(weightQuery)

    func collectDaily(_ type: HKQuantityType, unit: HKUnit, into assign: @escaping ([String: Double]) -> Void) {
      group.enter()
      let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: now, options: [])
      let query = HKStatisticsCollectionQuery(
        quantityType: type,
        quantitySamplePredicate: predicate,
        options: .cumulativeSum,
        anchorDate: anchorDate,
        intervalComponents: dayInterval
      )
      query.initialResultsHandler = { [weak self] _, collection, error in
        defer { group.leave() }
        guard let self = self else { return }
        if let failure = self.readFailure(error) {
          state.note(failure)
          return
        }
        var values: [String: Double] = [:]
        collection?.enumerateStatistics(from: queryStart, to: now) { statistics, _ in
          let key = self.dayString(statistics.startDate)
          values[key, default: 0] += statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
        assign(values)
      }
      store.execute(query)
    }

    collectDaily(stepType, unit: .count()) { state.steps = $0 }
    collectDaily(exerciseType, unit: .minute()) { state.exercise = $0 }
    collectDaily(energyType, unit: .kilocalorie()) { state.energy = $0 }

    group.notify(queue: .global()) { [weak self] in
      guard let self = self else {
        completion(.failure(.failed))
        return
      }
      if let failure = state.failure {
        completion(.failure(failure))
        return
      }
      let today = self.calendar.startOfDay(for: now)
      guard let start = self.calendar.date(byAdding: .day, value: -(HealthSync.windowDays - 1), to: today) else {
        completion(.failure(.failed))
        return
      }
      var days: [[String: Any]] = []
      for offset in 0..<HealthSync.windowDays {
        guard let date = self.calendar.date(byAdding: .day, value: offset, to: start) else { continue }
        let key = self.dayString(date)
        days.append([
          "day": key,
          "steps": self.bounded(state.steps[key] ?? 0, limit: 1_000_000),
          "exerciseMinutes": self.bounded(state.exercise[key] ?? 0, limit: 1440),
          "activeKcal": self.bounded(state.energy[key] ?? 0, limit: 20_000),
        ])
      }
      let token = UUID().uuidString
      if let newAnchor = state.anchor {
        self.stateLock.lock()
        self.pendingAnchors[token] = newAnchor
        self.stateLock.unlock()
      }
      completion(.success([
        "weights": state.weights,
        "deletedWeightIds": state.deleted,
        "days": days,
        "token": token,
      ]))
    }
  }

  /// `nil` when there is no error, or the only error is an empty series.
  private func readFailure(_ error: Error?) -> ReadFailure? {
    guard let error else { return nil }
    let ns = error as NSError
    guard ns.domain == HKErrorDomain else { return .failed }
    if ns.code == HKError.Code.errorNoData.rawValue { return nil }
    if ns.code == HKError.Code.errorAuthorizationDenied.rawValue
        || ns.code == HKError.Code.errorAuthorizationNotDetermined.rawValue {
      return .authorization
    }
    return .failed
  }

  /// Clamps a daily total into the range the sync API accepts.
  private func bounded(_ value: Double, limit: Double) -> Double {
    guard value.isFinite else { return 0 }
    return min(max(value, 0), limit).rounded()
  }

  private func dayString(_ date: Date) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  // MARK: Anchor

  private func loadAnchor() -> HKQueryAnchor? {
    guard let data = defaults.data(forKey: anchorKey) else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
  }

  private func commit(token: String) {
    stateLock.lock()
    let anchor = pendingAnchors.removeValue(forKey: token)
    stateLock.unlock()
    guard let anchor = anchor,
          let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    else { return }
    defaults.set(data, forKey: anchorKey)
  }

  // MARK: Background delivery

  private func startObservers() {
    stopObservers()
    let types: [HKQuantityType] = [weightType, stepType, exerciseType, energyType]
    for type in types {
      store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
      let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
        guard let self = self, error == nil else {
          return
        }
        self.backgroundSync(completion: completion)
      }
      store.execute(query)
      observers.append(query)
    }
  }

  private func stopObservers() {
    for query in observers { store.stop(query) }
    observers.removeAll()
    store.disableAllBackgroundDelivery { _, _ in }
  }

  private func backgroundSync(completion: @escaping () -> Void) {
    uploadQueue.async { [weak self] in
      guard let self = self else {
        completion()
        return
      }
      // Four observers usually fire together; one upload covers all of them.
      if Date().timeIntervalSince(self.lastBackgroundFinish) < 30 {
        completion()
        return
      }
      guard self.defaults.bool(forKey: self.enabledKey),
            let baseUrl = self.defaults.string(forKey: self.baseUrlKey),
            let token = self.sessionToken()
      else {
        completion()
        return
      }
      let finished = DispatchSemaphore(value: 0)
      self.readPayload { outcome in
        guard case let .success(payload) = outcome else {
          finished.signal()
          return
        }
        self.upload(payload: payload, baseUrl: baseUrl, bearer: token) { success in
          if success, let commitToken = payload["token"] as? String { self.commit(token: commitToken) }
          finished.signal()
        }
      }
      _ = finished.wait(timeout: .now() + 25)
      self.lastBackgroundFinish = Date()
      completion()
    }
  }

  private func sessionToken() -> String? {
    guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
          let data = try? Data(contentsOf: dir.appendingPathComponent("session.json")),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = json["token"] as? String,
          !token.isEmpty
    else { return nil }
    return token
  }

  private func upload(payload: [String: Any], baseUrl: String, bearer: String, completion: @escaping (Bool) -> Void) {
    guard let url = URL(string: baseUrl + "/api/apple-health/sync") else {
      completion(false)
      return
    }
    let weights = payload["weights"] as? [[String: Any]] ?? []
    let deleted = payload["deletedWeightIds"] as? [String] ?? []
    let days = payload["days"] as? [[String: Any]] ?? []

    var bodies: [[String: Any]] = []
    var index = 0
    while index < weights.count {
      let end = min(index + HealthSync.chunkSize, weights.count)
      bodies.append(["weights": Array(weights[index..<end]), "deletedWeightIds": [String](), "days": [[String: Any]]()])
      index = end
    }
    index = 0
    while index < deleted.count {
      let end = min(index + HealthSync.chunkSize, deleted.count)
      bodies.append(["weights": [[String: Any]](), "deletedWeightIds": Array(deleted[index..<end]), "days": [[String: Any]]()])
      index = end
    }
    // The last request always carries the days, so lastSyncedAt moves even with no new weights.
    bodies.append(["weights": [[String: Any]](), "deletedWeightIds": [String](), "days": days])

    func send(_ position: Int) {
      if position >= bodies.count {
        completion(true)
        return
      }
      guard let data = try? JSONSerialization.data(withJSONObject: bodies[position]) else {
        completion(false)
        return
      }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
      request.httpBody = data
      URLSession.shared.dataTask(with: request) { _, response, error in
        guard error == nil, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
          completion(false)
          return
        }
        send(position + 1)
      }.resume()
    }
    send(0)
  }
}
