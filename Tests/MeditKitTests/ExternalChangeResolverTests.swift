import XCTest
@testable import MeditKit

final class ExternalChangeResolverTests: XCTestCase {

    func testNotifyAlwaysBanner() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .notify, isDirty: false), .banner)
        XCTAssertEqual(ExternalChangeResolver.action(policy: .notify, isDirty: true), .banner)
    }

    func testPromptCleanReloadsSilently() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .prompt, isDirty: false), .reloadSilently)
    }

    func testPromptDirtyPrompts() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .prompt, isDirty: true), .prompt)
    }

    func testAutoCleanReloadsSilently() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .autoIfClean, isDirty: false), .reloadSilently)
    }

    func testAutoDirtyPrompts() {
        XCTAssertEqual(ExternalChangeResolver.action(policy: .autoIfClean, isDirty: true), .prompt)
    }
}
