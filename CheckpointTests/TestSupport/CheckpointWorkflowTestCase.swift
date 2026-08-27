import XCTest
@testable import Checkpoint

class CheckpointWorkflowTestCase: XCTestCase {
    var defaults: UserDefaults!
    var defaultsSuiteName: String!

    // MARK: - Test lifecycle

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "CheckpointTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        resetSharedAppGroupState()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        resetSharedAppGroupState()
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    @MainActor
    func makeSeededStore(questionCount: Int) -> CheckpointStore {
        let goal = makeGoal()
        let store = CheckpointStore(defaults: defaults)
        store.goal = goal
        store.questions = (1...questionCount).map { makeQuestion(goal: goal, index: $0) }
        store.competencies = [
            .initial(topic: "arrays", estimatedLevel: 1.2),
            .initial(topic: "recursion", estimatedLevel: 2.0),
            .initial(topic: "hash maps", estimatedLevel: 1.6)
        ]
        return store
    }
}
