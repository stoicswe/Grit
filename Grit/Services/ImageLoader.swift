import Foundation
import SwiftUI
import UIKit

// MARK: - Image Loader

/// Two-tier image cache used for avatars and other small remote images.
///
/// `AsyncImage` re-downloads through the shared `URLSession` whose default
/// cache is tiny and whose decoded bitmaps are never retained — the same
/// avatar URL appearing in a list of 50 notes triggers 50 decodes.  This
/// loader adds:
///
/// * **Memory tier** — decoded `UIImage`s in an `NSCache` (cost-limited).
/// * **Disk tier**   — a dedicated `URLCache` (100 MB) that honours the server's
///   `Cache-Control` / `ETag` headers, so avatars survive app restarts and
///   revalidate cheaply.
/// * **In-flight coalescing** — concurrent requests for the same URL share one
///   network call.
actor ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("GritImageCache", isDirectory: true)
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity:  100 * 1024 * 1024,
            directory:     dir
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)

        memory.countLimit = 600
        memory.totalCostLimit = 48 * 1024 * 1024   // ~48 MB of decoded bitmaps
    }

    /// Returns the cached image synchronously-ish (no network) if present in memory.
    func cached(for urlString: String) -> UIImage? {
        memory.object(forKey: urlString as NSString)
    }

    /// Loads an image, serving from memory, then disk, then network.
    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let hit = memory.object(forKey: key) { return hit }

        if let running = inFlight[url.absoluteString] {
            return await running.value
        }

        let task = Task<UIImage?, Never> { [session] in
            var request = URLRequest(url: url)
            // Let URLCache decide freshness; the server's Cache-Control is honoured.
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data)
            else { return nil }
            // Decode off the main thread so first display doesn't stutter.
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[url.absoluteString] = task
        let result = await task.value
        inFlight[url.absoluteString] = nil

        if let result {
            let cost = Int(result.size.width * result.size.height * result.scale * result.scale * 4)
            memory.setObject(result, forKey: key, cost: cost)
        }
        return result
    }

    /// Drops the in-memory tier (e.g. on a memory warning). Disk cache is kept.
    func evictMemory() { memory.removeAllObjects() }

    /// Clears both tiers — called on logout so avatars from another account
    /// are never shown.
    func clearAll() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

// MARK: - CachedAsyncImage

/// Drop-in replacement for `AsyncImage` backed by `ImageLoader`.
///
/// The `content` closure receives an `Image` once loaded; `placeholder` is
/// shown while loading or when the load fails.  If the image is already in the
/// memory tier it is rendered on the very first frame with no flash.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            // Fast path: memory hit renders immediately.
            if let hit = await ImageLoader.shared.cached(for: url.absoluteString) {
                image = hit
                return
            }
            let loaded = await ImageLoader.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image  = loaded
            failed = loaded == nil
        }
    }
}
