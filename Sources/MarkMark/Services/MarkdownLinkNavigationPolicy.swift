import Foundation
import MarkdownReaderKit

/// Product policy for local Markdown link navigation.
///
/// `WebViewMarkdownView` only reports local `mr:///...` clicks. This policy
/// decides whether that local target can become an in-window MarkMark
/// navigation, and which directory tree root should be shown.
enum MarkdownLinkNavigationPolicy {
    enum TargetKind: Equatable {
        case markdownFile
        case directory
        case unsupportedFile
        case missing
    }

    struct Decision: Equatable {
        let targetURL: URL
        let targetKind: TargetKind
        let rootURL: URL?
        let requiresConfirmation: Bool

        var canNavigate: Bool {
            targetKind == .markdownFile || targetKind == .directory
        }
    }

    /// Only MarkMark's internal `mr:///absolute/path` URLs are eligible for
    /// in-window navigation. `file:///...`, absolute Markdown hrefs, and web
    /// URLs deliberately return nil so they do not silently change workspace.
    static func internalTargetURL(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == "mr",
              url.host?.isEmpty != false,
              !url.path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: url.path).markMarkCanonicalFileURL
    }

    static func decide(
        sourceFileURL: URL?,
        currentRootURL: URL?,
        targetURL: URL,
        fileManager: FileManager = .default
    ) -> Decision {
        let canonicalTarget = targetURL.markMarkCanonicalFileURL
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: canonicalTarget.path, isDirectory: &isDirectory) else {
            return Decision(
                targetURL: canonicalTarget,
                targetKind: .missing,
                rootURL: nil,
                requiresConfirmation: false
            )
        }

        let targetKind: TargetKind = {
            if isDirectory.boolValue {
                return .directory
            }
            return FileService.isKnownMarkdownExtension(canonicalTarget) ? .markdownFile : .unsupportedFile
        }()

        guard targetKind == .markdownFile || targetKind == .directory else {
            return Decision(
                targetURL: canonicalTarget,
                targetKind: targetKind,
                rootURL: nil,
                requiresConfirmation: false
            )
        }

        let targetDirectory = isDirectory.boolValue
            ? canonicalTarget
            : canonicalTarget.deletingLastPathComponent()

        if let currentRootURL {
            let root = currentRootURL.markMarkCanonicalFileURL
            if contains(canonicalTarget, inOrEqualTo: root) {
                return Decision(
                    targetURL: canonicalTarget,
                    targetKind: targetKind,
                    rootURL: root,
                    requiresConfirmation: false
                )
            }

            let sourceDirectory = sourceFileURL?.markMarkCanonicalFileURL.deletingLastPathComponent() ?? root
            return Decision(
                targetURL: canonicalTarget,
                targetKind: targetKind,
                rootURL: nearestCommonDirectory(sourceDirectory, targetDirectory),
                requiresConfirmation: true
            )
        }

        let sourceDirectory = sourceFileURL?.markMarkCanonicalFileURL.deletingLastPathComponent() ?? targetDirectory
        return Decision(
            targetURL: canonicalTarget,
            targetKind: targetKind,
            rootURL: nearestCommonDirectory(sourceDirectory, targetDirectory),
            requiresConfirmation: false
        )
    }

    static func contains(_ child: URL, inOrEqualTo root: URL) -> Bool {
        let childComponents = child.markMarkCanonicalFileURL.pathComponents
        let rootComponents = root.markMarkCanonicalFileURL.pathComponents
        guard rootComponents.count <= childComponents.count else { return false }
        return zip(rootComponents, childComponents).allSatisfy { $0 == $1 }
    }

    static func nearestCommonDirectory(_ lhs: URL, _ rhs: URL) -> URL {
        let lhsComponents = lhs.markMarkCanonicalFileURL.pathComponents
        let rhsComponents = rhs.markMarkCanonicalFileURL.pathComponents
        let commonComponents = zip(lhsComponents, rhsComponents)
            .prefix { $0 == $1 }
            .map(\.0)

        guard !commonComponents.isEmpty else {
            return URL(fileURLWithPath: "/", isDirectory: true)
        }

        let path: String
        if commonComponents == ["/"] {
            path = "/"
        } else if commonComponents.first == "/" {
            path = "/" + commonComponents.dropFirst().joined(separator: "/")
        } else {
            path = commonComponents.joined(separator: "/")
        }

        return URL(fileURLWithPath: path, isDirectory: true).markMarkCanonicalFileURL
    }
}
