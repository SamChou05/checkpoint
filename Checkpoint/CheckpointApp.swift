import SwiftUI
import BackgroundTasks
import OSLog
import UIKit

@main
struct CheckpointApp: App {
    @UIApplicationDelegateAdaptor(CheckpointAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(store: appDelegate.store)
        }
    }
}

@MainActor
final class CheckpointAppDelegate: NSObject, UIApplicationDelegate {
    let store = CheckpointStore(automaticallyStartsQuestionMaintenance: false)
    private let backgroundPurchaseController = PurchaseController()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        QuestionBankBackgroundScheduler.register(
            shouldSchedule: { [weak self] in
                self?.store.needsBackgroundQuestionMaintenance ?? false
            },
            maintenanceHandler: { [weak self] maximumBatchCount in
                guard let self else { return false }
                let hasMembership = await self.backgroundPurchaseController.refreshEntitlements()
                self.store.updateMembershipTier(hasMembership ? .member : .starter)
                return await self.store.performBackgroundQuestionMaintenance(
                    maximumBatchCount: maximumBatchCount
                )
            }
        )
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        store.scheduleServerQuestionReserveMaintenance()
        QuestionBankBackgroundScheduler.schedule()
    }
}

enum BackgroundTaskSchedulingStatus: String, Codable, Equatable, Sendable {
    case pending
    case submitted
    case failed
}

struct BackgroundTaskSchedulingRecord: Codable, Equatable, Sendable {
    var identifier: String
    var status: BackgroundTaskSchedulingStatus
    var statusUpdatedAt: Date
    var lastSubmittedAt: Date? = nil
    var lastObservedPendingAt: Date? = nil
    var lastFailureAt: Date? = nil
    var lastErrorDomain: String? = nil
    var lastErrorCode: Int? = nil
    var lastErrorDescription: String? = nil
}

struct QuestionBankBackgroundDiagnostics: Codable, Equatable, Sendable {
    var lastScheduleCheckAt: Date?
    var schedulingRecords: [String: BackgroundTaskSchedulingRecord] = [:]
    var lastRunTaskIdentifier: String?
    var lastRunStartedAt: Date?
    var lastRunCompletedAt: Date?
    var lastRunSucceeded: Bool?
    var lastRunExpiredAt: Date?

    mutating func recordScheduleCheck(at date: Date) {
        lastScheduleCheckAt = date
    }

    mutating func recordPending(identifier: String, at date: Date) {
        var record = schedulingRecords[identifier] ?? BackgroundTaskSchedulingRecord(
            identifier: identifier,
            status: .pending,
            statusUpdatedAt: date
        )
        record.status = .pending
        record.statusUpdatedAt = date
        record.lastObservedPendingAt = date
        schedulingRecords[identifier] = record
    }

    mutating func recordSubmission(identifier: String, at date: Date) {
        var record = schedulingRecords[identifier] ?? BackgroundTaskSchedulingRecord(
            identifier: identifier,
            status: .submitted,
            statusUpdatedAt: date
        )
        record.status = .submitted
        record.statusUpdatedAt = date
        record.lastSubmittedAt = date
        schedulingRecords[identifier] = record
    }

    mutating func recordSubmissionFailure(identifier: String, error: Error, at date: Date) {
        let error = error as NSError
        var record = schedulingRecords[identifier] ?? BackgroundTaskSchedulingRecord(
            identifier: identifier,
            status: .failed,
            statusUpdatedAt: date
        )
        record.status = .failed
        record.statusUpdatedAt = date
        record.lastFailureAt = date
        record.lastErrorDomain = error.domain
        record.lastErrorCode = error.code
        record.lastErrorDescription = error.localizedDescription
        schedulingRecords[identifier] = record
    }

    mutating func recordRunStarted(identifier: String, at date: Date) {
        lastRunTaskIdentifier = identifier
        lastRunStartedAt = date
        lastRunSucceeded = nil
    }

    mutating func recordRunCompleted(succeeded: Bool, at date: Date) {
        lastRunCompletedAt = date
        lastRunSucceeded = succeeded
    }

    mutating func recordRunExpired(at date: Date) {
        lastRunExpiredAt = date
    }

