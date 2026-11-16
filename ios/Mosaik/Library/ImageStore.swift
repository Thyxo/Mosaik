// Billeder til gitteret og fremviseren. src >= 0 = puljen, src < 0 = ægte foto nr. -src-1.
import Photos
import UIKit

final class ImageBox { let image: CGImage; init(_ i: CGImage) { image = i } }

final class ImageStore {
    static let shared = ImageStore()

    static let smallPx = 72
    static let bigPx = 300

    private var smallPool: [CGImage?] = []
    private let lock = NSLock()
    private let bigCache = NSCache<NSNumber, ImageBox>()
    private let realSmall = NSCache<NSNumber, ImageBox>()
    private let queue = DispatchQueue(label: "mosaik.images", qos: .userInitiated, attributes: .concurrent)
    private var waiting: [String: [(CGImage?) -> Void]] = [:]

    let fullSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 400 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    private init() {
        bigCache.countLimit = 260
        realSmall.countLimit = 400
    }

    /// Afkod alle små puljebilleder i baggrunden (ca. 15 MB i hukommelsen).
    func preloadSmall() {
        let pool = Pool.shared
        lock.lock(); if smallPool.count != pool.count { smallPool = Array(repeating: nil, count: pool.count) }; lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            DispatchQueue.concurrentPerform(iterations: pool.count) { i in
                if self.small(Int32(i)) != nil { return }
                let img = Self.downsample(url: pool.url(i), px: Self.smallPx)
                self.lock.lock(); self.smallPool[i] = img; self.lock.unlock()
            }
        }
    }

    func small(_ src: Int32) -> CGImage? {
        if src >= 0 {
            lock.lock(); defer { lock.unlock() }
            let i = Int(src)
            return i < smallPool.count ? smallPool[i] : nil
        }
        return realSmall.object(forKey: NSNumber(value: src))?.image
    }

    func big(_ src: Int32) -> CGImage? { bigCache.object(forKey: NSNumber(value: src))?.image }

    /// Hent billedet asynkront; `done` kaldes på hovedtråden.
    func load(_ src: Int32, big: Bool, _ done: @escaping (CGImage?) -> Void) {
        let key = "\(src)-\(big)"
        lock.lock()
        if waiting[key] != nil { waiting[key]!.append(done); lock.unlock(); return }
        waiting[key] = [done]
        lock.unlock()
        let finish: (CGImage?) -> Void = { img in
            DispatchQueue.main.async {
                self.lock.lock(); let cbs = self.waiting.removeValue(forKey: key) ?? []; self.lock.unlock()
                for cb in cbs { cb(img) }
            }
        }
        if src >= 0 {
            queue.async {
                let img = Self.downsample(url: Pool.shared.url(Int(src)), px: big ? Self.bigPx : Self.smallPx)
                if let img {
                    if big { self.bigCache.setObject(ImageBox(img), forKey: NSNumber(value: src)) }
                    else { self.lock.lock(); if Int(src) < self.smallPool.count { self.smallPool[Int(src)] = img }; self.lock.unlock() }
                }
                finish(img)
            }
        } else {
            let k = Int(-src - 1)
            let real = RealPhotos.shared
            guard k < real.assets.count else { finish(nil); return }
            Task {
                let px = CGFloat(big ? 400 : 120)
                let img = await real.image(real.assets[k], px: px, quality: big)
                if let img { (big ? self.bigCache : self.realSmall).setObject(ImageBox(img), forKey: NSNumber(value: src)) }
                finish(img)
            }
        }
    }

    /// Billedformat (bredde/højde) til fremviseren
    func aspect(_ src: Int32) -> CGFloat {
        if src >= 0 { return Pool.shared.aspect(Int(src)) }
        let k = Int(-src - 1)
        guard k < RealPhotos.shared.assets.count else { return 1 }
        let a = RealPhotos.shared.assets[k]
        return a.pixelHeight > 0 ? CGFloat(a.pixelWidth) / CGFloat(a.pixelHeight) : 1
    }

    /// Fuldt billede til fremviseren. Puljen hentes fra Picsum (caches på disken).
    func full(_ src: Int32, screenPx: CGFloat) async -> CGImage? {
        if src >= 0 {
            let i = Int(src)
            let a = Pool.shared.aspect(i)
            let w = 1080, h = max(200, Int((1080 / a).rounded()))
            guard let url = URL(string: "https://picsum.photos/id/\(Pool.shared.picsumID(i))/\(w)/\(h)") else { return nil }
            guard let (d, r) = try? await fullSession.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return Self.downsample(data: d, px: 1600)
        }
        let k = Int(-src - 1)
        guard k < RealPhotos.shared.assets.count else { return nil }
        return await RealPhotos.shared.image(RealPhotos.shared.assets[k], px: screenPx, quality: true, fit: true)
    }

    static func downsample(url: URL, px: Int) -> CGImage? {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumb(s, px)
    }

    static func downsample(data: Data, px: Int) -> CGImage? {
        guard let s = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumb(s, px)
    }

    private static func thumb(_ s: CGImageSource, _ px: Int) -> CGImage? {
        let o: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: px,
        ]
        return CGImageSourceCreateThumbnailAtIndex(s, 0, o as CFDictionary)
    }
}
