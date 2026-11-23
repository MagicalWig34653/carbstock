import CarbStockCore
import Foundation
import HealthKit

/// A place completed workouts can be read from. Read-only: nothing is ever written back.
/// The real implementation is Apple Health; tests use a fake (no HealthKit in unit tests).
protocol WorkoutSource: Sendable {
    var source: ActivitySource { get }
    var isAvailable: Bool { get }
    /// Shows the system permission sheet (only the first time per data type).
    func requestAccess() async throws
    /// Completed cycling workouts that started at or after `since`.
    func cyclingWorkouts(since: Date) async throws -> [ExternalActivity]
}

enum WorkoutSourceError: Error, Equatable {
    case unavailable
    /// Health data is encrypted while the device is locked; try again later.
    case deviceLocked
    case failed
}

/// Apple Health through HealthKit: reads `HKWorkout` of type cycling, keeps only start and duration
/// (data minimisation: no heart rate, power, calories, route, source device). Never writes, never shares.
struct HealthKitWorkoutSource: WorkoutSource {
    let source: ActivitySource = .health
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async throws {
        guard isAvailable else { throw WorkoutSourceError.unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
        } catch {
            throw WorkoutSourceError.failed
        }
    }

    func cyclingWorkouts(since: Date) async throws -> [ExternalActivity] {
        guard isAvailable else { throw WorkoutSourceError.unavailable }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        let cycling = HKQuery.predicateForWorkouts(with: .cycling)
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, cycling]))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
        do {
            let workouts = try await query.result(for: store)
            return workouts.map {
                ExternalActivity(source: .health, externalID: $0.uuid.uuidString, start: $0.startDate,
                                 movingSeconds: $0.duration, elapsedSeconds: $0.duration, sport: .cycling)
            }
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            throw WorkoutSourceError.deviceLocked
        } catch {
            throw WorkoutSourceError.failed
        }
    }
}