    var summary: String {
        if let failure = schedulingRecords.values
            .filter({ $0.status == .failed })
            .max(by: { $0.statusUpdatedAt < $1.statusUpdatedAt }) {
            let message = failure.lastErrorDescription ?? "Unknown scheduling error"
            return "Background scheduling needs attention: \(message)"
        }

        if lastRunSucceeded == true, let lastRunCompletedAt {
            return "Background preparation last completed \(Self.timestamp(lastRunCompletedAt))."
        }

        if lastRunSucceeded == false, let lastRunCompletedAt {
            return "Background preparation last stopped without completing \(Self.timestamp(lastRunCompletedAt))."
        }

        if let lastScheduleCheckAt {
            let scheduledCount = schedulingRecords.values.filter {
                $0.status == .pending || $0.status == .submitted
            }.count
            return "\(scheduledCount) background task request\(scheduledCount == 1 ? " was" : "s were") accepted by iOS; timing is system-managed. Last checked \(Self.timestamp(lastScheduleCheckAt))."
        }

        return "No background scheduling checks recorded yet."
    }

    var supportText: String {
        var lines = [
            "Background Question Preparation",
            "Last schedule check: \(Self.optionalTimestamp(lastScheduleCheckAt))",
            "Last run task: \(lastRunTaskIdentifier ?? "none")",
            "Last run started: \(Self.optionalTimestamp(lastRunStartedAt))",
            "Last run completed: \(Self.optionalTimestamp(lastRunCompletedAt))",
            "Last run succeeded: \(lastRunSucceeded.map(String.init) ?? "unknown")",
            "Last run expired: \(Self.optionalTimestamp(lastRunExpiredAt))"
        ]

        for record in schedulingRecords.values.sorted(by: { $0.identifier < $1.identifier }) {
            lines.append(contentsOf: [
                "",
                "Task: \(record.identifier)",
                "Status: \(record.status.rawValue)",
                "Status updated: \(Self.timestamp(record.statusUpdatedAt))",
                "Last submitted: \(Self.optionalTimestamp(record.lastSubmittedAt))",
                "Last observed pending: \(Self.optionalTimestamp(record.lastObservedPendingAt))",
                "Last failure: \(Self.optionalTimestamp(record.lastFailureAt))",
                "Last error: \(record.lastErrorDescription ?? "none")",
                "Last error code: \(record.lastErrorDomain ?? "none") \(record.lastErrorCode.map(String.init) ?? "")"
            ])
        }

        return lines.joined(separator: "\n")
    }

