import Foundation
import OSLog

/// An actor responsible for calling OpenAI's Whisper and GPT endpoints.
actor OpenAIService {
    static let shared = OpenAIService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "OpenAIService", category: "OpenAI")
    private let session: URLSession
    
    private init() {
        // Configure URLSession with longer timeout for transcription
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = OpenAIConfig.Config.timeout
        config.timeoutIntervalForResource = OpenAIConfig.Config.timeout
        self.session = URLSession(configuration: config)
        
        logger.debug("OpenAIService initialized")
    }

    /// Transcribe the given audio file using Whisper
    /// - Parameter url: Local URL to an audio file (e.g. .mp3)
    /// - Returns: The text transcription
    func transcribeAudio(url: URL) async throws -> String {
        logger.debug("transcribeAudio called for file: \(url.path)")

        // Check file size
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
        guard fileSize <= OpenAIConfig.Config.maxTranscriptionSize else {
            logger.error("File too large: \(fileSize) bytes")
            throw NSError(domain: "OpenAIService", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Audio file too large (max 25MB)"])
        }

        // 1) Prepare request
        let boundary = "Boundary-\(UUID().uuidString)"
        let transcribeURL = URL(string: OpenAIConfig.baseURL + OpenAIConfig.Endpoint.transcription)!

        var request = URLRequest(url: transcribeURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(OpenAIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // 2) Build form data
        var body = Data()
        
        // "file" param
        let fileData = try Data(contentsOf: url)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp3\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // "model" param
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(OpenAIConfig.Model.whisper)\r\n".data(using: .utf8)!)

        // "response_format" param
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // 3) Execute request
        let (data, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse,
              (200...299).contains(httpResp.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "Unknown"
            logger.error("Failed transcription - Status: \((response as? HTTPURLResponse)?.statusCode ?? -1). Body=\(bodyStr)")
            throw NSError(domain: "OpenAIService", code: -2, 
                         userInfo: [NSLocalizedDescriptionKey: "Transcription error: \(bodyStr)"])
        }

        let transcriptText = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        logger.debug("transcribeAudio success, length=\(transcriptText.count)")

        return transcriptText
    }

    /// Analyze transcript with GPT to get title, description, tags, quotes
    func analyzeContent(transcript: String) async throws -> (title: String, description: String, tags: [String], quotes: [String]) {
        logger.debug("analyzeContent called, transcript length=\(transcript.count)")

        // Step 1) Extract short quotes
        let extractQuotesPrompt = """
Extract 2-3 insightful quotes from the following transcript, each on a new line starting with a dash. Keep them short:
\(transcript)
"""
        let quotes = try await gptCall(prompt: extractQuotesPrompt, temperature: 0.5, maxTokens: 150)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("-") }
            .map { $0.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }

        // Step 2) Title, description, tags
        // Title
        let titlePrompt = """
Based on the following transcript, generate a catchy title (max 60 characters):
\(transcript)
"""
        let autoTitle = try await gptCall(prompt: titlePrompt, temperature: 0.7, maxTokens: 60)

        // Description
        let descPrompt = """
Based on the transcript, generate a concise video description (max 200 characters):
\(transcript)
"""
        let autoDescription = try await gptCall(prompt: descPrompt, temperature: 0.7, maxTokens: 200)

        // 20 tags
        let tagsPrompt = """
Read this transcript and produce 20 relevant category tags (comma-separated) that best capture the main topics:
\(transcript)
"""
        let tagsResponse = try await gptCall(prompt: tagsPrompt, temperature: 0.7, maxTokens: 200)
        let tagList = tagsResponse
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (title: autoTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                description: autoDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: tagList,
                quotes: quotes)
    }

    /// Internal method for sending prompt to chat/completions
    private func gptCall(prompt: String, temperature: Double, maxTokens: Int) async throws -> String {
        logger.debug("gptCall => prompt length=\(prompt.count), temperature=\(temperature), maxTokens=\(maxTokens)")

        var request = URLRequest(url: URL(string: OpenAIConfig.baseURL + OpenAIConfig.Endpoint.chat)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(OpenAIConfig.apiKey)", forHTTPHeaderField: "Authorization")

        let bodyDict: [String: Any] = [
            "model": OpenAIConfig.Model.gpt4,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict, options: [])

        let (data, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse,
              (200...299).contains(httpResp.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "Unknown"
            logger.error("GPT call failed. Status: \( (response as? HTTPURLResponse)?.statusCode ?? -1). Body=\(bodyStr)")
            throw NSError(domain: "OpenAIService", code: -4, 
                         userInfo: [NSLocalizedDescriptionKey: "GPT call failed: \(bodyStr)"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            logger.error("Failed to parse GPT reply.")
            throw NSError(domain: "OpenAIService", code: -5, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse GPT response"])
        }

        logger.debug("GPT reply length=\(content.count)")
        return content
    }
} 