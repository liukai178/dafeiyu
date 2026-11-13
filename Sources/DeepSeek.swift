import Foundation

struct DeepSeekError: Error, LocalizedError {
    let message: String
    var status: Int = 0
    var isAuth: Bool { status == 401 || status == 403 }

    var errorDescription: String? { message }
}

final class DeepSeekClient {
    private let baseURL: String
    private let apiKey: String
    private let model: String
    private var currentTask: Task<Void, Never>?
    private var cancelled = false

    init(apiKey: String, baseURL: String, model: String) {
        self.apiKey = apiKey
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        self.baseURL = base.isEmpty ? "https://api.deepseek.com" : base
        self.model = model
    }

    func cancel() {
        cancelled = true
        currentTask?.cancel()
    }

    // MARK: - Streaming chat (blocking; call from a background queue)

    func streamChat(messages: [APIMessage],
                    tools: [[String: Any]]?,
                    temperature: Double,
                    onDelta: @escaping (String) -> Void) -> Result<APIMessage, DeepSeekError> {
        guard !apiKey.isEmpty else {
            return .failure(DeepSeekError(message: "还没有配置 DeepSeek API Key。"))
        }
        guard let url = URL(string: baseURL + "/chat/completions") else {
            return .failure(DeepSeekError(message: "API 地址不正确：\(baseURL)"))
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { Self.dict(for: $0) },
            "stream": true,
            "temperature": temperature,
            "max_tokens": 1200
        ]
        if let tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .failure(DeepSeekError(message: "请求编码失败：\(error.localizedDescription)"))
        }

        let sem = DispatchSemaphore(value: 0)
        var output: Result<APIMessage, DeepSeekError> = .failure(DeepSeekError(message: "未知错误"))

