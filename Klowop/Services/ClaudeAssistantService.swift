import Foundation
import SwiftData
import Observation

/// Talks to the Claude Messages API (https://api.anthropic.com/v1/messages) with tool use,
/// so the assistant can read and write the user's agenda, todos, meals, and finances.
///
/// The conversation is kept as raw JSON message dictionaries and assistant responses are
/// echoed back verbatim — this preserves thinking and tool_use blocks exactly as the API
/// requires for multi-turn tool loops.
@Observable
final class ClaudeAssistantService {
    static let shared = ClaudeAssistantService()

    var isThinking = false

    private let model = "claude-opus-4-8"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private var conversation: [[String: Any]] = []
    private let maxToolRounds = 12

    enum AssistantError: LocalizedError {
        case missingAPIKey
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add your Anthropic API key in Settings to talk to the assistant."
            case .badResponse(let message):
                return message
            }
        }
    }

    func resetConversation() {
        conversation = []
    }

    @MainActor
    func send(_ userText: String, context: ModelContext) async throws -> String {
        guard !AppSettings.shared.anthropicAPIKey.isEmpty else {
            throw AssistantError.missingAPIKey
        }
        isThinking = true
        defer { isThinking = false }

        conversation.append(["role": "user", "content": userText])

        var rounds = 0
        while true {
            let response = try await requestMessage()
            let content = response["content"] as? [[String: Any]] ?? []
            let stopReason = response["stop_reason"] as? String ?? "end_turn"

            // Echo the assistant turn back verbatim (preserves thinking/tool_use blocks).
            conversation.append(["role": "assistant", "content": content])

            switch stopReason {
            case "tool_use":
                rounds += 1
                guard rounds <= maxToolRounds else {
                    return textBlocks(in: content) + "\n(Stopped after too many tool calls.)"
                }
                var results: [[String: Any]] = []
                for block in content where (block["type"] as? String) == "tool_use" {
                    let toolName = block["name"] as? String ?? ""
                    let toolInput = block["input"] as? [String: Any] ?? [:]
                    let toolID = block["id"] as? String ?? ""
                    let result = await AssistantTools.execute(name: toolName, input: toolInput, context: context)
                    results.append([
                        "type": "tool_result",
                        "tool_use_id": toolID,
                        "content": result,
                    ])
                }
                conversation.append(["role": "user", "content": results])

            case "pause_turn":
                // Server paused a long turn; re-send to let it resume.
                continue

            case "refusal":
                return "I can't help with that request."

            default:
                return textBlocks(in: content)
            }
        }
    }

    private func textBlocks(in content: [[String: Any]]) -> String {
        content.compactMap { block in
            (block["type"] as? String) == "text" ? block["text"] as? String : nil
        }.joined(separator: "\n")
    }

    private func systemPrompt() -> String {
        let now = ISO8601DateFormatter().string(from: .now)
        let name = AppSettings.shared.userName
        return """
        You are Klowop, \(name.isEmpty ? "the user" : name)'s personal secretary inside their life-management iPhone app. \
        You manage their agenda, to-do lists, food log, and finances through the tools provided. \
        Be warm, brief, and proactive — like a great human assistant. \
        When the user mentions plans, food, or purchases in passing, offer to log or schedule them. \
        Always use tools to read or change data instead of guessing. \
        When creating events or todos from vague times ("tomorrow afternoon"), pick a sensible concrete time and mention it. \
        The current date and time is \(now) (the user's local timezone). \
        Use ISO 8601 date-times with the timezone offset from the current time when calling tools.
        """
    }

    private func requestMessage() async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppSettings.shared.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "system": systemPrompt(),
            "tools": AssistantTools.definitions,
            "messages": conversation,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AssistantError.badResponse("No HTTP response.")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AssistantError.badResponse("Could not decode API response.")
        }
        guard http.statusCode == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw AssistantError.badResponse(message)
        }
        return json
    }
}
