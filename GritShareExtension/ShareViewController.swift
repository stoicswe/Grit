import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point.
///
/// When the user taps **Share → Grit** from Safari (or any app that shares a URL),
/// this view controller silently extracts the URL, converts it to a `grit://`
/// deep link, and opens the main Grit app — all without showing any UI.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await extractAndForward() }
    }

    // MARK: - URL extraction and forwarding

    private func extractAndForward() async {
        guard
            let item     = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first
        else { complete(); return }

        let url = await loadURL(from: provider)

        guard let url else { complete(); return }

        // Convert  https://host/path  →  grit://host/path
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "https" || components.scheme == "http"
        else { complete(); return }

        components.scheme = "grit"

        guard let gritURL = components.url else { complete(); return }

        await MainActor.run {
            extensionContext?.open(gritURL, completionHandler: { [weak self] _ in
                self?.complete()
            })
        }
    }

    // MARK: - NSItemProvider helpers

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        let urlType  = UTType.url.identifier
        let textType = UTType.plainText.identifier

        if provider.hasItemConformingToTypeIdentifier(urlType),
           let item = try? await provider.loadItem(forTypeIdentifier: urlType) {
            if let url = item as? URL { return url }
            if let str = item as? String { return URL(string: str) }
        }

        if provider.hasItemConformingToTypeIdentifier(textType),
           let item = try? await provider.loadItem(forTypeIdentifier: textType),
           let str  = item as? String {
            return URL(string: str)
        }

        return nil
    }

    // MARK: - Completion

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
