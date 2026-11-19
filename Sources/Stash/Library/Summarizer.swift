import Foundation
import FoundationModels

/// Writes short page summaries with Apple's on-device model (Apple Intelligence).
/// Nothing leaves the Mac. On Macs without Apple Intelligence it does nothing.
enum Summarizer {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// Two or three sentences about `text`, in the page's language, or nil.
    static func summarize(title: String, text: String) async -> String? {
        guard isAvailable else { return nil }
        // ponytail: the model's window is 4,096 tokens for input and output; the opening of a page carries its point.
        let excerpt = String(text.prefix(6_000))
        let session = LanguageModelSession(instructions: """
            You summarize saved web pages for a personal library. Write two or three plain sentences \
            that say what the page is about and why it is useful. Use the language of the page. \
            Do not start with "This page" or "The article".
            """)
        do {
            let response = try await session.respond(to: "Title: \(title)\n\n\(excerpt)")
            let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? nil : summary
        } catch {
            logger.info("Summary failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
