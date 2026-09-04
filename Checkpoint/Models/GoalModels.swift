import Foundation

enum GoalCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case codingInterview = "Coding Interview"
    case examPrep = "Exam Prep"
    case languageLearning = "Language Learning"
    case fitness = "Fitness"
    case writing = "Writing"
    case custom = "Custom"

    var id: String { rawValue }
}

enum SkillMapStatus: String, Codable, Equatable, Sendable {
    case suggested
    case reviewed
}

enum SkillMapProvenance: String, Codable, Equatable, Sendable {
    case backendInferred
    case explicitFocusAreas
    case questionTopics
    case userEdited
    case adaptiveEvolution
}

enum ArchivedSkillReason: String, Codable, Equatable, Sendable {
    case mastered
    case userRemoved
}

struct SkillMapObjective: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String

    init(
        id: UUID = UUID(),
        name: String
    ) {
        self.id = id
        self.name = SkillMapTopic.normalizedName(name)
    }
}

struct SkillMapTopic: Identifiable, Codable, Equatable, Sendable {
    static let maximumActiveObjectiveCount = 5

    var id: UUID
    var name: String
    var aliases: [String]
    var objectives: [SkillMapObjective]
    var stage: Int
    var predecessorIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        objectives: [SkillMapObjective] = [],
        stage: Int = 1,
        predecessorIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.objectives = objectives
        self.stage = max(1, stage)
        self.predecessorIDs = predecessorIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case aliases
        case objectives
        case stage
        case predecessorIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        objectives = try container.decodeIfPresent([SkillMapObjective].self, forKey: .objectives) ?? []
        stage = max(1, try container.decodeIfPresent(Int.self, forKey: .stage) ?? 1)
        predecessorIDs = try container.decodeIfPresent([UUID].self, forKey: .predecessorIDs) ?? []
    }

    static func normalizedName(_ rawName: String) -> String {
        rawName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:-"))
    }

    static func canonicalIdentityKey(_ rawName: String) -> String {
        normalizedName(rawName)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    func limitedToActiveObjectiveCount() -> SkillMapTopic {
        guard objectives.count > Self.maximumActiveObjectiveCount else { return self }
        var limitedTopic = self
        limitedTopic.objectives = Array(objectives.prefix(Self.maximumActiveObjectiveCount))
        return limitedTopic
    }

    static func validatedNames(
        _ rawNames: [String],
        allowedCount: ClosedRange<Int> = 3...6
    ) -> [String]? {
        guard allowedCount.contains(rawNames.count) else { return nil }

        let unsupportedSeparators = CharacterSet(charactersIn: ",;\n")
        let names = rawNames.map(normalizedName)
        guard names.allSatisfy({ name in
            (1...48).contains(name.count) &&
                name.rangeOfCharacter(from: unsupportedSeparators) == nil
        }) else {
            return nil
        }

        let keys = names.map(canonicalIdentityKey)
        guard Set(keys).count == keys.count else { return nil }
        return names
    }
}

struct ArchivedSkillMasterySnapshot: Codable, Equatable, Sendable {
    var estimatedLevel: Double
    var masteryPercent: Int
    var attempts: Int
    var correct: Int
    var partial: Int
    var incorrect: Int
    var currentStreak: Int
}

struct ArchivedSkillMapTopic: Identifiable, Codable, Equatable, Sendable {
    var topic: SkillMapTopic
    var reason: ArchivedSkillReason
    var archivedAt: Date
    var successorSkillIDs: [SkillMapTopic.ID]
    var mastery: ArchivedSkillMasterySnapshot?

    var id: SkillMapTopic.ID { topic.id }
}

