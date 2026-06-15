import Foundation

/// The source of truth for the language picker: a curated common list, the full
/// list, and display-name formatting. Pure value data, fully tested. IDs are the
/// highlight.js identifiers HighlighterSwift expects.
public enum LanguageCatalog {

    public struct Language: Equatable {
        public let id: String
        public let displayName: String
        public init(id: String, displayName: String) {
            self.id = id
            self.displayName = displayName
        }
    }

    /// Curated, commonly-used languages (shown at the top level of the menu).
    public static let common: [Language] = [
        Language(id: "swift", displayName: "Swift"),
        Language(id: "python", displayName: "Python"),
        Language(id: "javascript", displayName: "JavaScript"),
        Language(id: "typescript", displayName: "TypeScript"),
        Language(id: "json", displayName: "JSON"),
        Language(id: "yaml", displayName: "YAML"),
        Language(id: "markdown", displayName: "Markdown"),
        Language(id: "bash", displayName: "Shell"),
        Language(id: "xml", displayName: "HTML/XML"),
        Language(id: "css", displayName: "CSS"),
        Language(id: "scss", displayName: "SCSS"),
        Language(id: "c", displayName: "C"),
        Language(id: "cpp", displayName: "C++"),
        Language(id: "objectivec", displayName: "Objective-C"),
        Language(id: "go", displayName: "Go"),
        Language(id: "rust", displayName: "Rust"),
        Language(id: "java", displayName: "Java"),
        Language(id: "kotlin", displayName: "Kotlin"),
        Language(id: "ruby", displayName: "Ruby"),
        Language(id: "php", displayName: "PHP"),
        Language(id: "sql", displayName: "SQL"),
        Language(id: "toml", displayName: "TOML"),
        Language(id: "ini", displayName: "INI"),
        Language(id: "diff", displayName: "Diff"),
        Language(id: "lua", displayName: "Lua"),
        Language(id: "perl", displayName: "Perl"),
        Language(id: "makefile", displayName: "Makefile"),
        Language(id: "dockerfile", displayName: "Dockerfile"),
    ]

    /// A broad set of additional highlight.js languages for the "All Languages…"
    /// submenu. (Not exhaustive of all ~190, but a deep, alphabetized selection;
    /// the common list above is merged in and de-duplicated.)
    private static let additional: [Language] = [
        Language(id: "ada", displayName: "Ada"),
        Language(id: "apache", displayName: "Apache"),
        Language(id: "applescript", displayName: "AppleScript"),
        Language(id: "asciidoc", displayName: "AsciiDoc"),
        Language(id: "awk", displayName: "Awk"),
        Language(id: "clojure", displayName: "Clojure"),
        Language(id: "cmake", displayName: "CMake"),
        Language(id: "coffeescript", displayName: "CoffeeScript"),
        Language(id: "crystal", displayName: "Crystal"),
        Language(id: "csharp", displayName: "C#"),
        Language(id: "dart", displayName: "Dart"),
        Language(id: "elixir", displayName: "Elixir"),
        Language(id: "elm", displayName: "Elm"),
        Language(id: "erlang", displayName: "Erlang"),
        Language(id: "fortran", displayName: "Fortran"),
        Language(id: "fsharp", displayName: "F#"),
        Language(id: "graphql", displayName: "GraphQL"),
        Language(id: "groovy", displayName: "Groovy"),
        Language(id: "haskell", displayName: "Haskell"),
        Language(id: "haxe", displayName: "Haxe"),
        Language(id: "julia", displayName: "Julia"),
        Language(id: "latex", displayName: "LaTeX"),
        Language(id: "less", displayName: "Less"),
        Language(id: "lisp", displayName: "Lisp"),
        Language(id: "matlab", displayName: "MATLAB"),
        Language(id: "nginx", displayName: "Nginx"),
        Language(id: "nim", displayName: "Nim"),
        Language(id: "nix", displayName: "Nix"),
        Language(id: "ocaml", displayName: "OCaml"),
        Language(id: "powershell", displayName: "PowerShell"),
        Language(id: "prolog", displayName: "Prolog"),
        Language(id: "protobuf", displayName: "Protocol Buffers"),
        Language(id: "puppet", displayName: "Puppet"),
        Language(id: "r", displayName: "R"),
        Language(id: "scala", displayName: "Scala"),
        Language(id: "scheme", displayName: "Scheme"),
        Language(id: "smalltalk", displayName: "Smalltalk"),
        Language(id: "tcl", displayName: "Tcl"),
        Language(id: "vbnet", displayName: "VB.NET"),
        Language(id: "verilog", displayName: "Verilog"),
        Language(id: "vhdl", displayName: "VHDL"),
        Language(id: "vim", displayName: "Vim Script"),
        Language(id: "wasm", displayName: "WebAssembly"),
        Language(id: "zig", displayName: "Zig"),
    ]

    /// The full list = common ∪ additional, de-duplicated by id, alphabetized by
    /// display name.
    public static let all: [Language] = {
        var seen = Set<String>()
        var result: [Language] = []
        for lang in common + additional where !seen.contains(lang.id) {
            seen.insert(lang.id)
            result.append(lang)
        }
        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }()

    /// A tidy display name for a highlight.js id (used by the status bar and
    /// menus). Falls back to title-casing the id.
    public static func displayName(for id: String) -> String {
        if let entry = all.first(where: { $0.id == id }) { return entry.displayName }
        switch id {
        case "cpp": return "C++"
        case "objectivec": return "Objective-C"
        case "xml": return "HTML/XML"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}
