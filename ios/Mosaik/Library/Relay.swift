// Relæet (samme som Noter+/Lommeregneren): GET /r/:rum, POST /r/:rum, GET /r/:rum/events (Server-Sent Events).
import Foundation

final class RelayClient {
    static let base = "https://relay-production-03f5.up.railway.app"

    let room: String
    private let onState: @MainActor ([String: Any]) -> Void
    private let onStatus: @MainActor (String) -> Void
    private var task: Task<Void, Never>?

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 45      // serveren pinger hvert 15. sek.
        c.timeoutIntervalForResource = 24 * 3600
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    static func clean(_ s: String) -> String {
        String(s.lowercased().filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }.prefix(40))
    }

    init(room: String, onState: @escaping @MainActor ([String: Any]) -> Void, onStatus: @escaping @MainActor (String) -> Void) {
        self.room = Self.clean(room)
        self.onState = onState
        self.onStatus = onStatus
    }

    func start() {
        stop()
        guard room.count >= 3, let url = URL(string: "\(Self.base)/r/\(room)/events") else {
            let off = onStatus
            Task { @MainActor in off("off") }
            return
        }
        task = Task { [session, onState, onStatus] in
            while !Task.isCancelled {
                await onStatus("connecting")
                do {
                    var req = URLRequest(url: url)
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, resp) = try await session.bytes(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    await onStatus("online")
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if let d = json.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                           let st = obj["state"] as? [String: Any] {
                            await onState(st)
                        }
                    }
                } catch {}
                if Task.isCancelled { break }
                await onStatus("offline")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Skriv felter til rummet (bruges til "Test"-knappen i panelet)
    func publish(_ patch: [String: Any]) async {
        guard room.count >= 3, let url = URL(string: "\(Self.base)/r/\(room)"),
              let body = try? JSONSerialization.data(withJSONObject: patch) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        _ = try? await session.data(for: req)
    }
}