struct GoalSkillMap: Codable, Equatable, Sendable {
    var version: Int
    var provenance: SkillMapProvenance
    var topics: [SkillMapTopic]
    var archivedTopics: [ArchivedSkillMapTopic]
    var status: SkillMapStatus
    var evolutionEnabled: Bool
    var lastEvolvedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        topics: [SkillMapTopic],
        archivedTopics: [ArchivedSkillMapTopic] = [],
        status: SkillMapStatus = .suggested,
        version: Int = 1,
        provenance: SkillMapProvenance = .questionTopics,
        evolutionEnabled: Bool = true,
        lastEvolvedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.version = max(1, version)
        self.provenance = provenance
        self.topics = topics.map { $0.limitedToActiveObjectiveCount() }
        self.archivedTopics = archivedTopics
        self.status = status
        self.evolutionEnabled = evolutionEnabled
        self.lastEvolvedAt = lastEvolvedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case version
        case provenance
        case topics
        case archivedTopics
        case status
        case evolutionEnabled
        case lastEvolvedAt
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = max(1, try container.decodeIfPresent(Int.self, forKey: .version) ?? 1)
        provenance = try container.decodeIfPresent(SkillMapProvenance.self, forKey: .provenance)
            ?? .questionTopics
        topics = try container.decode([SkillMapTopic].self, forKey: .topics)
            .map { $0.limitedToActiveObjectiveCount() }
        archivedTopics = try container.decodeIfPresent(
            [ArchivedSkillMapTopic].self,
            forKey: .archivedTopics
        ) ?? []
        status = try container.decodeIfPresent(SkillMapStatus.self, forKey: .status) ?? .suggested
        evolutionEnabled = try container.decodeIfPresent(Bool.self, forKey: .evolutionEnabled) ?? true
        lastEvolvedAt = try container.decodeIfPresent(Date.self, forKey: .lastEvolvedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var topicNames: [String] {
        topics.map(\.name)
    }
}

enum SkillMapEvolutionFailure: String, Codable, Equatable, Sendable {
    case invalidResponse
    case safetyIntervention
}

struct SkillMapEvolutionIntent: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var goalID: Goal.ID
    var baseVersion: Int
    var baseMapFingerprint: String
    var masteredSkillIDs: [SkillMapTopic.ID]
    var createdAt: Date
    var lastAttemptAt: Date?
    var lastFailure: SkillMapEvolutionFailure?
    var invalidResponseAttemptCount: Int

    init(
        id: UUID = UUID(),
        goalID: Goal.ID,
        baseVersion: Int,
        baseMapFingerprint: String,
        masteredSkillIDs: [SkillMapTopic.ID],
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        lastFailure: SkillMapEvolutionFailure? = nil,
        invalidResponseAttemptCount: Int = 0
    ) {
        self.id = id
        self.goalID = goalID
        self.baseVersion = baseVersion
        self.baseMapFingerprint = baseMapFingerprint
        self.masteredSkillIDs = masteredSkillIDs
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.lastFailure = lastFailure
        self.invalidResponseAttemptCount = max(0, invalidResponseAttemptCount)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case goalID
        case baseVersion
        case baseMapFingerprint
        case masteredSkillIDs
        case createdAt
        case lastAttemptAt
        case lastFailure
        case invalidResponseAttemptCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        goalID = try container.decode(Goal.ID.self, forKey: .goalID)
        baseVersion = try container.decode(Int.self, forKey: .baseVersion)
        baseMapFingerprint = try container.decode(String.self, forKey: .baseMapFingerprint)
        masteredSkillIDs = try container.decode([SkillMapTopic.ID].self, forKey: .masteredSkillIDs)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        lastFailure = try container.decodeIfPresent(SkillMapEvolutionFailure.self, forKey: .lastFailure)
        invalidResponseAttemptCount = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .invalidResponseAttemptCount) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(goalID, forKey: .goalID)
        try container.encode(baseVersion, forKey: .baseVersion)
        try container.encode(baseMapFingerprint, forKey: .baseMapFingerprint)
        try container.encode(masteredSkillIDs, forKey: .masteredSkillIDs)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastAttemptAt, forKey: .lastAttemptAt)
        try container.encodeIfPresent(lastFailure, forKey: .lastFailure)
        try container.encode(invalidResponseAttemptCount, forKey: .invalidResponseAttemptCount)
    }
}

enum GoalContextLimits {
    static let maximumDocumentCount = 5
    static let maximumDocumentNameLength = 80
    static let maximumCharactersPerDocument = 12_000
    static let maximumTotalDocumentCharacters = 24_000
    static let minimumUsefulDocumentCharacters = 40
    static let maximumImportFileBytes = 20 * 1_024 * 1_024
}

