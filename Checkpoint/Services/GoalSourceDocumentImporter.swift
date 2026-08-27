import Foundation
import UniformTypeIdentifiers

#if canImport(PDFKit)
import PDFKit
#endif

enum GoalSourceImportError: LocalizedError, Equatable, Sendable {
    case fileTooLarge
    case unsupportedType
    case unreadableFile
    case noExtractableText
    case tooLittleText

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "The file is too large. Choose a file under 20 MB."
        case .unsupportedType:
            return "That file type isn't supported. Choose a text, Markdown, or PDF file."
        case .unreadableFile:
            return "Checkpoint couldn't read that file."
        case .noExtractableText:
            return "No selectable text was found. Scanned PDFs need OCR before import."
        case .tooLittleText:
            return "The file doesn't contain enough text to improve the questions."
        }
    }
}

struct GoalSourceImportResult: Sendable {
    var documents: [GoalSourceDocument]
    var failureMessages: [String]
}

enum GoalSourceDocumentImporter {
    static let supportedContentTypes: [UTType] = [.text, .pdf]
    private static let knownTextExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "xml", "yaml", "yml",
        "html", "htm", "log", "swift", "py", "js", "ts", "css", "sql"
    ]

    static func importDocuments(from urls: [URL]) async -> GoalSourceImportResult {
        await Task.detached(priority: .userInitiated) {
            var documents: [GoalSourceDocument] = []
            var failureMessages: [String] = []

            for url in urls {
                do {
                    documents.append(try loadDocument(from: url))
                } catch {
                    let detail = (error as? LocalizedError)?.errorDescription
                        ?? GoalSourceImportError.unreadableFile.localizedDescription
                    failureMessages.append("\(url.lastPathComponent): \(detail)")
                }
            }

            return GoalSourceImportResult(
                documents: documents,
                failureMessages: failureMessages
            )
        }.value
    }

    static func loadDocument(from url: URL) throws -> GoalSourceDocument {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let fallbackFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber
        if let fileSize = resourceValues?.fileSize ?? fallbackFileSize?.intValue,
           fileSize > GoalContextLimits.maximumImportFileBytes {
            throw GoalSourceImportError.fileTooLarge
        }

        let contentType = resourceValues?.contentType
        let text: String
        if contentType?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            text = try extractedPDFText(from: url)
        } else if contentType?.conforms(to: .text) == true
            || knownTextExtensions.contains(url.pathExtension.lowercased()) {
            text = try extractedPlainText(from: url)
        } else {
            throw GoalSourceImportError.unsupportedType
        }

        let document = GoalSourceDocument(name: url.lastPathComponent, text: text)
        guard document.characterCount >= GoalContextLimits.minimumUsefulDocumentCharacters else {
            throw GoalSourceImportError.tooLittleText
        }
        return document
    }

    private static func extractedPlainText(from url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw GoalSourceImportError.unreadableFile
        }
        guard data.count <= GoalContextLimits.maximumImportFileBytes else {
            throw GoalSourceImportError.fileTooLarge
        }

        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1
        ]
        guard let text = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first else {
            throw GoalSourceImportError.unreadableFile
        }
        return text
    }

    private static func extractedPDFText(from url: URL) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            throw GoalSourceImportError.unreadableFile
        }

        var pageText: [String] = []
        var extractedCharacterCount = 0
        for pageIndex in 0..<document.pageCount {
            guard let text = document.page(at: pageIndex)?.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            pageText.append(text)
            extractedCharacterCount += text.count
            if extractedCharacterCount >= GoalContextLimits.maximumCharactersPerDocument {
                break
            }
        }

        let text = pageText.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GoalSourceImportError.noExtractableText
        }
        return text
        #else
        throw GoalSourceImportError.unsupportedType
        #endif
    }
}
