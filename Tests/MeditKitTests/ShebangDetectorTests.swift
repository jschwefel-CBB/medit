import XCTest
@testable import MeditKit

final class ShebangDetectorTests: XCTestCase {

    private func lang(_ firstLine: String) -> String? {
        ShebangDetector.language(forFirstLine: firstLine)
    }

    func testEnvPython() { XCTAssertEqual(lang("#!/usr/bin/env python"), "python") }
    func testDirectPython3() { XCTAssertEqual(lang("#!/usr/bin/python3"), "python") }
    func testBinSh() { XCTAssertEqual(lang("#!/bin/sh"), "bash") }
    func testBinBash() { XCTAssertEqual(lang("#!/bin/bash"), "bash") }
    func testEnvZsh() { XCTAssertEqual(lang("#!/usr/bin/env zsh"), "bash") }
    func testEnvNode() { XCTAssertEqual(lang("#!/usr/bin/env node"), "javascript") }
    func testEnvRuby() { XCTAssertEqual(lang("#!/usr/bin/env ruby"), "ruby") }
    func testDirectPerl() { XCTAssertEqual(lang("#!/usr/bin/perl"), "perl") }
    func testEnvLua() { XCTAssertEqual(lang("#!/usr/bin/env lua"), "lua") }
    func testEnvPhp() { XCTAssertEqual(lang("#!/usr/bin/env php"), "php") }

    func testNoShebangReturnsNil() { XCTAssertNil(lang("import os")) }
    func testEmptyReturnsNil() { XCTAssertNil(lang("")) }
    func testShebangUnknownInterpreterReturnsNil() { XCTAssertNil(lang("#!/usr/bin/env brainfuck")) }
    func testLeadingSpacesStillDetected() { XCTAssertEqual(lang("#!  /usr/bin/env python"), "python") }
}
