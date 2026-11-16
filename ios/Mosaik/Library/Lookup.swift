// Navn/ord -> billede via Wikipedia (dansk først, så engelsk). Bruges når relæet sender et navn.
import UIKit

enum Lookup {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["User-Agent": "Mosaik/1.0 (iOS)", "Api-User-Agent": "Mosaik/1.0 (iOS)"]
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    static func image(for query: String, lang: String) async -> (CGImage, String)? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        var langs = [lang.isEmpty ? "da" : lang]
        if langs[0] != "en" { langs.append("en") }
        for l in langs {
            if let r = await fromSummary(title: q, lang: l) { return r }
            if let t = await search(q, lang: l), let r = await fromSummary(title: t, lang: l) { return r }
        }
        return nil
    }

    static func fromSummary(title: String, lang: String) async -> (CGImage, String)? {
        let t = title.replacingOccurrences(of: " ", with: "_")
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let enc = t.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://\(lang).wikipedia.org/api/rest_v1/page/summary/\(enc)?redirect=true"),
              let (d, r) = try? await session.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if (j["type"] as? String) == "disambiguation" { return nil }
        var candidates: [String] = []
        if let o = j["originalimage"] as? [String: Any], let s = o["source"] as? String {
            let w = (o["width"] as? Int) ?? 0
            let low = s.lowercased()
            if !low.hasSuffix(".svg") && !low.hasSuffix(".tif") && !low.hasSuffix(".tiff") && w < 6000 { candidates.append(s) }
        }
        if let th = j["thumbnail"] as? [String: Any], let s = th["source"] as? String { candidates.append(s) }
        for s in candidates {
            if let u = URL(string: s), let img = await download(u) { return (img, (j["title"] as? String) ?? title) }
        }
        return nil
    }

    static func search(_ q: String, lang: String) async -> String? {
        var c = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php")!
        c.queryItems = [.init(name: "action", value: "query"), .init(name: "list", value: "search"),
                        .init(name: "srsearch", value: q), .init(name: "srlimit", value: "1"), .init(name: "format", value: "json")]
        guard let url = c.url, let (d, _) = try? await session.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let query = j["query"] as? [String: Any], let s = query["search"] as? [[String: Any]],
              let first = s.first?["title"] as? String else { return nil }
        return first
    }

    static func download(_ url: URL) async -> CGImage? {
        guard let (d, r) = try? await session.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ImageStore.downsample(data: d, px: 1400)
    }

    /// "data:image/jpeg;base64,..." eller ren base64
    static func decodeBase64(_ s: String) -> CGImage? {
        let b = s.range(of: "base64,").map { String(s[$0.upperBound...]) } ?? s
        guard let d = Data(base64Encoded: b, options: .ignoreUnknownCharacters) else { return nil }
        return ImageStore.downsample(data: d, px: 1400)
    }
}
