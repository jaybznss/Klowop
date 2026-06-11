import Foundation
import HealthKit
import Observation

/// Apple Health integration.
///
/// Writes: meals logged in Klowop become dietary samples (energy, protein, carbs, fat).
/// Reads:  Apple Watch activity (active energy, steps, exercise minutes) and body
///         composition (weight, body fat %, lean mass) — smart scales like the
///         Hume BodyPod sync those into Apple Health automatically.
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    struct ActivitySnapshot {
        var activeEnergy: Double      // kcal
        var steps: Double
        var exerciseMinutes: Double
    }

    struct BodySnapshot {
        var weightKg: (value: Double, date: Date)?
        var bodyFatFraction: (value: Double, date: Date)?   // 0...1
        var leanMassKg: (value: Double, date: Date)?
        var isEmpty: Bool { weightKg == nil && bodyFatFraction == nil && leanMassKg == nil }
    }

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "healthkit_enabled") }
    }
    var activity: ActivitySnapshot?
    var bodyComposition = BodySnapshot()
    var lastError: String?

    private let store = HKHealthStore()

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "healthkit_enabled")
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static func quantity(_ id: HKQuantityTypeIdentifier) -> HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: id)!
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        let read: Set<HKObjectType> = [
            Self.quantity(.activeEnergyBurned),
            Self.quantity(.stepCount),
            Self.quantity(.appleExerciseTime),
            Self.quantity(.bodyMass),
            Self.quantity(.bodyFatPercentage),
            Self.quantity(.leanBodyMass),
        ]
        let write: Set<HKSampleType> = [
            Self.quantity(.dietaryEnergyConsumed),
            Self.quantity(.dietaryProtein),
            Self.quantity(.dietaryCarbohydrates),
            Self.quantity(.dietaryFatTotal),
        ]
        try await store.requestAuthorization(toShare: write, read: read)
        isEnabled = true
        await refresh()
    }

    // MARK: - Read (activity for a day + latest body composition)

    func refresh(day: Date = .now) async {
        guard isEnabled, Self.isAvailable else { return }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

        async let energy = sum(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let steps = sum(.stepCount, unit: .count(), start: start, end: end)
        async let exercise = sum(.appleExerciseTime, unit: .minute(), start: start, end: end)
        activity = ActivitySnapshot(activeEnergy: await energy,
                                    steps: await steps,
                                    exerciseMinutes: await exercise)

        async let weight = latest(.bodyMass, unit: .gramUnit(with: .kilo))
        async let bodyFat = latest(.bodyFatPercentage, unit: .percent())
        async let leanMass = latest(.leanBodyMass, unit: .gramUnit(with: .kilo))
        bodyComposition = BodySnapshot(weightKg: await weight,
                                       bodyFatFraction: await bodyFat,
                                       leanMassKg: await leanMass)
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: Self.quantity(id),
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    struct HistorySample: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    /// Historical samples for trend charts (e.g. weight over the last 90 days).
    func history(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int = 90) async -> [HistorySample] {
        guard isEnabled, Self.isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: Self.quantity(id), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let history = (samples as? [HKQuantitySample] ?? []).map {
                    HistorySample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: history)
            }
            store.execute(query)
        }
    }

    func weightHistory(days: Int = 90) async -> [HistorySample] {
        await history(.bodyMass, unit: .gramUnit(with: .kilo), days: days)
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> (Double, Date)? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: Self.quantity(id), predicate: nil,
                                      limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.startDate))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Write meals

    /// Saves a logged meal as dietary samples. Returns an identifier that lets us
    /// delete the samples later if the meal is removed in the app.
    func logMeal(name: String, calories: Int, protein: Double, carbs: Double,
                 fat: Double, date: Date) async -> String? {
        guard isEnabled, Self.isAvailable else { return nil }
        let uuid = UUID().uuidString
        let metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: uuid,
            HKMetadataKeyFoodType: name,
        ]
        func sample(_ id: HKQuantityTypeIdentifier, _ value: Double, _ unit: HKUnit) -> HKQuantitySample {
            HKQuantitySample(type: Self.quantity(id),
                             quantity: HKQuantity(unit: unit, doubleValue: value),
                             start: date, end: date, metadata: metadata)
        }
        var samples = [sample(.dietaryEnergyConsumed, Double(calories), .kilocalorie())]
        if protein > 0 { samples.append(sample(.dietaryProtein, protein, .gram())) }
        if carbs > 0 { samples.append(sample(.dietaryCarbohydrates, carbs, .gram())) }
        if fat > 0 { samples.append(sample(.dietaryFatTotal, fat, .gram())) }
        do {
            try await store.save(samples)
            return uuid
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func deleteMeal(uuid: String) async {
        guard isEnabled, Self.isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                                    allowedValues: [uuid])
        let types: [HKQuantityTypeIdentifier] = [.dietaryEnergyConsumed, .dietaryProtein,
                                                 .dietaryCarbohydrates, .dietaryFatTotal]
        for id in types {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.deleteObjects(of: Self.quantity(id), predicate: predicate) { _, _, _ in
                    continuation.resume()
                }
            }
        }
    }
}
