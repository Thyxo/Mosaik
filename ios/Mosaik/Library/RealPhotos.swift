// De nyeste ægte fotos fra kamerarullen (PhotoKit). De ligger nederst i biblioteket.
import Photos
import UIKit

final class RealPhotos {
    static let shared = RealPhotos()

    private(set) var assets: [PHAsset] = []          // nyeste først
    private(set) var rgb: [SIMD3<Float>] = []
    let manager = PHCachingImageManager()

    var authorized: Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .authorized || s == .limited
    }

    func requestAccess() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited
    }

    /// Henter de `count` nyeste fotos og deres gennemsnitsfarver.
    func load(count: Int) async {
        guard count > 0, authorized else { assets = []; rgb = []; return }
        let opt = PHFetchOptions()
        opt.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opt.fetchLimit = count
        let res = PHAsset.fetchAssets(with: .image, options: opt)
        var list: [PHAsset] = []
        res.enumerateObjects { a, _, _ in list.append(a) }
        var colors: [SIMD3<Float>] = []
        for a in list {
            let img = await image(a, px: 24, quality: false)
            colors.append(img.map(Self.average) ?? SIMD3(0.5, 0.5, 0.5))
        }
        assets = list
        rgb = colors
    }

    func image(_ asset: PHAsset, px: CGFloat, quality: Bool, fit: Bool = false) async -> CGImage? {
        await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.deliveryMode = quality ? .highQualityFormat : .fastFormat
            o.resizeMode = .fast
            o.isNetworkAccessAllowed = true
            o.isSynchronous = false
            var done = false
            manager.requestImage(for: asset, targetSize: CGSize(width: px, height: px),
                                 contentMode: fit ? .aspectFit : .aspectFill, options: o) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if done || (degraded && quality) { return }
                done = true
                cont.resume(returning: img.flatMap(Self.upright))
            }
        }
    }

    /// CGImage der vender rigtigt (UIImage kan have en orientering)
    static func upright(_ img: UIImage) -> CGImage? {
        if img.imageOrientation == .up, let cg = img.cgImage { return cg }
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        return UIGraphicsImageRenderer(size: img.size, format: f).image { _ in img.draw(at: .zero) }.cgImage
    }

    static func average(_ cg: CGImage) -> SIMD3<Float> {
        var px = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return SIMD3(0.5, 0.5, 0.5) }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return SIMD3(Float(px[0]) / 255, Float(px[1]) / 255, Float(px[2]) / 255)
    }
}