        let task = Task { [weak self] in
            defer { sem.signal() }
            guard let self else {
                output = .failure(DeepSeekError(message: "客户端已释放"))
                return
            }
            do {
                output = .success(try await self.performStream(request: request, onDelta: onDelta))
            } catch is CancellationError {
                output = .failure(DeepSeekError(message: "已取消"))
            } catch let error as DeepSeekError {
                output = .failure(error)
            } catch {
                let ns = error as NSError
                if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
                    output = .failure(DeepSeekError(message: "已取消"))
                } else {
                    output = .failure(DeepSeekError(message: Self.friendly(error)))
                }
            }
        }
        currentTask = task
        sem.wait()
        currentTask = nil
        if cancelled {
            return .failure(DeepSeekError(message: "已取消"))
        }
        return output
    }

    private func performStream(request: URLRequest,
                               onDelta: @escaping (String) -> Void) async throws -> APIMessage {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError(message: "没有收到服务器响应。")
        }
        guard http.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 4096 { break }
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            throw DeepSeekError(message: Self.apiErrorMessage(text, status: http.statusCode), status: http.statusCode)
        }

        var content = ""
        var finishReason = ""
        struct Accum {
            var id = ""
            var name = ""
            var arguments = ""
        }
        var accums: [Int: Accum] = [:]

        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard !payload.isEmpty,
                  let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "服务端返回了错误"
                throw DeepSeekError(message: message, status: http.statusCode)
            }
            guard let choices = object["choices"] as? [[String: Any]],
                  let first = choices.first else { continue }
            if let reason = first["finish_reason"] as? String, !reason.isEmpty {
                finishReason = reason
            }
            guard let delta = first["delta"] as? [String: Any] else { continue }

            if let chunk = delta["content"] as? String, !chunk.isEmpty {
                content += chunk
                onDelta(chunk)
            }
            if let calls = delta["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    let index = call["index"] as? Int ?? 0
                    var accum = accums[index] ?? Accum()
                    if let id = call["id"] as? String, !id.isEmpty { accum.id = id }
                    if let fn = call["function"] as? [String: Any] {
                        if let name = fn["name"] as? String, !name.isEmpty { accum.name += name }
                        if let args = fn["arguments"] as? String { accum.arguments += args }
                    }
                    accums[index] = accum
                }
            }
        }

        let toolCalls: [APIToolCall] = accums.keys.sorted().compactMap { key in
            guard let accum = accums[key], !accum.name.isEmpty else { return nil }
            return APIToolCall(
                id: accum.id.isEmpty ? "call_\(UUID().uuidString.prefix(8))" : accum.id,
                type: "function",
                function: APIFunctionCall(name: accum.name, arguments: accum.arguments.isEmpty ? "{}" : accum.arguments)
            )
        }

        _ = finishReason
        if content.isEmpty && toolCalls.isEmpty {
            throw DeepSeekError(message: "肥鱼这次没憋出话，再试一次？")
        }
        return APIMessage(assistantMessage: content.isEmpty ? nil : content, toolCalls: toolCalls)
    }

    private static func dict(for message: APIMessage) -> [String: Any] {
        var d: [String: Any] = ["role": message.role]
        if let content = message.content {
            d["content"] = content
        } else if message.tool_calls != nil {
            d["content"] = NSNull()
        } else {
            d["content"] = ""
        }
        if let calls = message.tool_calls {
            d["tool_calls"] = calls.map { call -> [String: Any] in
                [
                    "id": call.id,
                    "type": call.type,
                    "function": ["name": call.function.name, "arguments": call.function.arguments]
                ]
            }
        }
        if let id = message.tool_call_id { d["tool_call_id"] = id }
        return d
    }

    // MARK: - Non-streaming completion (memory extraction etc.)

    func complete(messages: [APIMessage], temperature: Double = 0.2, maxTokens: Int = 400) -> Result<String, DeepSeekError> {
        guard !apiKey.isEmpty else {
            return .failure(DeepSeekError(message: "还没有配置 DeepSeek API Key。"))
        }
        guard let url = URL(string: baseURL + "/chat/completions") else {
            return .failure(DeepSeekError(message: "API 地址不正确"))
        }
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { Self.dict(for: $0) },
            "stream": false,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let sem = DispatchSemaphore(value: 0)
        var output: Result<String, DeepSeekError> = .failure(DeepSeekError(message: "未知错误"))
        let task = Task {
            defer { sem.signal() }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                guard http?.statusCode == 200 else {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    output = .failure(DeepSeekError(
                        message: Self.apiErrorMessage(text, status: http?.statusCode ?? 0),
                        status: http?.statusCode ?? 0
                    ))
                    return
                }
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = object["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    output = .failure(DeepSeekError(message: "返回格式不对"))
                    return
                }
                output = .success(content)
            } catch {
                output = .failure(DeepSeekError(message: Self.friendly(error)))
            }
        }
        sem.wait()
        task.cancel()
        return output
    }

    // MARK: - Simple connection test

    func testConnection() -> Result<String, DeepSeekError> {
        guard !apiKey.isEmpty else {
            return .failure(DeepSeekError(message: "还没有配置 API Key"))
        }
        guard let url = URL(string: baseURL + "/models") else {
            return .failure(DeepSeekError(message: "API 地址不正确"))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let sem = DispatchSemaphore(value: 0)
        var output: Result<String, DeepSeekError> = .failure(DeepSeekError(message: "未知错误"))
        let task = Task {
            defer { sem.signal() }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                if http?.statusCode == 200 {
                    output = .success("连接成功")
                } else {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    output = .failure(DeepSeekError(
                        message: Self.apiErrorMessage(text, status: http?.statusCode ?? 0),
                        status: http?.statusCode ?? 0
                    ))
                }
            } catch {
                output = .failure(DeepSeekError(message: Self.friendly(error)))
            }
        }
        sem.wait()
        task.cancel()
        return output
    }

    private static func apiErrorMessage(_ text: String, status: Int) -> String {
        if let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return status == 401 ? "API Key 无效或已过期。" : message
        }
        switch status {
        case 401, 403: return "API Key 无效或没有权限。"
        case 402: return "账户余额不足。"
        case 429: return "请求太快了，缓一下再试。"
        case 500...599: return "DeepSeek 服务暂时不可用（\(status)）。"
        default: return "请求失败（HTTP \(status)）"
        }
    }

    private static func friendly(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorNotConnectedToInternet: return "网络断了，检查一下 WiFi？"
        case NSURLErrorTimedOut: return "等太久了，DeepSeek 没回应。"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "连不上 DeepSeek，检查网络或 API 地址。"
        default: return ns.localizedDescription
        }
    }
}
