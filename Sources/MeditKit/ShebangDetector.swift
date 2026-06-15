import Foundation

/// Maps a script's shebang first line to a highlight.js language id. Pure value
/// logic, fully tested. Returns nil when there's no shebang or the interpreter
/// isn't recognized.
public enum ShebangDetector {

    /// interpreter executable name → language id.
    private static let interpreters: [String: String] = [
        "python": "python", "python2": "python", "python3": "python",
        "sh": "bash", "bash": "bash", "zsh": "bash", "dash": "bash", "ksh": "bash",
        "node": "javascript", "nodejs": "javascript",
        "ruby": "ruby",
        "perl": "perl",
        "lua": "lua",
        "php": "php",
        "awk": "awk",
        "tclsh": "tcl",
        "Rscript": "r",
    ]

    public static func language(forFirstLine firstLine: String) -> String? {
        guard firstLine.hasPrefix("#!") else { return nil }
        // Strip "#!", split into tokens.
        let rest = firstLine.dropFirst(2)
        let tokens = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        // The interpreter is either the first token's basename, or — for
        // "/usr/bin/env python" — the token after "env".
        func basename(_ path: String) -> String {
            (path as NSString).lastPathComponent
        }

        var interpreterToken = basename(tokens[0])
        if interpreterToken == "env", tokens.count >= 2 {
            interpreterToken = basename(tokens[1])
        }
        return interpreters[interpreterToken]
    }
}
