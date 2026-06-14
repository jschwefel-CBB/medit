import Foundation

/// Maps a filename or URL to the highlight.js language identifier that
/// HighlighterSwift expects in `highlight(_:as:)`. Pure value logic — testable
/// without AppKit. Identifiers are the canonical highlight.js names (e.g.
/// `javascript`, `cpp`, `objectivec`, `xml` for HTML).
public enum LanguageMap {

    /// Filenames (lowercased) that imply a language regardless of extension.
    private static let specialFilenames: [String: String] = [
        "makefile": "makefile",
        "dockerfile": "dockerfile",
        "gnumakefile": "makefile"
    ]

    /// File extension (lowercased, no dot) → highlight.js identifier.
    private static let extensionMap: [String: String] = [
        "swift": "swift",
        "py": "python", "pyw": "python",
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
        "ts": "typescript", "tsx": "typescript",
        "json": "json", "jsonc": "json",
        "yaml": "yaml", "yml": "yaml",
        "md": "markdown", "markdown": "markdown",
        "sh": "bash", "bash": "bash", "zsh": "bash",
        "c": "c", "h": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp", "hxx": "cpp",
        "m": "objectivec", "mm": "objectivec",
        "go": "go",
        "rs": "rust",
        "rb": "ruby",
        "java": "java",
        "kt": "kotlin", "kts": "kotlin",
        "html": "xml", "htm": "xml", "xhtml": "xml", "xml": "xml", "plist": "xml", "svg": "xml",
        "css": "css",
        "scss": "scss",
        "php": "php",
        "sql": "sql",
        "pl": "perl", "pm": "perl",
        "lua": "lua",
        "toml": "toml",
        "ini": "ini", "cfg": "ini", "conf": "ini",
        "mk": "makefile", "mak": "makefile",
        "diff": "diff", "patch": "diff"
    ]

    /// Resolve a highlight.js identifier from a bare filename or full path.
    /// Returns `nil` when the language can't be determined.
    public static func language(forFilename filename: String) -> String? {
        let last = (filename as NSString).lastPathComponent
        guard !last.isEmpty else { return nil }

        let lowerName = last.lowercased()

        // Exact special-filename match (Makefile, Dockerfile).
        if let special = specialFilenames[lowerName] {
            return special
        }
        // Prefix special-filename match (Dockerfile.dev, Makefile.inc).
        for (name, lang) in specialFilenames where lowerName.hasPrefix(name + ".") {
            return lang
        }

        let ext = (lowerName as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return extensionMap[ext]
    }

    /// Convenience overload for a file URL.
    public static func language(forURL url: URL) -> String? {
        language(forFilename: url.lastPathComponent)
    }
}
