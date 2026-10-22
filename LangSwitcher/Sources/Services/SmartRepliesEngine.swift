import Foundation

// MARK: - Smart Replies Engine
// Generates quick, contextual response pills (Affirmative, Deferral, Decline)
// based on dialogue context, inquiries, and questions.

public struct SmartRepliesEngine {

    public enum ReplyCategory: String, CaseIterable, Sendable {
        case affirmative
        case deferral
        case decline

        public var iconName: String {
            switch self {
            case .affirmative: return "checkmark.circle.fill"
            case .deferral: return "clock.arrow.circlepath"
            case .decline: return "xmark.circle.fill"
            }
        }
    }

    public struct ReplyCandidate: Identifiable, Equatable, Sendable {
        public let id: Int
        public let category: ReplyCategory
        public let text: String
        public let shortcut: String

        public init(id: Int, category: ReplyCategory, text: String) {
            self.id = id
            self.category = category
            self.text = text
            self.shortcut = "\(id)"
        }
    }

    /// Derives 3 smart reply pills for a given question or message context.
    public static func generateReplies(for context: String) -> [ReplyCandidate] {
        let isRussian = context.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
        let lower = context.lowercased()

        if isRussian {
            if lower.contains("созвон") || lower.contains("встреч") || lower.contains("время") || lower.contains("когда") || lower.contains("удобно") {
                return [
                    ReplyCandidate(id: 1, category: .affirmative, text: "Да, отлично, договорились!"),
                    ReplyCandidate(id: 2, category: .deferral, text: "Уточню расписание и напишу через пару минут."),
                    ReplyCandidate(id: 3, category: .decline, text: "К сожалению, в это время никак не получится.")
                ]
            } else if lower.contains("посмотр") || lower.contains("провер") || lower.contains("pr") || lower.contains("ревью") || lower.contains("глян") {
                return [
                    ReplyCandidate(id: 1, category: .affirmative, text: "Да, конечно, сейчас посмотрю!"),
                    ReplyCandidate(id: 2, category: .deferral, text: "Чуть позже освобожусь и гляну."),
                    ReplyCandidate(id: 3, category: .decline, text: "Сегодня завал, перекинь, пожалуйста, на кого-то еще.")
                ]
            } else {
                return [
                    ReplyCandidate(id: 1, category: .affirmative, text: "Да, всё супер, договорились!"),
                    ReplyCandidate(id: 2, category: .deferral, text: "Дай мне минут 15, уточню и отвечу."),
                    ReplyCandidate(id: 3, category: .decline, text: "К сожалению, сейчас не смогу.")
                ]
            }
        } else {
            if lower.contains("call") || lower.contains("meet") || lower.contains("time") || lower.contains("when") || lower.contains("available") {
                return [
                    ReplyCandidate(id: 1, category: .affirmative, text: "Sounds great, confirmed!"),
                    ReplyCandidate(id: 2, category: .deferral, text: "Let me check my calendar and get back to you."),
                    ReplyCandidate(id: 3, category: .decline, text: "Unfortunately, I won't be able to make it.")
                ]
            } else if lower.contains("review") || lower.contains("look") || lower.contains("check") || lower.contains("pr") {
                return [
                    ReplyCandidate(id: 1, category: .affirmative, text: "Sure, taking a look right now!"),
                    ReplyCandidate(id: 2, category: .deferral, text: "Will look into this shortly."),
                    ReplyCandidate(id: 3, category: .decline, text: "Swamped today, could someone else cover?")
                ]
            } else {
                return [
                    ReplyCandidate(id: 1, category: .affirmative, text: "Sounds good, confirmed!"),
                    ReplyCandidate(id: 2, category: .deferral, text: "Let me check and get back to you shortly."),
                    ReplyCandidate(id: 3, category: .decline, text: "Unfortunately, I won't be able to do this.")
                ]
            }
        }
    }
}
