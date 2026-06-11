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
    /// Text streamed token-by-token for the current turn, so the UI can render
    /// the reply as it's written instead of waiting for the full message.
    var streamingText = ""

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
        streamingText = ""
        defer {
            isThinking = false
            streamingText = ""
        }

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

    /// Streams one API turn over SSE. Text deltas are appended to `streamingText`
    /// for live display, while the full content blocks (thinking, text, tool_use)
    /// are reconstructed verbatim so the tool loop can echo them back exactly.
    @MainActor
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
            "stream": true,
            "thinking": ["type": "adaptive"],
            "system": systemPrompt(),
            "tools": AssistantTools.definitions,
            "messages": conversation,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AssistantError.badResponse("No HTTP response.")
        }
        guard http.statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let json = (try? JSONSerialization.jsonObject(with: errorData)) as? [String: Any]
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw AssistantError.badResponse(message)
        }

        var blocks: [[String: Any]] = []
        var partialToolInputJSON: [Int: String] = [:]
        var stopReason = "end_turn"

        for try await line in bytes.lines {
            guard line.hasPrefix("data: "),
                  let data = line.dropFirst(6).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                guard let index = event["index"] as? Int,
                      var block = event["content_block"] as? [String: Any] else { continue }
                if (block["type"] as? String) == "tool_use" { block["input"] = [String: Any]() }
                while blocks.count <= index { blocks.append([:]) }
                blocks[index] = block

            case "content_block_delta":
                guard let index = event["index"] as? Int, index < blocks.count,
                      let delta = event["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String else { continue }
                switch deltaType {
                case "text_delta":
                    let text = delta["text"] as? String ?? ""
                    blocks[index]["text"] = (blocks[index]["text"] as? String ?? "") + text
                    streamingText += text
                case "thinking_delta":
                    blocks[index]["thinking"] = (blocks[index]["thinking"] as? String ?? "")
                        + (delta["thinking"] as? String ?? "")
                case "signature_delta":
                    blocks[index]["signature"] = (blocks[index]["signature"] as? String ?? "")
                        + (delta["signature"] as? String ?? "")
                case "input_json_delta":
                    partialToolInputJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
                default:
                    break
                }

            case "content_block_stop":
                guard let index = event["index"] as? Int, index < blocks.count else { continue }
                if let jsonString = partialToolInputJSON[index], !jsonString.isEmpty,
                   let jsonData = jsonString.data(using: .utf8),
                   let input = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    blocks[index]["input"] = input
                }

            case "message_delta":
                if let delta = event["delta"] as? [String: Any],
                   let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }

            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String ?? "stream error"
                throw AssistantError.badResponse(message)

            default:
                break // message_start, message_stop, ping
            }
        }

        // Between tool rounds, keep streamed narration visible with a separator.
        if !streamingText.isEmpty { streamingText += "\n" }

        return ["content": blocks, "stop_reason": stopReason]
    }
}