    private static func optionalTimestamp(_ date: Date?) -> String {
        date.map(timestamp) ?? "never"
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

struct QuestionBankBackgroundDiagnosticsStore {
    static let persistenceKey = "questionBankBackgroundDiagnostics.v1"

    var defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> QuestionBankBackgroundDiagnostics {
        guard let data = defaults.data(forKey: Self.persistenceKey),
              let diagnostics = try? JSONDecoder().decode(QuestionBankBackgroundDiagnostics.self, from: data) else {
            return QuestionBankBackgroundDiagnostics()
        }
        return diagnostics
    }

    func save(_ diagnostics: QuestionBankBackgroundDiagnostics) {
        guard let data = try? JSONEncoder().encode(diagnostics) else { return }
        defaults.set(data, forKey: Self.persistenceKey)
    }

    func update(_ change: (inout QuestionBankBackgroundDiagnostics) -> Void) {
        var diagnostics = load()
        change(&diagnostics)
        save(diagnostics)
    }
}

@MainActor
enum QuestionBankBackgroundScheduler {
    static let refreshTaskIdentifier = "com.samchou.checkpoint.question-refresh"
    static let processingTaskIdentifier = "com.samchou.checkpoint.question-processing"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Checkpoint",
        category: "QuestionBankBackgroundScheduler"
    )
    private static let diagnosticsStore = QuestionBankBackgroundDiagnosticsStore()
    private static var didRegister = false
    private static var lastScheduleAttemptAt: Date?
    private static var maintenanceHandler: (@MainActor @Sendable (Int) async -> Bool)?
    private static var shouldScheduleHandler: (@MainActor @Sendable () -> Bool)?

    static var diagnosticsSummary: String {
        diagnosticsStore.load().summary
    }

    static var diagnosticsSupportText: String {
        diagnosticsStore.load().supportText
    }

    static func register(
        shouldSchedule: @escaping @MainActor @Sendable () -> Bool,
        maintenanceHandler: @escaping @MainActor @Sendable (Int) async -> Bool
    ) {
        self.shouldScheduleHandler = shouldSchedule
        self.maintenanceHandler = maintenanceHandler
        guard !didRegister else { return }
        didRegister = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskIdentifier,
            using: .main
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, maximumBatchCount: 1)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingTaskIdentifier,
            using: .main
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(processingTask, maximumBatchCount: 4)
        }
    }

    static func schedule(now: Date = Date()) {
        guard didRegister, shouldScheduleHandler?() ?? true else { return }
        if let lastScheduleAttemptAt,
           now.timeIntervalSince(lastScheduleAttemptAt) < 15 * 60 {
            return
        }
        lastScheduleAttemptAt = now
        diagnosticsStore.update { $0.recordScheduleCheck(at: now) }

        BGTaskScheduler.shared.getPendingTaskRequests { pendingRequests in
            let pendingIdentifiers = Set(pendingRequests.map(\.identifier))
            Task { @MainActor in
                submitMissingRequests(pendingIdentifiers: pendingIdentifiers, now: now)
            }
        }
    }

    static func missingTaskIdentifiers(pendingIdentifiers: Set<String>) -> [String] {
        [refreshTaskIdentifier, processingTaskIdentifier].filter {
            !pendingIdentifiers.contains($0)
        }
    }

    private static func submitMissingRequests(pendingIdentifiers: Set<String>, now: Date) {
        for identifier in [refreshTaskIdentifier, processingTaskIdentifier]
        where pendingIdentifiers.contains(identifier) {
            diagnosticsStore.update { $0.recordPending(identifier: identifier, at: now) }
        }

        for identifier in missingTaskIdentifiers(pendingIdentifiers: pendingIdentifiers) {
            let request: BGTaskRequest
            if identifier == refreshTaskIdentifier {
                let refreshRequest = BGAppRefreshTaskRequest(identifier: identifier)
                refreshRequest.earliestBeginDate = now.addingTimeInterval(30 * 60)
                request = refreshRequest
            } else {
                let processingRequest = BGProcessingTaskRequest(identifier: identifier)
                processingRequest.earliestBeginDate = now.addingTimeInterval(2 * 60 * 60)
                processingRequest.requiresNetworkConnectivity = true
                processingRequest.requiresExternalPower = false
                request = processingRequest
            }

            do {
                try BGTaskScheduler.shared.submit(request)
                diagnosticsStore.update { $0.recordSubmission(identifier: identifier, at: now) }
            } catch {
                diagnosticsStore.update {
                    $0.recordSubmissionFailure(identifier: identifier, error: error, at: now)
                }
                logger.error(
                    "Failed to submit background task \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private static func handle(_ task: BGTask, maximumBatchCount: Int) {
        lastScheduleAttemptAt = nil
        diagnosticsStore.update {
            $0.recordRunStarted(identifier: task.identifier, at: Date())
        }

        // A delivered BGTask request is consumed before its work begins. Queue
        // the need-gated successor up front so a jetsam or process crash during
        // entitlement refresh/generation cannot strand maintenance until the
        // next foreground launch. The completion call below remains as a
        // deduplicated retry for work that is still needed.
        schedule()

        guard let maintenanceHandler else {
            diagnosticsStore.update { $0.recordRunCompleted(succeeded: false, at: Date()) }
            task.setTaskCompleted(success: false)
            return
        }

        let operation = Task { @MainActor in
            let succeeded = await maintenanceHandler(maximumBatchCount)
            let completed = succeeded && !Task.isCancelled
            diagnosticsStore.update { $0.recordRunCompleted(succeeded: completed, at: Date()) }
            task.setTaskCompleted(success: completed)
            // A transient provider failure still consumes the current OS request.
            // Re-request while the bank remains below target; schedule() is need-gated.
            schedule()
        }
        task.expirationHandler = {
            operation.cancel()
            Task { @MainActor in
                diagnosticsStore.update { $0.recordRunExpired(at: Date()) }
            }
        }
    }
}