struct GoalSourceDocument: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var text: String
    var importedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        text: String,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.text = Self.normalizedText(text, limit: GoalContextLimits.maximumCharactersPerDocument)
        self.importedAt = importedAt
    }

    var characterCount: Int {
        text.count
    }

    static func normalizedDocuments(_ documents: [GoalSourceDocument]) -> [GoalSourceDocument] {
        var seenText: Set<String> = []
        var candidates: [GoalSourceDocument] = []

        for document in documents {
            let normalized = GoalSourceDocument(
                id: document.id,
                name: document.name,
                text: document.text,
                importedAt: document.importedAt
            )
            guard normalized.text.count >= GoalContextLimits.minimumUsefulDocumentCharacters else { continue }

            let duplicateKey = normalized.text.lowercased()
            guard seenText.insert(duplicateKey).inserted else { continue }
            candidates.append(normalized)
            if candidates.count >= GoalContextLimits.maximumDocumentCount { break }
        }

        let allocations = fairCharacterAllocations(
            for: candidates.map(\.characterCount),
            totalLimit: GoalContextLimits.maximumTotalDocumentCharacters
        )
        return zip(candidates, allocations).compactMap { document, allocation in
            let text = normalizedText(document.text, limit: allocation)
            guard text.count >= GoalContextLimits.minimumUsefulDocumentCharacters else { return nil }
            return GoalSourceDocument(
                id: document.id,
                name: document.name,
                text: text,
                importedAt: document.importedAt
            )
        }
    }

    private static func normalizedName(_ rawName: String) -> String {
        let collapsed = rawName
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = collapsed.isEmpty ? "Study material" : collapsed
        return String(resolved.prefix(GoalContextLimits.maximumDocumentNameLength))
    }

    private static func normalizedText(_ rawText: String, limit: Int) -> String {
        guard limit > 0 else { return "" }

        let normalizedLineEndings = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        var previousLineWasEmpty = false

        for rawLine in normalizedLineEndings.components(separatedBy: "\n") {
            let line = rawLine
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isEmpty = line.isEmpty
            if isEmpty && previousLineWasEmpty {
                continue
            }
            lines.append(line)
            previousLineWasEmpty = isEmpty
        }

        let normalized = lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }

        let marker = "\n[…truncated…]\n"
        guard limit > marker.count + 2 else {
            return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let availableCharacters = limit - marker.count
        let prefixCount = (availableCharacters * 3) / 5
        let suffixCount = availableCharacters - prefixCount
        return String(normalized.prefix(prefixCount)).trimmingCharacters(in: .whitespacesAndNewlines)
            + marker
            + String(normalized.suffix(suffixCount)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fairCharacterAllocations(for lengths: [Int], totalLimit: Int) -> [Int] {
        guard !lengths.isEmpty else { return [] }
        guard lengths.reduce(0, +) > totalLimit else { return lengths }

        var allocations = Array(repeating: 0, count: lengths.count)
        var unresolved = Set(lengths.indices)
        var remaining = totalLimit

        while !unresolved.isEmpty {
            let share = remaining / unresolved.count
            let smallDocuments = unresolved.filter { lengths[$0] <= share }
            if smallDocuments.isEmpty {
                let orderedIndices = unresolved.sorted()
                let remainder = remaining % orderedIndices.count
                for (offset, index) in orderedIndices.enumerated() {
                    allocations[index] = share + (offset < remainder ? 1 : 0)
                }
                break
            }

            for index in smallDocuments {
                allocations[index] = lengths[index]
                remaining -= lengths[index]
                unresolved.remove(index)
            }
        }

        return allocations
    }
}

struct Goal: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var deadline: Date
    var category: GoalCategory
    var currentLevel: String
    var focusAreas: String
    var sourceDocuments: [GoalSourceDocument]
    var derivedSkillMap: GoalSkillMap?
    var preferredQuestionStyle: QuestionFormat
    var minimumQuestionDifficulty: Int
    var createdAt = Date()

    init(
        id: UUID = UUID(),
        title: String,
        deadline: Date,
        category: GoalCategory,
        currentLevel: String,
        focusAreas: String,
        sourceDocuments: [GoalSourceDocument] = [],
        derivedSkillMap: GoalSkillMap? = nil,
        preferredQuestionStyle: QuestionFormat,
        minimumQuestionDifficulty: Int = UnlockPolicy.default.minimumQuestionDifficulty,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.deadline = deadline
        self.category = category
        self.currentLevel = currentLevel
        self.focusAreas = focusAreas
        self.sourceDocuments = GoalSourceDocument.normalizedDocuments(sourceDocuments)
        self.derivedSkillMap = derivedSkillMap
        self.preferredQuestionStyle = preferredQuestionStyle
        self.minimumQuestionDifficulty = UnlockPolicy.normalizedQuestionDifficulty(minimumQuestionDifficulty)
        self.createdAt = createdAt
    }

    var difficultyLabel: String {
        Self.difficultyLabel(for: minimumQuestionDifficulty)
    }

    static func difficultyLabel(for level: Int) -> String {
        switch UnlockPolicy.normalizedQuestionDifficulty(level) {
        case 1:
            return "Basics"
        case 2:
            return "Foundational"
        case 3:
            return "Intermediate"
        case 4:
            return "Advanced"
        default:
            return "Expert"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case deadline
        case category
        case currentLevel
        case focusAreas
        case sourceDocuments
        case derivedSkillMap
        case preferredQuestionStyle
        case minimumQuestionDifficulty
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        deadline = try container.decode(Date.self, forKey: .deadline)
        category = try container.decode(GoalCategory.self, forKey: .category)
        currentLevel = try container.decode(String.self, forKey: .currentLevel)
        focusAreas = try container.decode(String.self, forKey: .focusAreas)
        sourceDocuments = GoalSourceDocument.normalizedDocuments(
            try container.decodeIfPresent([GoalSourceDocument].self, forKey: .sourceDocuments) ?? []
        )
        derivedSkillMap = try container.decodeIfPresent(GoalSkillMap.self, forKey: .derivedSkillMap)
        preferredQuestionStyle = try container.decode(QuestionFormat.self, forKey: .preferredQuestionStyle)
        minimumQuestionDifficulty = UnlockPolicy.normalizedQuestionDifficulty(
            try container.decodeIfPresent(Int.self, forKey: .minimumQuestionDifficulty)
                ?? UnlockPolicy.default.minimumQuestionDifficulty
        )
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct GoalDisplayTitleResolver {
    let titlesByID: [Goal.ID: String]

    init(
        goals: [Goal],
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let groups = Dictionary(grouping: goals) { goal in
            Self.comparisonKey(for: goal.title, locale: locale)
        }

        titlesByID = groups.values.reduce(into: [Goal.ID: String]()) { result, matchingGoals in
            guard matchingGoals.count > 1 else {
                if let goal = matchingGoals.first {
                    result[goal.id] = goal.title
                }
                return
            }

            let shortLabels = matchingGoals.map { goal in
                let dueDate = Self.formattedDeadline(
                    goal.deadline,
                    includesYear: false,
                    calendar: calendar,
                    locale: locale,
                    timeZone: timeZone
                )
                return "\(goal.title) · due \(dueDate)"
            }

            let normalizedShortLabels = Set(
                shortLabels.map { Self.comparisonKey(for: $0, locale: locale) }
            )
            if normalizedShortLabels.count == matchingGoals.count {
                for (goal, label) in zip(matchingGoals, shortLabels) {
                    result[goal.id] = label
                }
                return
            }

            let longLabels = matchingGoals.map { goal in
                let dueDate = Self.formattedDeadline(
                    goal.deadline,
                    includesYear: true,
                    calendar: calendar,
                    locale: locale,
                    timeZone: timeZone
                )
                return "\(goal.title) · due \(dueDate)"
            }

            let normalizedLongLabels = Set(
                longLabels.map { Self.comparisonKey(for: $0, locale: locale) }
            )
            if normalizedLongLabels.count == matchingGoals.count {
                for (goal, label) in zip(matchingGoals, longLabels) {
                    result[goal.id] = label
                }
                return
            }

            let stableGoals = matchingGoals.sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
            for (index, goal) in stableGoals.enumerated() {
                let labelIndex = matchingGoals.firstIndex { $0.id == goal.id } ?? 0
                result[goal.id] = "\(longLabels[labelIndex]) · profile \(index + 1)"
            }
        }
    }

    func title(for goal: Goal) -> String {
        titlesByID[goal.id] ?? goal.title
    }

    func title(for goalID: Goal.ID, fallback: String) -> String {
        titlesByID[goalID] ?? fallback
    }

    private static func comparisonKey(
        for title: String,
        locale: Locale
    ) -> String {
        title
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
    }

    private static func formattedDeadline(
        _ date: Date,
        includesYear: Bool,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(includesYear ? "MMMdy" : "MMMd")
        return formatter.string(from: date)
    }
}
