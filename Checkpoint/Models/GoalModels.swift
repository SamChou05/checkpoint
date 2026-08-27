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
    var id: UUID
    var name: String
    var aliases: [String]
    var objectives: [SkillMapObjective]

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        objectives: [SkillMapObjective] = []
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.objectives = objectives
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case aliases
        case objectives
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        objectives = try container.decodeIfPresent([SkillMapObjective].self, forKey: .objectives) ?? []
    }

    static func normalizedName(_ rawName: String) -> String {
        rawName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .:-"))
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

        let keys = names.map { $0.lowercased() }
        guard Set(keys).count == keys.count else { return nil }
        return names
    }
}

struct GoalSkillMap: Codable, Equatable, Sendable {
    var version: Int
    var provenance: SkillMapProvenance
    var topics: [SkillMapTopic]
    var status: SkillMapStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        topics: [SkillMapTopic],
        status: SkillMapStatus = .suggested,
        version: Int = 1,
        provenance: SkillMapProvenance = .questionTopics,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.version = max(1, version)
        self.provenance = provenance
        self.topics = topics
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case version
        case provenance
        case topics
        case status
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = max(1, try container.decodeIfPresent(Int.self, forKey: .version) ?? 1)
        provenance = try container.decodeIfPresent(SkillMapProvenance.self, forKey: .provenance)
            ?? .questionTopics
        topics = try container.decode([SkillMapTopic].self, forKey: .topics)
        status = try container.decodeIfPresent(SkillMapStatus.self, forKey: .status) ?? .suggested
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var topicNames: [String] {
        topics.map(\.name)
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
