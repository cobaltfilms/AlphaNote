import UIKit
import UniformTypeIdentifiers

/// « Partager › AlphaNote » : récupère le texte (ou le lien) partagé, le dépose
/// dans la boîte du groupe d'apps et se ferme aussitôt. L'app en fait une note
/// à sa prochaine activation (SharedInbox.importPending).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await collectAndFinish() }
    }

    private func collectAndFinish() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var parts: [String] = []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty {
                parts.append(text)
            }
            for provider in item.attachments ?? [] {
                if let text = await load(provider) { parts.append(text) }
            }
        }
        // Un lien partagé avec son titre arrive souvent deux fois : on dédoublonne.
        var seen = Set<String>()
        let text = parts.filter { seen.insert($0).inserted }.joined(separator: "\n")
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? SharedInbox.deposit(text)
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func load(_ provider: NSItemProvider) async -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            return url.absoluteString
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            return text
        }
        return nil
    }
}
