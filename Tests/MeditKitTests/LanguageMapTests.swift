import XCTest
@testable import MeditKit

final class LanguageMapTests: XCTestCase {

    private func lang(forFile name: String) -> String? {
        LanguageMap.language(forFilename: name)
    }

    func testCommonExtensionsMapToHighlightJSIdentifiers() {
        XCTAssertEqual(lang(forFile: "main.swift"), "swift")
        XCTAssertEqual(lang(forFile: "script.py"), "python")
        XCTAssertEqual(lang(forFile: "app.js"), "javascript")
        XCTAssertEqual(lang(forFile: "app.jsx"), "javascript")
        XCTAssertEqual(lang(forFile: "app.ts"), "typescript")
        XCTAssertEqual(lang(forFile: "component.tsx"), "typescript")
        XCTAssertEqual(lang(forFile: "data.json"), "json")
        XCTAssertEqual(lang(forFile: "config.yaml"), "yaml")
        XCTAssertEqual(lang(forFile: "config.yml"), "yaml")
        XCTAssertEqual(lang(forFile: "README.md"), "markdown")
        XCTAssertEqual(lang(forFile: "run.sh"), "bash")
        XCTAssertEqual(lang(forFile: "lib.c"), "c")
        XCTAssertEqual(lang(forFile: "lib.h"), "c")
        XCTAssertEqual(lang(forFile: "engine.cpp"), "cpp")
        XCTAssertEqual(lang(forFile: "engine.hpp"), "cpp")
        XCTAssertEqual(lang(forFile: "view.m"), "objectivec")
        XCTAssertEqual(lang(forFile: "server.go"), "go")
        XCTAssertEqual(lang(forFile: "main.rs"), "rust")
        XCTAssertEqual(lang(forFile: "app.rb"), "ruby")
        XCTAssertEqual(lang(forFile: "Main.java"), "java")
        XCTAssertEqual(lang(forFile: "Main.kt"), "kotlin")
        XCTAssertEqual(lang(forFile: "page.html"), "xml")
        XCTAssertEqual(lang(forFile: "page.xml"), "xml")
        XCTAssertEqual(lang(forFile: "style.css"), "css")
        XCTAssertEqual(lang(forFile: "style.scss"), "scss")
        XCTAssertEqual(lang(forFile: "index.php"), "php")
        XCTAssertEqual(lang(forFile: "query.sql"), "sql")
        XCTAssertEqual(lang(forFile: "Config.toml"), "toml")
        XCTAssertEqual(lang(forFile: "settings.ini"), "ini")
        XCTAssertEqual(lang(forFile: "change.diff"), "diff")
        XCTAssertEqual(lang(forFile: "change.patch"), "diff")
    }

    func testSpecialFilenamesWithoutExtension() {
        XCTAssertEqual(lang(forFile: "Makefile"), "makefile")
        XCTAssertEqual(lang(forFile: "makefile"), "makefile")
        XCTAssertEqual(lang(forFile: "Dockerfile"), "dockerfile")
        XCTAssertEqual(lang(forFile: "Dockerfile.dev"), "dockerfile")
    }

    func testCaseInsensitiveExtensions() {
        XCTAssertEqual(lang(forFile: "MAIN.SWIFT"), "swift")
        XCTAssertEqual(lang(forFile: "Data.JSON"), "json")
    }

    func testFullPathIsHandled() {
        XCTAssertEqual(lang(forFile: "/Users/x/project/src/main.swift"), "swift")
        XCTAssertEqual(LanguageMap.language(forURL: URL(fileURLWithPath: "/tmp/foo.py")), "python")
    }

    func testUnknownOrMissingExtensionReturnsNil() {
        XCTAssertNil(lang(forFile: "mystery.qwerty"))
        XCTAssertNil(lang(forFile: "noextension"))
        XCTAssertNil(lang(forFile: ""))
    }
}
