# Autopilot GUI Test Driver — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `autopilot`, a deterministic, app-agnostic macOS GUI test driver that executes declarative JSON test plans against any Mac app via the Accessibility API, with CLI + MCP front-ends over a shared core.

**Architecture:** A standalone SwiftPM package at `~/repositories/autopilot`. A library `AutopilotCore` holds the engine (plan parser, targeting, action engine, assertion engine, reporter). Thin `autopilot` (CLI) and `AutopilotMCP` (MCP server) executables wrap the core. A `TestHostApp` fixture with known AX identifiers is used to test the driver against ground truth. The plan JSON is the only contract between an offline plan author (agent/human) and the executor; no LLM runs in the execution path.

**Tech Stack:** Swift 6 (tools-version 6.0, language mode v5 to match `medit`), AppKit + ApplicationServices (Accessibility `AXUIElement` API), CoreGraphics (event synthesis + screenshots), Vision/Accelerate or vDSP for deterministic template matching, `apple/swift-argument-parser` for the CLI, Swift Testing for tests. macOS 14+.

**Reference spec:** `~/repositories/medit/docs/specs/2026-06-16-gui-test-driver-design.md`

---

## File Structure

Package root: `~/repositories/autopilot/`

```
autopilot/
  Package.swift
  .gitignore
  README.md
  Sources/
    AutopilotCore/
      Plan/
        Plan.swift                 # Plan, TargetApp, Defaults, Step models (Codable)
        Selector.swift             # Selector model + resolution priority enum
        Action.swift               # Action enum + per-action args
        Assertion.swift            # Assertion model: property, op, expected
        PlanParser.swift           # JSON -> Plan, schema validation, include resolution
        PlanError.swift            # typed parse/validation errors
      Targeting/
        ElementRef.swift           # resolved handle: AX element OR screen point
        AXTree.swift               # AX traversal + snapshot/dump helpers
        AXResolver.swift           # selector -> AX element(s)
        VisionResolver.swift       # deterministic template match -> point
        Targeting.swift            # orchestrates AXResolver then VisionResolver
        TargetingError.swift       # zero/ambiguous/timeout errors
      Actions/
        EventSynthesizer.swift     # CGEvent click/type/key/scroll primitives
        ActionEngine.swift         # executes one Step's action
      Assertions/
        AssertionEngine.swift      # evaluates one Step's assertion
      Runtime/
        Permissions.swift          # AX/Automation TCC preflight
        AppLauncher.swift          # launch/terminate target app
        Screenshot.swift           # CGWindow screenshot capture
        Clock.swift                # injectable time source for polling/timeouts
        Poller.swift               # poll-until-condition with timeout
      Report/
        Report.swift               # Report, StepResult models (Codable)
        Reporter.swift             # builds + writes report.json, artifacts
      Runner/
        PlanRunner.swift           # top-level: parse -> run steps -> report
    autopilot/
      main.swift                   # CLI entry (ArgumentParser commands)
    AutopilotMCP/
      main.swift                   # MCP server entry (stdio JSON-RPC)
      MCPServer.swift              # tool dispatch: run_plan, get_report, dump_axtree
  Tests/
    AutopilotCoreTests/
      PlanParserTests.swift
      IncludeResolutionTests.swift
      SelectorResolutionTests.swift
      AssertionEngineTests.swift
      ReporterTests.swift
      PollerTests.swift
      IntegrationTests.swift       # drives TestHostApp end-to-end
  Fixtures/
    TestHostApp/
      Package.swift                # builds a tiny .app bundle
      Sources/TestHostApp/main.swift
```

`medit` integration (Phase 6) modifies files under `~/repositories/medit/`.

---

## Phase 1 — Package scaffold + plan model + parser

### Task 1: Create the SwiftPM package skeleton

**Files:**
- Create: `~/repositories/autopilot/Package.swift`
- Create: `~/repositories/autopilot/.gitignore`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Runtime/Clock.swift` (placeholder so the target compiles)

- [ ] **Step 1: Create the package directory and init git**

Run:
```bash
mkdir -p ~/repositories/autopilot/Sources/AutopilotCore/Runtime
mkdir -p ~/repositories/autopilot/Tests/AutopilotCoreTests
cd ~/repositories/autopilot && git init
```
Expected: `Initialized empty Git repository`.

- [ ] **Step 2: Write `Package.swift`**

Create `~/repositories/autopilot/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "autopilot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AutopilotCore", targets: ["AutopilotCore"]),
        .executable(name: "autopilot", targets: ["autopilot"]),
        .executable(name: "AutopilotMCP", targets: ["AutopilotMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "AutopilotCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "autopilot",
            dependencies: [
                "AutopilotCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AutopilotMCP",
            dependencies: ["AutopilotCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AutopilotCoreTests",
            dependencies: ["AutopilotCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 3: Write `.gitignore`**

Create `~/repositories/autopilot/.gitignore`:
```
.build/
.DS_Store
*.xcodeproj
.swiftpm/
artifacts/
```

- [ ] **Step 4: Add a minimal `Clock.swift` so every target has a source file**

Create `~/repositories/autopilot/Sources/AutopilotCore/Runtime/Clock.swift`:
```swift
import Foundation

/// Injectable time source so polling/timeout logic is testable without real sleeps.
public protocol Clock: Sendable {
    /// Seconds since an arbitrary fixed reference; monotonic.
    func now() -> TimeInterval
    /// Sleep for the given duration.
    func sleep(_ seconds: TimeInterval)
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    public func sleep(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
```

- [ ] **Step 5: Create stub entry points for the two executables**

Create `~/repositories/autopilot/Sources/autopilot/main.swift`:
```swift
print("autopilot")
```
Create `~/repositories/autopilot/Sources/AutopilotMCP/main.swift`:
```swift
print("AutopilotMCP")
```

- [ ] **Step 6: Build to verify the package resolves**

Run: `cd ~/repositories/autopilot && swift build`
Expected: `Build complete!` (after fetching swift-argument-parser).

- [ ] **Step 7: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "chore: scaffold autopilot SwiftPM package"
```

---

### Task 2: Plan model types (Codable)

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Plan/Selector.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Plan/Action.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Plan/Assertion.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Plan/Plan.swift`
- Test: `~/repositories/autopilot/Tests/AutopilotCoreTests/PlanParserTests.swift`

- [ ] **Step 1: Write the failing test for decoding a minimal plan**

Create `~/repositories/autopilot/Tests/AutopilotCoreTests/PlanParserTests.swift`:
```swift
import Testing
import Foundation
@testable import AutopilotCore

@Suite struct PlanDecodingTests {
    @Test func decodesMinimalPlan() throws {
        let json = """
        {
          "schemaVersion": "1.0",
          "name": "smoke",
          "target": { "bundleId": "com.example.app" },
          "steps": [
            { "id": "c1", "action": "click",
              "target": { "role": "AXButton", "identifier": "ok" } }
          ]
        }
        """.data(using: .utf8)!
        let plan = try JSONDecoder().decode(Plan.self, from: json)
        #expect(plan.name == "smoke")
        #expect(plan.schemaVersion == "1.0")
        #expect(plan.target.bundleId == "com.example.app")
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].id == "c1")
        #expect(plan.steps[0].action == .click)
        #expect(plan.steps[0].target?.identifier == "ok")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/repositories/autopilot && swift test --filter PlanDecodingTests`
Expected: FAIL — `cannot find 'Plan' in scope`.

- [ ] **Step 3: Write `Selector.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Plan/Selector.swift`:
```swift
import Foundation

/// A deterministic locator for one UI element. Predicates are ANDed.
/// Resolution priority is fixed: identifier > role+attr > path > vision.
public struct Selector: Codable, Equatable, Sendable {
    public var role: String?
    public var identifier: String?
    public var title: String?
    public var label: String?
    public var value: String?
    /// Positional index path, e.g. ["window[0]", "group[2]", "button[0]"].
    public var path: [String]?
    public var vision: VisionSelector?

    public init(role: String? = nil, identifier: String? = nil, title: String? = nil,
                label: String? = nil, value: String? = nil, path: [String]? = nil,
                vision: VisionSelector? = nil) {
        self.role = role; self.identifier = identifier; self.title = title
        self.label = label; self.value = value; self.path = path; self.vision = vision
    }
}

/// Template-match fallback locator. Deterministic: fixed confidence threshold, no LLM.
public struct VisionSelector: Codable, Equatable, Sendable {
    public var image: String          // path to template PNG, relative to plan file
    public var confidence: Double     // 0...1, required match threshold
    public init(image: String, confidence: Double) {
        self.image = image; self.confidence = confidence
    }
}
```

- [ ] **Step 4: Write `Action.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Plan/Action.swift`:
```swift
import Foundation

/// v1 action vocabulary. Lean by design.
public enum Action: String, Codable, Sendable {
    case launch, terminate
    case click, doubleClick, rightClick
    case type, keyPress, setValue, scroll
    case waitFor, screenshot, assert
    case wait   // explicit, discouraged fixed delay
}

/// Per-action arguments. Only the fields relevant to a given action are used.
public struct ActionArgs: Codable, Equatable, Sendable {
    public var text: String?          // type / setValue
    public var keys: String?          // keyPress, e.g. "cmd+s"
    public var deltaX: Int?           // scroll
    public var deltaY: Int?           // scroll
    public var seconds: Double?       // wait
    public var path: String?          // screenshot output path
    public var present: Bool?         // waitFor: true=appears, false=disappears
    public init() {}
}
```

- [ ] **Step 5: Write `Assertion.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Plan/Assertion.swift`:
```swift
import Foundation

public enum AssertProperty: String, Codable, Sendable {
    case value, title, enabled, focused, position, size, exists
}

public enum AssertOp: String, Codable, Sendable {
    case equals, notEquals, contains, matches
    case exists, notExists, greaterThan, lessThan
}

public struct Assertion: Codable, Equatable, Sendable {
    public var property: AssertProperty
    public var op: AssertOp
    /// Expected value as a string; numeric ops parse it as Double.
    public var expected: String?
    public init(property: AssertProperty, op: AssertOp, expected: String? = nil) {
        self.property = property; self.op = op; self.expected = expected
    }
}
```

- [ ] **Step 6: Write `Plan.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Plan/Plan.swift`:
```swift
import Foundation

public struct TargetApp: Codable, Equatable, Sendable {
    public var bundleId: String?
    public var path: String?
    public var launchArgs: [String]?
    public var launchFiles: [String]?
    public init(bundleId: String? = nil, path: String? = nil,
                launchArgs: [String]? = nil, launchFiles: [String]? = nil) {
        self.bundleId = bundleId; self.path = path
        self.launchArgs = launchArgs; self.launchFiles = launchFiles
    }
}

public struct PlanDefaults: Codable, Equatable, Sendable {
    public var timeoutMs: Int?
    public var retryIntervalMs: Int?
    public init(timeoutMs: Int? = nil, retryIntervalMs: Int? = nil) {
        self.timeoutMs = timeoutMs; self.retryIntervalMs = retryIntervalMs
    }
}

public struct Step: Codable, Equatable, Sendable {
    public var id: String
    public var action: Action
    public var target: Selector?
    public var args: ActionArgs?
    public var assert: Assertion?
    public var timeoutMs: Int?
    public init(id: String, action: Action, target: Selector? = nil,
                args: ActionArgs? = nil, assert: Assertion? = nil, timeoutMs: Int? = nil) {
        self.id = id; self.action = action; self.target = target
        self.args = args; self.assert = assert; self.timeoutMs = timeoutMs
    }
}

public struct Plan: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var name: String
    public var include: [String]?
    public var target: TargetApp
    public var defaults: PlanDefaults?
    public var steps: [Step]
    public init(schemaVersion: String, name: String, include: [String]? = nil,
                target: TargetApp, defaults: PlanDefaults? = nil, steps: [Step]) {
        self.schemaVersion = schemaVersion; self.name = name; self.include = include
        self.target = target; self.defaults = defaults; self.steps = steps
    }
}
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd ~/repositories/autopilot && swift test --filter PlanDecodingTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: plan model types (Plan, Step, Selector, Action, Assertion)"
```

---

### Task 3: PlanParser with schema validation

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Plan/PlanError.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Plan/PlanParser.swift`
- Test: `~/repositories/autopilot/Tests/AutopilotCoreTests/PlanParserTests.swift` (extend)

- [ ] **Step 1: Write failing tests for validation rules**

Append to `~/repositories/autopilot/Tests/AutopilotCoreTests/PlanParserTests.swift`:
```swift
@Suite struct PlanValidationTests {
    @Test func rejectsUnsupportedSchemaVersion() throws {
        let json = """
        {"schemaVersion":"2.0","name":"x","target":{"bundleId":"a"},"steps":[]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func rejectsTargetWithNeitherBundleIdNorPath() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{},"steps":[]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func rejectsDuplicateStepIds() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"s","action":"screenshot"},{"id":"s","action":"screenshot"}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func rejectsActionRequiringTargetWithoutOne() throws {
        // click requires a target
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"s","action":"click"}]}
        """.data(using: .utf8)!
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        }
    }

    @Test func acceptsValidPlan() throws {
        let json = """
        {"schemaVersion":"1.0","name":"x","target":{"bundleId":"a"},
         "steps":[{"id":"s","action":"click","target":{"identifier":"ok"}}]}
        """.data(using: .utf8)!
        let plan = try PlanParser().parse(data: json, baseDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(plan.steps.count == 1)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/repositories/autopilot && swift test --filter PlanValidationTests`
Expected: FAIL — `cannot find 'PlanParser' in scope`.

- [ ] **Step 3: Write `PlanError.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Plan/PlanError.swift`:
```swift
import Foundation

public enum PlanError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(String)
    case invalidTarget(String)
    case duplicateStepId(String)
    case missingTarget(stepId: String, action: String)
    case missingArgs(stepId: String, action: String, field: String)
    case includeCycle(path: String)
    case includeTooDeep(maxDepth: Int)
    case includeNotFound(path: String)
    case decode(String)

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let v): return "Unsupported schemaVersion: \(v) (supported: 1.0)"
        case .invalidTarget(let m): return "Invalid target: \(m)"
        case .duplicateStepId(let id): return "Duplicate step id: \(id)"
        case .missingTarget(let id, let a): return "Step \(id): action '\(a)' requires a target selector"
        case .missingArgs(let id, let a, let f): return "Step \(id): action '\(a)' requires args.\(f)"
        case .includeCycle(let p): return "Include cycle detected at: \(p)"
        case .includeTooDeep(let d): return "Include nesting exceeds max depth \(d)"
        case .includeNotFound(let p): return "Included plan not found: \(p)"
        case .decode(let m): return "Plan decode error: \(m)"
        }
    }
}
```

- [ ] **Step 4: Write `PlanParser.swift` (validation only; include resolution added in Task 4)**

Create `~/repositories/autopilot/Sources/AutopilotCore/Plan/PlanParser.swift`:
```swift
import Foundation

public struct PlanParser {
    public static let supportedSchemaVersion = "1.0"
    public static let maxIncludeDepth = 8

    public init() {}

    /// Parse raw JSON into a validated Plan. `baseDirectory` is the directory
    /// the plan file lives in, used to resolve `include` paths (Task 4).
    public func parse(data: Data, baseDirectory: URL) throws -> Plan {
        let plan: Plan
        do {
            plan = try JSONDecoder().decode(Plan.self, from: data)
        } catch {
            throw PlanError.decode(String(describing: error))
        }
        let resolved = try resolveIncludes(plan, baseDirectory: baseDirectory,
                                           stack: [], depth: 0)
        try validate(resolved)
        return resolved
    }

    /// Resolve includes — real implementation lands in Task 4. For now, no includes.
    func resolveIncludes(_ plan: Plan, baseDirectory: URL,
                         stack: [String], depth: Int) throws -> Plan {
        return plan
    }

    func validate(_ plan: Plan) throws {
        guard plan.schemaVersion == Self.supportedSchemaVersion else {
            throw PlanError.unsupportedSchemaVersion(plan.schemaVersion)
        }
        if (plan.target.bundleId?.isEmpty ?? true) && (plan.target.path?.isEmpty ?? true) {
            throw PlanError.invalidTarget("must set either bundleId or path")
        }
        var seen = Set<String>()
        for step in plan.steps {
            if !seen.insert(step.id).inserted {
                throw PlanError.duplicateStepId(step.id)
            }
            try validateStep(step)
        }
    }

    private static let targetRequiringActions: Set<Action> = [
        .click, .doubleClick, .rightClick, .type, .keyPress, .setValue, .scroll, .waitFor, .assert
    ]

    func validateStep(_ step: Step) throws {
        if Self.targetRequiringActions.contains(step.action), step.target == nil {
            throw PlanError.missingTarget(stepId: step.id, action: step.action.rawValue)
        }
        switch step.action {
        case .type, .setValue:
            if step.args?.text == nil {
                throw PlanError.missingArgs(stepId: step.id, action: step.action.rawValue, field: "text")
            }
        case .keyPress:
            if step.args?.keys == nil {
                throw PlanError.missingArgs(stepId: step.id, action: step.action.rawValue, field: "keys")
            }
        case .assert:
            if step.assert == nil {
                throw PlanError.missingArgs(stepId: step.id, action: step.action.rawValue, field: "assert")
            }
        case .wait:
            if step.args?.seconds == nil {
                throw PlanError.missingArgs(stepId: step.id, action: step.action.rawValue, field: "seconds")
            }
        default:
            break
        }
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd ~/repositories/autopilot && swift test --filter PlanValidationTests`
Expected: PASS (all 5 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: PlanParser with schema + step validation"
```

---

### Task 4: Include resolution (composition)

**Files:**
- Modify: `~/repositories/autopilot/Sources/AutopilotCore/Plan/PlanParser.swift` (replace `resolveIncludes`)
- Test: `~/repositories/autopilot/Tests/AutopilotCoreTests/IncludeResolutionTests.swift`

- [ ] **Step 1: Write failing tests using temp plan files**

Create `~/repositories/autopilot/Tests/AutopilotCoreTests/IncludeResolutionTests.swift`:
```swift
import Testing
import Foundation
@testable import AutopilotCore

@Suite struct IncludeResolutionTests {
    /// Write JSON to a temp dir and return (dir, fileURL).
    func writePlan(_ json: String, name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try json.data(using: .utf8)!.write(to: url)
        return url
    }

    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("autopilot-inc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func prependsIncludedSteps() throws {
        let dir = try tempDir()
        _ = try writePlan("""
        {"schemaVersion":"1.0","name":"setup","target":{"bundleId":"a"},
         "steps":[{"id":"launch","action":"launch"}]}
        """, name: "setup.json", in: dir)
        let mainURL = try writePlan("""
        {"schemaVersion":"1.0","name":"main","include":["setup.json"],
         "target":{"bundleId":"a"},
         "steps":[{"id":"shot","action":"screenshot"}]}
        """, name: "main.json", in: dir)

        let data = try Data(contentsOf: mainURL)
        let plan = try PlanParser().parse(data: data, baseDirectory: dir)
        #expect(plan.steps.map(\.id) == ["launch", "shot"])
        #expect(plan.include == nil) // flattened away after resolution
    }

    @Test func detectsCycle() throws {
        let dir = try tempDir()
        _ = try writePlan("""
        {"schemaVersion":"1.0","name":"a","include":["b.json"],
         "target":{"bundleId":"a"},"steps":[{"id":"a1","action":"screenshot"}]}
        """, name: "a.json", in: dir)
        let bURL = try writePlan("""
        {"schemaVersion":"1.0","name":"b","include":["a.json"],
         "target":{"bundleId":"a"},"steps":[{"id":"b1","action":"screenshot"}]}
        """, name: "b.json", in: dir)
        let data = try Data(contentsOf: bURL)
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: data, baseDirectory: dir)
        }
    }

    @Test func missingIncludeThrows() throws {
        let dir = try tempDir()
        let mainURL = try writePlan("""
        {"schemaVersion":"1.0","name":"main","include":["nope.json"],
         "target":{"bundleId":"a"},"steps":[{"id":"s","action":"screenshot"}]}
        """, name: "main.json", in: dir)
        let data = try Data(contentsOf: mainURL)
        #expect(throws: PlanError.self) {
            _ = try PlanParser().parse(data: data, baseDirectory: dir)
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/repositories/autopilot && swift test --filter IncludeResolutionTests`
Expected: FAIL — `prependsIncludedSteps` gets `["shot"]` not `["launch","shot"]`; cycle test does not throw.

- [ ] **Step 3: Replace `resolveIncludes` in `PlanParser.swift`**

In `~/repositories/autopilot/Sources/AutopilotCore/Plan/PlanParser.swift`, replace the stub `resolveIncludes(...)` method with:
```swift
    /// Resolve `include` references by prepending included steps in order.
    /// `stack` holds canonical paths of plans currently being resolved (cycle detection).
    /// Host plan's target/defaults win; included steps are prepended before host steps.
    func resolveIncludes(_ plan: Plan, baseDirectory: URL,
                         stack: [String], depth: Int) throws -> Plan {
        guard let includes = plan.include, !includes.isEmpty else { return plan }
        if depth >= Self.maxIncludeDepth { throw PlanError.includeTooDeep(maxDepth: Self.maxIncludeDepth) }

        var prependedSteps: [Step] = []
        for rel in includes {
            let url = baseDirectory.appendingPathComponent(rel)
            let canonical = url.standardizedFileURL.path
            if stack.contains(canonical) { throw PlanError.includeCycle(path: canonical) }
            guard FileManager.default.fileExists(atPath: canonical) else {
                throw PlanError.includeNotFound(path: rel)
            }
            let data: Data
            do { data = try Data(contentsOf: url) }
            catch { throw PlanError.includeNotFound(path: rel) }
            let child: Plan
            do { child = try JSONDecoder().decode(Plan.self, from: data) }
            catch { throw PlanError.decode("in included \(rel): \(error)") }
            let resolvedChild = try resolveIncludes(
                child, baseDirectory: url.deletingLastPathComponent(),
                stack: stack + [canonical], depth: depth + 1)
            prependedSteps.append(contentsOf: resolvedChild.steps)
        }

        var flattened = plan
        flattened.steps = prependedSteps + plan.steps
        flattened.include = nil
        return flattened
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd ~/repositories/autopilot && swift test --filter IncludeResolutionTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite to confirm no regression**

Run: `cd ~/repositories/autopilot && swift test`
Expected: PASS (all plan tests).

- [ ] **Step 6: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: include resolution with cycle + depth detection"
```

---

### Task 5: TestHostApp fixture

A tiny AppKit app with **known AX identifiers**, used as ground truth for driving tests. It exposes: a button (`okButton`), a text field (`nameField`), a static label (`statusLabel`) that mirrors the field's text, and a counter label (`countLabel`) incremented by the button.

**Files:**
- Create: `~/repositories/autopilot/Fixtures/TestHostApp/Package.swift`
- Create: `~/repositories/autopilot/Fixtures/TestHostApp/Sources/TestHostApp/main.swift`

- [ ] **Step 1: Write the TestHostApp package manifest**

Create `~/repositories/autopilot/Fixtures/TestHostApp/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestHostApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TestHostApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
```

- [ ] **Step 2: Write the app source with known AX identifiers**

Create `~/repositories/autopilot/Fixtures/TestHostApp/Sources/TestHostApp/main.swift`:
```swift
import AppKit

final class AppController: NSObject, NSApplicationDelegate {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let nameField = NSTextField(frame: NSRect(x: 20, y: 150, width: 200, height: 24))
    let statusLabel = NSTextField(labelWithString: "status: ")
    let countLabel = NSTextField(labelWithString: "count: 0")
    var count = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        window.title = "TestHostApp"
        let content = NSView(frame: window.contentView!.bounds)

        nameField.setAccessibilityIdentifier("nameField")
        nameField.target = self
        nameField.action = #selector(nameChanged)
        content.addSubview(nameField)

        statusLabel.frame = NSRect(x: 20, y: 110, width: 320, height: 20)
        statusLabel.setAccessibilityIdentifier("statusLabel")
        content.addSubview(statusLabel)

        countLabel.frame = NSRect(x: 20, y: 80, width: 320, height: 20)
        countLabel.setAccessibilityIdentifier("countLabel")
        content.addSubview(countLabel)

        let okButton = NSButton(title: "OK", target: self, action: #selector(okTapped))
        okButton.frame = NSRect(x: 20, y: 30, width: 80, height: 28)
        okButton.setAccessibilityIdentifier("okButton")
        content.addSubview(okButton)

        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func nameChanged() {
        statusLabel.stringValue = "status: \(nameField.stringValue)"
    }

    @objc func okTapped() {
        count += 1
        countLabel.stringValue = "count: \(count)"
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
```

- [ ] **Step 3: Build the fixture to verify it compiles**

Run: `cd ~/repositories/autopilot/Fixtures/TestHostApp && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Document how integration tests locate the built binary**

Append to the file a top comment (already present via header) — no code change. Note in commit body: integration tests (Task 13) launch the built executable at
`Fixtures/TestHostApp/.build/debug/TestHostApp`.

- [ ] **Step 5: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "test: TestHostApp fixture with known AX identifiers"
```

---

## Phase 2 — AX targeting engine + poller

### Task 6: ElementRef + Poller

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Targeting/ElementRef.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Runtime/Poller.swift`
- Test: `~/repositories/autopilot/Tests/AutopilotCoreTests/PollerTests.swift`

- [ ] **Step 1: Write `ElementRef.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Targeting/ElementRef.swift`:
```swift
import Foundation
import ApplicationServices

/// A resolved element: either a live AX element handle, or a screen point
/// (from the vision fallback) when no AX element is available.
public enum ElementRef {
    case ax(AXUIElement)
    case point(CGPoint)
}
```

- [ ] **Step 2: Write failing tests for the Poller**

Create `~/repositories/autopilot/Tests/AutopilotCoreTests/PollerTests.swift`:
```swift
import Testing
import Foundation
@testable import AutopilotCore

/// Deterministic fake clock: advances only when sleep() is called.
final class FakeClock: Clock, @unchecked Sendable {
    private var t: TimeInterval = 0
    func now() -> TimeInterval { t }
    func sleep(_ seconds: TimeInterval) { t += seconds }
}

@Suite struct PollerTests {
    @Test func returnsImmediatelyWhenConditionTrue() throws {
        let clock = FakeClock()
        let poller = Poller(clock: clock)
        var calls = 0
        let ok = poller.waitUntil(timeoutMs: 1000, intervalMs: 100) {
            calls += 1; return true
        }
        #expect(ok)
        #expect(calls == 1)
    }

    @Test func pollsUntilConditionBecomesTrue() throws {
        let clock = FakeClock()
        let poller = Poller(clock: clock)
        var calls = 0
        let ok = poller.waitUntil(timeoutMs: 1000, intervalMs: 100) {
            calls += 1; return calls >= 3
        }
        #expect(ok)
        #expect(calls == 3)
    }

    @Test func timesOutWhenNeverTrue() throws {
        let clock = FakeClock()
        let poller = Poller(clock: clock)
        var calls = 0
        let ok = poller.waitUntil(timeoutMs: 500, intervalMs: 100) {
            calls += 1; return false
        }
        #expect(!ok)
        // 500ms / 100ms interval => ~6 attempts (t=0,100,200,300,400,500)
        #expect(calls >= 5 && calls <= 7)
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `cd ~/repositories/autopilot && swift test --filter PollerTests`
Expected: FAIL — `cannot find 'Poller' in scope`.

- [ ] **Step 4: Write `Poller.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Runtime/Poller.swift`:
```swift
import Foundation

/// Polls a condition until it returns true or the timeout elapses.
/// Time is driven by the injected Clock, so tests are deterministic.
public struct Poller {
    let clock: Clock
    public init(clock: Clock = SystemClock()) { self.clock = clock }

    /// Returns true if `condition` became true within the timeout.
    @discardableResult
    public func waitUntil(timeoutMs: Int, intervalMs: Int,
                          condition: () -> Bool) -> Bool {
        let start = clock.now()
        let timeout = TimeInterval(timeoutMs) / 1000.0
        let interval = TimeInterval(intervalMs) / 1000.0
        while true {
            if condition() { return true }
            if clock.now() - start >= timeout { return false }
            clock.sleep(interval)
        }
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd ~/repositories/autopilot && swift test --filter PollerTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: ElementRef + deterministic Poller"
```

---

### Task 7: AXTree traversal + property reads

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Targeting/AXTree.swift`

This is a thin, well-bounded wrapper over the C Accessibility API. It is exercised end-to-end by the integration tests (Task 13) against TestHostApp; pure-unit testing of the C API is impractical, so this task has no isolated unit test — its correctness is verified by Tasks 8 and 13.

- [ ] **Step 1: Write `AXTree.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Targeting/AXTree.swift`:
```swift
import Foundation
import ApplicationServices

/// Attribute reads + tree traversal over the Accessibility API.
public enum AXTree {
    /// Read a string attribute (e.g. kAXRoleAttribute) or nil.
    public static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success else { return nil }
        return value as? String
    }

    /// Read a bool attribute, or nil.
    public static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    /// Read frame (position + size) in screen coordinates, or nil.
    public static func frame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// Immediate children of an element.
    public static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard err == .success, let arr = value as? [AXUIElement] else { return [] }
        return arr
    }

    /// The application-level AX element for a running process.
    public static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// Depth-first pre-order walk, invoking `visit` on every descendant
    /// (including `root`). Bounded by `maxNodes` as a runaway guard.
    public static func walk(_ root: AXUIElement, maxNodes: Int = 5000,
                            visit: (AXUIElement) -> Void) {
        var stack = [root]
        var count = 0
        while let el = stack.popLast() {
            visit(el)
            count += 1
            if count >= maxNodes { return }
            stack.append(contentsOf: children(el).reversed())
        }
    }

    /// A JSON-serializable snapshot of the subtree (role/identifier/title/value/frame),
    /// used for failure diagnostics.
    public static func snapshot(_ root: AXUIElement, maxNodes: Int = 2000) -> [[String: String]] {
        var out: [[String: String]] = []
        walk(root, maxNodes: maxNodes) { el in
            var node: [String: String] = [:]
            if let r = string(el, kAXRoleAttribute as String) { node["role"] = r }
            if let id = string(el, kAXIdentifierAttribute as String) { node["identifier"] = id }
            if let t = string(el, kAXTitleAttribute as String) { node["title"] = t }
            if let v = string(el, kAXValueAttribute as String) { node["value"] = v }
            if let f = frame(el) {
                node["frame"] = "\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))"
            }
            out.append(node)
        }
        return out
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ~/repositories/autopilot && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: AXTree traversal + attribute reads + snapshot"
```

---

### Task 8: AXResolver — selector to element(s)

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Targeting/TargetingError.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Targeting/AXResolver.swift`

Unit-tested via the `matches(node:selector:)` pure predicate (no live AX needed); full resolution is covered by integration tests (Task 13).

- [ ] **Step 1: Write `TargetingError.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Targeting/TargetingError.swift`:
```swift
import Foundation

public enum TargetingError: Error, CustomStringConvertible {
    case notFound(selector: String)
    case ambiguous(selector: String, count: Int)
    case timedOut(selector: String, timeoutMs: Int)

    public var description: String {
        switch self {
        case .notFound(let s): return "No element matched selector: \(s)"
        case .ambiguous(let s, let n): return "Selector matched \(n) elements (expected 1): \(s)"
        case .timedOut(let s, let ms): return "Timed out after \(ms)ms waiting for: \(s)"
        }
    }
}
```

- [ ] **Step 2: Write the failing test for the pure matcher**

Create `~/repositories/autopilot/Tests/AutopilotCoreTests/SelectorResolutionTests.swift`:
```swift
import Testing
import Foundation
@testable import AutopilotCore

@Suite struct SelectorMatcherTests {
    // A snapshot node is a [String:String] as produced by AXTree.snapshot.
    @Test func matchesByIdentifier() {
        let node = ["role": "AXButton", "identifier": "okButton", "title": "OK"]
        #expect(AXResolver.matches(node: node, selector: Selector(identifier: "okButton")))
        #expect(!AXResolver.matches(node: node, selector: Selector(identifier: "cancel")))
    }

    @Test func matchesByRoleAndTitle() {
        let node = ["role": "AXButton", "title": "OK"]
        #expect(AXResolver.matches(node: node, selector: Selector(role: "AXButton", title: "OK")))
        #expect(!AXResolver.matches(node: node, selector: Selector(role: "AXButton", title: "No")))
    }

    @Test func andsAllPredicates() {
        let node = ["role": "AXButton", "identifier": "okButton", "title": "OK"]
        // identifier matches but role does not -> no match
        #expect(!AXResolver.matches(node: node,
            selector: Selector(role: "AXTextField", identifier: "okButton")))
    }

    @Test func emptySelectorMatchesNothing() {
        let node = ["role": "AXButton"]
        #expect(!AXResolver.matches(node: node, selector: Selector()))
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `cd ~/repositories/autopilot && swift test --filter SelectorMatcherTests`
Expected: FAIL — `cannot find 'AXResolver' in scope`.

- [ ] **Step 4: Write `AXResolver.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Targeting/AXResolver.swift`:
```swift
import Foundation
import ApplicationServices

/// Resolves a Selector against a running app's AX tree.
public struct AXResolver {
    public init() {}

    /// Pure predicate: does a snapshot node satisfy the selector?
    /// All present predicates are ANDed. An all-nil selector matches nothing.
    public static func matches(node: [String: String], selector: Selector) -> Bool {
        var anyPredicate = false
        func check(_ value: String?, _ key: String) -> Bool {
            guard let value else { return true }      // predicate absent: no constraint
            anyPredicate = true
            return node[key] == value
        }
        let ok = check(selector.role, "role")
            && check(selector.identifier, "identifier")
            && check(selector.title, "title")
            && check(selector.label, "label")
            && check(selector.value, "value")
        return anyPredicate && ok
    }

    /// Resolve to exactly one AX element. Throws on zero or multiple matches.
    /// `path` and `vision` are handled by the Targeting orchestrator, not here.
    public func resolveOne(in appElement: AXUIElement, selector: Selector) throws -> AXUIElement {
        var matches: [AXUIElement] = []
        AXTree.walk(appElement) { el in
            var node: [String: String] = [:]
            if let r = AXTree.string(el, kAXRoleAttribute as String) { node["role"] = r }
            if let id = AXTree.string(el, kAXIdentifierAttribute as String) { node["identifier"] = id }
            if let t = AXTree.string(el, kAXTitleAttribute as String) { node["title"] = t }
            if let v = AXTree.string(el, kAXValueAttribute as String) { node["value"] = v }
            if Self.matches(node: node, selector: selector) { matches.append(el) }
        }
        let desc = Self.describe(selector)
        if matches.isEmpty { throw TargetingError.notFound(selector: desc) }
        if matches.count > 1 { throw TargetingError.ambiguous(selector: desc, count: matches.count) }
        return matches[0]
    }

    /// Count matches (for waitFor present/absent checks) without throwing.
    public func count(in appElement: AXUIElement, selector: Selector) -> Int {
        var n = 0
        AXTree.walk(appElement) { el in
            var node: [String: String] = [:]
            if let r = AXTree.string(el, kAXRoleAttribute as String) { node["role"] = r }
            if let id = AXTree.string(el, kAXIdentifierAttribute as String) { node["identifier"] = id }
            if let t = AXTree.string(el, kAXTitleAttribute as String) { node["title"] = t }
            if let v = AXTree.string(el, kAXValueAttribute as String) { node["value"] = v }
            if Self.matches(node: node, selector: selector) { n += 1 }
        }
        return n
    }

    static func describe(_ s: Selector) -> String {
        var parts: [String] = []
        if let r = s.role { parts.append("role=\(r)") }
        if let id = s.identifier { parts.append("identifier=\(id)") }
        if let t = s.title { parts.append("title=\(t)") }
        if let l = s.label { parts.append("label=\(l)") }
        if let v = s.value { parts.append("value=\(v)") }
        if let p = s.path { parts.append("path=\(p.joined(separator: "/"))") }
        return "{" + parts.joined(separator: ", ") + "}"
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd ~/repositories/autopilot && swift test --filter SelectorMatcherTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: AXResolver with pure selector matcher + resolveOne/count"
```

---

## Phase 3 — Actions, assertions, runtime, reporter, runner

### Task 9: EventSynthesizer + ActionEngine

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Actions/EventSynthesizer.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Actions/ActionEngine.swift`

EventSynthesizer is a thin CoreGraphics wrapper (verified via integration tests, Task 13). ActionEngine's `keyChord` parser is pure and unit-tested.

- [ ] **Step 1: Write `EventSynthesizer.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Actions/EventSynthesizer.swift`:
```swift
import Foundation
import CoreGraphics
import ApplicationServices

/// Synthesizes low-level input events via CoreGraphics.
public enum EventSynthesizer {
    public static func click(at point: CGPoint, clickCount: Int = 1, rightButton: Bool = false) {
        let button: CGMouseButton = rightButton ? .right : .left
        let down: CGEventType = rightButton ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = rightButton ? .rightMouseUp : .leftMouseUp
        for _ in 0..<clickCount {
            let d = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: point, mouseButton: button)
            let u = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: button)
            d?.post(tap: .cghidEventTap)
            u?.post(tap: .cghidEventTap)
        }
    }

    /// Type a string as unicode keyboard events (works regardless of layout).
    public static func type(_ text: String) {
        for scalar in text.unicodeScalars {
            var ch = UniChar(scalar.value > 0xFFFF ? 0 : scalar.value)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            if scalar.value <= 0xFFFF {
                down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
                up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
            }
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Press a key chord, e.g. virtualKey for "s" with .maskCommand.
    public static func keyChord(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    public static func scroll(dx: Int32, dy: Int32) {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        e?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Write failing test for the key-chord parser**

Append to `~/repositories/autopilot/Tests/AutopilotCoreTests/SelectorResolutionTests.swift`:
```swift
@Suite struct KeyChordParseTests {
    @Test func parsesCmdS() throws {
        let chord = try ActionEngine.parseChord("cmd+s")
        #expect(chord.flags.contains(.maskCommand))
        #expect(chord.virtualKey == 1) // ANSI 's'
    }

    @Test func parsesShiftCmdLeftLetter() throws {
        let chord = try ActionEngine.parseChord("shift+cmd+a")
        #expect(chord.flags.contains(.maskShift))
        #expect(chord.flags.contains(.maskCommand))
        #expect(chord.virtualKey == 0) // ANSI 'a'
    }

    @Test func unknownKeyThrows() {
        #expect(throws: Error.self) { _ = try ActionEngine.parseChord("cmd+£") }
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `cd ~/repositories/autopilot && swift test --filter KeyChordParseTests`
Expected: FAIL — `cannot find 'ActionEngine' in scope`.

- [ ] **Step 4: Write `ActionEngine.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Actions/ActionEngine.swift`:
```swift
import Foundation
import CoreGraphics
import ApplicationServices

public struct ActionEngine {
    public init() {}

    public struct Chord { public var virtualKey: CGKeyCode; public var flags: CGEventFlags }

    /// Map a small set of letters to ANSI virtual key codes. Extend as needed.
    static let letterKeyCodes: [Character: CGKeyCode] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,
        "b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
        "o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46,
        "1":18,"2":19,"3":20,"4":21,"5":23,"6":22,"7":26,"8":28,"9":25,"0":29
    ]
    static let namedKeyCodes: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
        "escape": 27, "left": 123, "right": 124, "down": 125, "up": 126
    ]

    public static func parseChord(_ s: String) throws -> Chord {
        let parts = s.lowercased().split(separator: "+").map(String.init)
        guard let keyToken = parts.last else { throw PlanError.decode("empty key chord") }
        var flags: CGEventFlags = []
        for mod in parts.dropLast() {
            switch mod {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: throw PlanError.decode("unknown modifier: \(mod)")
            }
        }
        if let named = namedKeyCodes[keyToken] { return Chord(virtualKey: named, flags: flags) }
        if keyToken.count == 1, let code = letterKeyCodes[keyToken.first!] {
            return Chord(virtualKey: code, flags: flags)
        }
        throw PlanError.decode("unknown key: \(keyToken)")
    }

    /// Center point of an ElementRef for click/type targeting.
    func point(for ref: ElementRef) -> CGPoint? {
        switch ref {
        case .point(let p): return p
        case .ax(let el):
            guard let f = AXTree.frame(el) else { return nil }
            return CGPoint(x: f.midX, y: f.midY)
        }
    }

    /// Perform a step's action against a resolved element (when applicable).
    /// Returns nothing; throws on unrecoverable failures.
    public func perform(action: Action, args: ActionArgs?, ref: ElementRef?) throws {
        switch action {
        case .click:
            guard let ref, let p = point(for: ref) else { throw PlanError.decode("click needs a point") }
            EventSynthesizer.click(at: p)
        case .doubleClick:
            guard let ref, let p = point(for: ref) else { throw PlanError.decode("doubleClick needs a point") }
            EventSynthesizer.click(at: p, clickCount: 2)
        case .rightClick:
            guard let ref, let p = point(for: ref) else { throw PlanError.decode("rightClick needs a point") }
            EventSynthesizer.click(at: p, rightButton: true)
        case .type:
            guard let text = args?.text else { throw PlanError.decode("type needs text") }
            if let ref, let p = point(for: ref) { EventSynthesizer.click(at: p) } // focus first
            EventSynthesizer.type(text)
        case .setValue:
            guard let text = args?.text, case .ax(let el)? = ref else { throw PlanError.decode("setValue needs AX element + text") }
            AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFString)
        case .keyPress:
            guard let keys = args?.keys else { throw PlanError.decode("keyPress needs keys") }
            let chord = try Self.parseChord(keys)
            EventSynthesizer.keyChord(virtualKey: chord.virtualKey, flags: chord.flags)
        case .scroll:
            EventSynthesizer.scroll(dx: Int32(args?.deltaX ?? 0), dy: Int32(args?.deltaY ?? 0))
        case .launch, .terminate, .waitFor, .screenshot, .assert, .wait:
            break // handled by PlanRunner, not here
        }
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `cd ~/repositories/autopilot && swift test --filter KeyChordParseTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: EventSynthesizer + ActionEngine with chord parser"
```

---

### Task 10: AssertionEngine

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Assertions/AssertionEngine.swift`
- Test: `~/repositories/autopilot/Tests/AutopilotCoreTests/AssertionEngineTests.swift`

The engine is split into a **pure evaluator** (`evaluate(op:actual:expected:)`) that is fully unit-tested, plus a thin AX property reader used at runtime.

- [ ] **Step 1: Write failing tests for the pure evaluator**

Create `~/repositories/autopilot/Tests/AutopilotCoreTests/AssertionEngineTests.swift`:
```swift
import Testing
import Foundation
@testable import AutopilotCore

@Suite struct AssertionEvaluatorTests {
    let e = AssertionEngine()

    @Test func equals() { #expect(e.evaluate(op: .equals, actual: "2 lines", expected: "2 lines")) }
    @Test func notEquals() { #expect(e.evaluate(op: .notEquals, actual: "a", expected: "b")) }
    @Test func contains() { #expect(e.evaluate(op: .contains, actual: "hello world", expected: "world")) }
    @Test func matchesRegex() { #expect(e.evaluate(op: .matches, actual: "count: 7", expected: #"count: \d+"#)) }
    @Test func greaterThan() { #expect(e.evaluate(op: .greaterThan, actual: "10", expected: "3")) }
    @Test func lessThan() { #expect(e.evaluate(op: .lessThan, actual: "2", expected: "9")) }
    @Test func greaterThanNonNumericIsFalse() { #expect(!e.evaluate(op: .greaterThan, actual: "x", expected: "3")) }
    @Test func equalsFails() { #expect(!e.evaluate(op: .equals, actual: "1 line", expected: "2 lines")) }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/repositories/autopilot && swift test --filter AssertionEvaluatorTests`
Expected: FAIL — `cannot find 'AssertionEngine' in scope`.

- [ ] **Step 3: Write `AssertionEngine.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Assertions/AssertionEngine.swift`:
```swift
import Foundation
import ApplicationServices

public struct AssertionEngine {
    public init() {}

    /// Pure comparison. `exists`/`notExists` are handled by the runner (element presence),
    /// not here. Numeric ops parse both sides as Double; non-numeric => false.
    public func evaluate(op: AssertOp, actual: String, expected: String) -> Bool {
        switch op {
        case .equals: return actual == expected
        case .notEquals: return actual != expected
        case .contains: return actual.contains(expected)
        case .matches:
            guard let re = try? NSRegularExpression(pattern: expected) else { return false }
            let range = NSRange(actual.startIndex..., in: actual)
            return re.firstMatch(in: actual, range: range) != nil
        case .greaterThan:
            guard let a = Double(actual), let b = Double(expected) else { return false }
            return a > b
        case .lessThan:
            guard let a = Double(actual), let b = Double(expected) else { return false }
            return a < b
        case .exists, .notExists:
            return false // presence handled by runner
        }
    }

    /// Read the requested property of an AX element as a string.
    public func readProperty(_ property: AssertProperty, from element: AXUIElement) -> String? {
        switch property {
        case .value: return AXTree.string(element, kAXValueAttribute as String)
        case .title: return AXTree.string(element, kAXTitleAttribute as String)
        case .enabled: return AXTree.bool(element, kAXEnabledAttribute as String).map { $0 ? "true" : "false" }
        case .focused: return AXTree.bool(element, kAXFocusedAttribute as String).map { $0 ? "true" : "false" }
        case .position:
            guard let f = AXTree.frame(element) else { return nil }
            return "\(Int(f.minX)),\(Int(f.minY))"
        case .size:
            guard let f = AXTree.frame(element) else { return nil }
            return "\(Int(f.width)),\(Int(f.height))"
        case .exists: return "true"
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd ~/repositories/autopilot && swift test --filter AssertionEvaluatorTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: AssertionEngine with pure evaluator + AX property reader"
```

---

### Task 11: Runtime — Permissions, AppLauncher, Screenshot

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Runtime/Permissions.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Runtime/AppLauncher.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Runtime/Screenshot.swift`

These wrap OS facilities; verified by integration tests (Task 13).

- [ ] **Step 1: Write `Permissions.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Runtime/Permissions.swift`:
```swift
import Foundation
import ApplicationServices

public struct Permissions {
    public init() {}

    /// Is the running process trusted for Accessibility control?
    public func hasAccessibility() -> Bool { AXIsProcessTrusted() }

    /// Human-readable instructions for granting AX permission.
    public func accessibilityInstructions() -> String {
        """
        Accessibility permission required.
        Grant it in: System Settings > Privacy & Security > Accessibility,
        then enable the binary running autopilot (or your terminal app).
        """
    }
}
```

- [ ] **Step 2: Write `AppLauncher.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Runtime/AppLauncher.swift`:
```swift
import Foundation
import AppKit

public struct LaunchedApp {
    public let pid: pid_t
    public let runningApp: NSRunningApplication
}

public enum AppLaunchError: Error, CustomStringConvertible {
    case notFound(String)
    case launchFailed(String)
    public var description: String {
        switch self {
        case .notFound(let s): return "App not found: \(s)"
        case .launchFailed(let s): return "Failed to launch: \(s)"
        }
    }
}

public struct AppLauncher {
    public init() {}

    /// Resolve the app URL from a TargetApp (bundleId or explicit path).
    public func resolveURL(_ target: TargetApp) throws -> URL {
        if let path = target.path { return URL(fileURLWithPath: path) }
        if let bundleId = target.bundleId,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return url
        }
        throw AppLaunchError.notFound(target.bundleId ?? target.path ?? "?")
    }

    /// Launch the target app, opening any launchFiles, and return the running app.
    public func launch(_ target: TargetApp) throws -> LaunchedApp {
        let url = try resolveURL(target)
        let config = NSWorkspace.OpenConfiguration()
        if let args = target.launchArgs { config.arguments = args }
        let fileURLs = (target.launchFiles ?? []).map { URL(fileURLWithPath: $0) }

        let sem = DispatchSemaphore(value: 0)
        var result: Result<NSRunningApplication, Error>?
        let completion: (NSRunningApplication?, Error?) -> Void = { app, err in
            if let app { result = .success(app) }
            else { result = .failure(err ?? AppLaunchError.launchFailed(url.path)) }
            sem.signal()
        }
        if fileURLs.isEmpty {
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: completion)
        } else {
            NSWorkspace.shared.open(fileURLs, withApplicationAt: url, configuration: config, completionHandler: completion)
        }
        sem.wait()
        switch result! {
        case .success(let app): return LaunchedApp(pid: app.processIdentifier, runningApp: app)
        case .failure(let err): throw err
        }
    }

    public func terminate(_ app: LaunchedApp) {
        app.runningApp.terminate()
    }
}
```

- [ ] **Step 3: Write `Screenshot.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Runtime/Screenshot.swift`:
```swift
import Foundation
import CoreGraphics
import AppKit

public enum Screenshot {
    /// Capture the full main display to a PNG at `path`. Returns true on success.
    @discardableResult
    public static func captureMainDisplay(to path: String) -> Bool {
        let displayID = CGMainDisplayID()
        guard let image = CGDisplayCreateImage(displayID) else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch { return false }
    }
}
```

- [ ] **Step 4: Build to verify compile**

Run: `cd ~/repositories/autopilot && swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: runtime permissions, app launcher, screenshot"
```

---

### Task 12: Report models + Reporter + Targeting orchestrator + PlanRunner

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Report/Report.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Report/Reporter.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Targeting/Targeting.swift`
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Runner/PlanRunner.swift`
- Test: `~/repositories/autopilot/Tests/AutopilotCoreTests/ReporterTests.swift`

- [ ] **Step 1: Write failing test for Report JSON shape**

Create `~/repositories/autopilot/Tests/AutopilotCoreTests/ReporterTests.swift`:
```swift
import Testing
import Foundation
@testable import AutopilotCore

@Suite struct ReporterTests {
    @Test func encodesReportWithStepResults() throws {
        var report = Report(plan: "smoke")
        report.add(StepResult(id: "s1", result: .pass, durationMs: 12))
        report.add(StepResult(id: "s2", result: .fail, durationMs: 30,
                              expected: "2", actual: "1"))
        report.finalize(permissions: PermissionStatus(accessibility: true, automation: true))

        #expect(report.result == .fail) // any fail => overall fail
        let data = try JSONEncoder().encode(report)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["result"] as? String == "fail")
        let steps = obj["steps"] as! [[String: Any]]
        #expect(steps.count == 2)
        #expect(steps[1]["actual"] as? String == "1")
    }

    @Test func allPassYieldsPass() throws {
        var report = Report(plan: "p")
        report.add(StepResult(id: "a", result: .pass, durationMs: 1))
        report.finalize(permissions: PermissionStatus(accessibility: true, automation: true))
        #expect(report.result == .pass)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/repositories/autopilot && swift test --filter ReporterTests`
Expected: FAIL — `cannot find 'Report' in scope`.

- [ ] **Step 3: Write `Report.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Report/Report.swift`:
```swift
import Foundation

public enum StepOutcome: String, Codable, Sendable { case pass, fail, error, skipped }

public struct StepResult: Codable, Sendable {
    public var id: String
    public var result: StepOutcome
    public var durationMs: Int
    public var expected: String?
    public var actual: String?
    public var message: String?
    public var screenshot: String?
    public var axDump: String?
    public init(id: String, result: StepOutcome, durationMs: Int,
                expected: String? = nil, actual: String? = nil, message: String? = nil,
                screenshot: String? = nil, axDump: String? = nil) {
        self.id = id; self.result = result; self.durationMs = durationMs
        self.expected = expected; self.actual = actual; self.message = message
        self.screenshot = screenshot; self.axDump = axDump
    }
}

public struct PermissionStatus: Codable, Sendable {
    public var accessibility: Bool
    public var automation: Bool
    public init(accessibility: Bool, automation: Bool) {
        self.accessibility = accessibility; self.automation = automation
    }
}

public struct Report: Codable, Sendable {
    public var plan: String
    public var result: StepOutcome
    public var durationMs: Int
    public var steps: [StepResult]
    public var permissions: PermissionStatus?

    public init(plan: String) {
        self.plan = plan; self.result = .pass; self.durationMs = 0
        self.steps = []; self.permissions = nil
    }

    public mutating func add(_ step: StepResult) { steps.append(step) }

    /// Compute overall result (any fail/error => that) and total duration.
    public mutating func finalize(permissions: PermissionStatus) {
        self.permissions = permissions
        durationMs = steps.reduce(0) { $0 + $1.durationMs }
        if steps.contains(where: { $0.result == .error }) { result = .error }
        else if steps.contains(where: { $0.result == .fail }) { result = .fail }
        else { result = .pass }
    }
}
```

- [ ] **Step 4: Write `Reporter.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Report/Reporter.swift`:
```swift
import Foundation

public struct Reporter {
    public init() {}

    /// Encode the report as pretty JSON.
    public func json(_ report: Report) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(report)
    }

    /// Write report.json into `directory`, creating it if needed. Returns the file URL.
    @discardableResult
    public func write(_ report: Report, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("report.json")
        try json(report).write(to: url)
        return url
    }

    /// One-line-per-step human summary for stdout.
    public func humanSummary(_ report: Report) -> String {
        var lines = ["Plan: \(report.plan)  =>  \(report.result.rawValue.uppercased())  (\(report.durationMs)ms)"]
        for s in report.steps {
            var line = "  [\(s.result.rawValue)] \(s.id) (\(s.durationMs)ms)"
            if s.result == .fail, let e = s.expected, let a = s.actual {
                line += "  expected=\(e) actual=\(a)"
            }
            if let m = s.message { line += "  \(m)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 5: Write `Targeting.swift` (orchestrates AX then vision; vision is a stub until Phase 6)**

Create `~/repositories/autopilot/Sources/AutopilotCore/Targeting/Targeting.swift`:
```swift
import Foundation
import ApplicationServices

/// Orchestrates element resolution: AX first, vision fallback (Phase 6),
/// with poll-until-resolvable semantics driven by the Poller.
public struct Targeting {
    let axResolver = AXResolver()
    let poller: Poller
    public init(poller: Poller = Poller()) { self.poller = poller }

    /// Resolve a selector to exactly one element, polling until available or timeout.
    public func resolve(_ selector: Selector, app: AXUIElement,
                        timeoutMs: Int, intervalMs: Int) throws -> ElementRef {
        var lastError: Error = TargetingError.timedOut(
            selector: AXResolver.describe(selector), timeoutMs: timeoutMs)
        let ok = poller.waitUntil(timeoutMs: timeoutMs, intervalMs: intervalMs) {
            do { _ = try axResolver.resolveOne(in: app, selector: selector); return true }
            catch { lastError = error; return false }
        }
        guard ok else {
            // Vision fallback hook (Phase 6) goes here. For now, surface the AX error.
            throw lastError
        }
        let el = try axResolver.resolveOne(in: app, selector: selector)
        return .ax(el)
    }

    /// Wait for an element to be present (or absent). Returns whether the wait succeeded.
    public func waitForPresence(_ selector: Selector, present: Bool, app: AXUIElement,
                                timeoutMs: Int, intervalMs: Int) -> Bool {
        poller.waitUntil(timeoutMs: timeoutMs, intervalMs: intervalMs) {
            (axResolver.count(in: app, selector: selector) > 0) == present
        }
    }
}
```

- [ ] **Step 6: Write `PlanRunner.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Runner/PlanRunner.swift`:
```swift
import Foundation
import ApplicationServices

public struct RunOptions {
    public var keepGoing: Bool
    public var artifactsDir: URL
    public init(keepGoing: Bool = false, artifactsDir: URL) {
        self.keepGoing = keepGoing; self.artifactsDir = artifactsDir
    }
}

public struct PlanRunner {
    let clock: Clock
    let permissions = Permissions()
    let launcher = AppLauncher()
    let actions = ActionEngine()
    let assertions = AssertionEngine()
    let reporter = Reporter()

    public init(clock: Clock = SystemClock()) { self.clock = clock }

    /// Parse-and-run is the caller's job for include base-dir reasons; this takes a resolved Plan.
    public func run(_ plan: Plan, options: RunOptions) throws -> Report {
        var report = Report(plan: plan.name)
        let hasAX = permissions.hasAccessibility()
        let perm = PermissionStatus(accessibility: hasAX, automation: true)

        guard hasAX else {
            report.add(StepResult(id: "_preflight", result: .error, durationMs: 0,
                                  message: permissions.accessibilityInstructions()))
            report.finalize(permissions: perm)
            return report
        }

        let defaults = plan.defaults
        let timeoutMs = defaults?.timeoutMs ?? 5000
        let intervalMs = defaults?.retryIntervalMs ?? 100
        let targeting = Targeting(poller: Poller(clock: clock))

        let launched = try launcher.launch(plan.target)
        defer { /* leave app running unless a terminate step ran; harmless for tests */ }
        let appElement = AXTree.application(pid: launched.pid)
        // Give the app a beat to register its AX tree (polled, not a fixed sleep).
        _ = targeting.waitForPresence(Selector(role: "AXWindow"), present: true,
                                      app: appElement, timeoutMs: timeoutMs, intervalMs: intervalMs)

        for step in plan.steps {
            let stepTimeout = step.timeoutMs ?? timeoutMs
            let start = clock.now()
            do {
                let result = try runStep(step, app: appElement, launched: launched,
                                         targeting: targeting, timeoutMs: stepTimeout,
                                         intervalMs: intervalMs, options: options)
                let dur = Int((clock.now() - start) * 1000)
                var r = result; r.durationMs = dur
                report.add(r)
                if r.result != .pass && !options.keepGoing { break }
            } catch {
                let dur = Int((clock.now() - start) * 1000)
                let dump = writeAXDump(appElement, stepId: step.id, dir: options.artifactsDir)
                let shot = options.artifactsDir.appendingPathComponent("\(step.id).png").path
                Screenshot.captureMainDisplay(to: shot)
                report.add(StepResult(id: step.id, result: .error, durationMs: dur,
                                      message: String(describing: error),
                                      screenshot: shot, axDump: dump))
                if !options.keepGoing { break }
            }
        }
        report.finalize(permissions: perm)
        return report
    }

    private func runStep(_ step: Step, app: AXUIElement, launched: LaunchedApp,
                         targeting: Targeting, timeoutMs: Int, intervalMs: Int,
                         options: RunOptions) throws -> StepResult {
        switch step.action {
        case .launch:
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        case .terminate:
            launcher.terminate(launched)
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        case .wait:
            clock.sleep(step.args?.seconds ?? 0)
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        case .screenshot:
            let path = step.args?.path ?? options.artifactsDir.appendingPathComponent("\(step.id).png").path
            let ok = Screenshot.captureMainDisplay(to: path)
            return StepResult(id: step.id, result: ok ? .pass : .fail, durationMs: 0,
                              screenshot: path)
        case .waitFor:
            let present = step.args?.present ?? true
            let ok = targeting.waitForPresence(step.target!, present: present, app: app,
                                               timeoutMs: timeoutMs, intervalMs: intervalMs)
            return StepResult(id: step.id, result: ok ? .pass : .fail, durationMs: 0,
                              message: ok ? nil : "element \(present ? "did not appear" : "did not disappear")")
        case .assert:
            return try runAssert(step, app: app, targeting: targeting,
                                 timeoutMs: timeoutMs, intervalMs: intervalMs, options: options)
        case .click, .doubleClick, .rightClick, .type, .keyPress, .setValue, .scroll:
            let ref = try targeting.resolve(step.target!, app: app,
                                            timeoutMs: timeoutMs, intervalMs: intervalMs)
            try actions.perform(action: step.action, args: step.args, ref: ref)
            return StepResult(id: step.id, result: .pass, durationMs: 0)
        }
    }

    private func runAssert(_ step: Step, app: AXUIElement, targeting: Targeting,
                           timeoutMs: Int, intervalMs: Int, options: RunOptions) throws -> StepResult {
        let assertion = step.assert!
        // exists / notExists assert on presence, not property value.
        if assertion.op == .exists || assertion.op == .notExists {
            let present = assertion.op == .exists
            let ok = targeting.waitForPresence(step.target!, present: present, app: app,
                                               timeoutMs: timeoutMs, intervalMs: intervalMs)
            return StepResult(id: step.id, result: ok ? .pass : .fail, durationMs: 0,
                              expected: present ? "exists" : "notExists",
                              actual: ok ? (present ? "exists" : "notExists") : (present ? "notExists" : "exists"))
        }
        guard case .ax(let el) = try targeting.resolve(step.target!, app: app,
                                                       timeoutMs: timeoutMs, intervalMs: intervalMs) else {
            return StepResult(id: step.id, result: .fail, durationMs: 0,
                              message: "cannot assert property on vision-only element")
        }
        let actual = assertions.readProperty(assertion.property, from: el) ?? ""
        let expected = assertion.expected ?? ""
        let ok = assertions.evaluate(op: assertion.op, actual: actual, expected: expected)
        var result = StepResult(id: step.id, result: ok ? .pass : .fail, durationMs: 0,
                                expected: expected, actual: actual)
        if !ok {
            let dump = writeAXDump(app, stepId: step.id, dir: options.artifactsDir)
            let shot = options.artifactsDir.appendingPathComponent("\(step.id).png").path
            Screenshot.captureMainDisplay(to: shot)
            result.axDump = dump; result.screenshot = shot
        }
        return result
    }

    private func writeAXDump(_ app: AXUIElement, stepId: String, dir: URL) -> String? {
        let snap = AXTree.snapshot(app)
        let url = dir.appendingPathComponent("\(stepId).axtree.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: snap, options: [.prettyPrinted])
            try data.write(to: url)
            return url.path
        } catch { return nil }
    }
}
```

- [ ] **Step 7: Run to verify ReporterTests pass**

Run: `cd ~/repositories/autopilot && swift test --filter ReporterTests`
Expected: PASS (2 tests).

- [ ] **Step 8: Build the whole package**

Run: `cd ~/repositories/autopilot && swift build`
Expected: `Build complete!`

- [ ] **Step 9: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: Report, Reporter, Targeting orchestrator, PlanRunner"
```

---

### Task 13: End-to-end integration test against TestHostApp

**Files:**
- Create: `~/repositories/autopilot/Tests/AutopilotCoreTests/IntegrationTests.swift`

This test is **environment-gated**: it requires Accessibility permission and a GUI session. It builds TestHostApp, runs a real plan, and asserts the report. It skips (not fails) when AX permission is absent, so CI without the grant stays green.

- [ ] **Step 1: Write the integration test**

Create `~/repositories/autopilot/Tests/AutopilotCoreTests/IntegrationTests.swift`:
```swift
import Testing
import Foundation
import ApplicationServices
@testable import AutopilotCore

@Suite struct IntegrationTests {
    /// Path to the built TestHostApp executable.
    func testHostAppBinary() -> URL {
        // Resolves relative to the package root when run via `swift test`.
        let pkgRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AutopilotCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
        return pkgRoot
            .appendingPathComponent("Fixtures/TestHostApp/.build/debug/TestHostApp")
    }

    @Test func typeUpdatesStatusLabel() async throws {
        guard AXIsProcessTrusted() else {
            // Skip when no AX permission; do not fail CI.
            return
        }
        let binary = testHostAppBinary()
        guard FileManager.default.fileExists(atPath: binary.path) else {
            Issue.record("TestHostApp not built. Run: (cd Fixtures/TestHostApp && swift build)")
            return
        }

        let artifacts = FileManager.default.temporaryDirectory
            .appendingPathComponent("autopilot-it-\(UUID().uuidString)")
        let plan = Plan(
            schemaVersion: "1.0",
            name: "host: type updates status",
            target: TargetApp(path: binary.path),
            defaults: PlanDefaults(timeoutMs: 4000, retryIntervalMs: 100),
            steps: [
                Step(id: "type-name", action: .type,
                     target: Selector(role: "AXTextField", identifier: "nameField"),
                     args: { var a = ActionArgs(); a.text = "Ada"; return a }()),
                Step(id: "assert-status", action: .assert,
                     target: Selector(identifier: "statusLabel"),
                     assert: Assertion(property: .value, op: .contains, expected: "Ada")),
            ]
        )
        let runner = PlanRunner()
        let report = try runner.run(plan, options: RunOptions(artifactsDir: artifacts))
        #expect(report.result == .pass, "report: \(Reporter().humanSummary(report))")
    }
}
```

- [ ] **Step 2: Build TestHostApp so the integration test can find it**

Run: `cd ~/repositories/autopilot/Fixtures/TestHostApp && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Run the integration test**

Run: `cd ~/repositories/autopilot && swift test --filter IntegrationTests`
Expected: PASS if AX permission is granted to the test runner; the test self-skips (still reported as passed/no-failure) if not. If it skips, grant Accessibility to your terminal and re-run to truly exercise it.

- [ ] **Step 4: Run the full suite**

Run: `cd ~/repositories/autopilot && swift test`
Expected: All suites PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "test: end-to-end integration test against TestHostApp"
```

---

## Phase 4 — CLI front-end

### Task 14: `autopilot run` command

**Files:**
- Modify: `~/repositories/autopilot/Sources/autopilot/main.swift` (replace stub)

The CLI is a thin wrapper: parse args, read the plan file, run it, write report, set exit code. Distinct exit codes: `0` pass, `1` test failure, `2` plan/parse error, `3` permission problem.

- [ ] **Step 1: Replace `main.swift` with the ArgumentParser command**

Replace `~/repositories/autopilot/Sources/autopilot/main.swift`:
```swift
import Foundation
import ArgumentParser
import AutopilotCore

struct Autopilot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "autopilot",
        abstract: "Run a declarative GUI test plan against a macOS app.",
        subcommands: [Run.self, Doctor.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Execute a plan JSON file.")

    @Argument(help: "Path to the plan JSON file.")
    var planPath: String

    @Option(name: .long, help: "Directory for report.json and failure artifacts.")
    var artifacts: String = "artifacts"

    @Flag(name: .long, help: "Continue after a failing step instead of stopping.")
    var keepGoing: Bool = false

    @Flag(name: .long, help: "Print report.json to stdout instead of the human summary.")
    var json: Bool = false

    func run() throws {
        let planURL = URL(fileURLWithPath: planPath)
        let baseDir = planURL.deletingLastPathComponent()
        let data: Data
        do { data = try Data(contentsOf: planURL) }
        catch { FileHandle.standardError.write(Data("Cannot read plan: \(planPath)\n".utf8)); throw ExitCode(2) }

        let plan: Plan
        do { plan = try PlanParser().parse(data: data, baseDirectory: baseDir) }
        catch {
            FileHandle.standardError.write(Data("Plan error: \(error)\n".utf8))
            throw ExitCode(2)
        }

        let artifactsURL = URL(fileURLWithPath: artifacts)
        let report = try PlanRunner().run(plan, options: RunOptions(keepGoing: keepGoing, artifactsDir: artifactsURL))
        let reporter = Reporter()
        try reporter.write(report, to: artifactsURL)

        if json {
            FileHandle.standardOutput.write(try reporter.json(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            print(reporter.humanSummary(report))
        }

        // Distinct exit codes.
        if report.permissions?.accessibility == false { throw ExitCode(3) }
        switch report.result {
        case .pass, .skipped: return
        case .fail: throw ExitCode(1)
        case .error: throw ExitCode(1)
        }
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check required permissions.")
    func run() throws {
        let perms = Permissions()
        if perms.hasAccessibility() {
            print("Accessibility: OK")
        } else {
            print("Accessibility: MISSING")
            print(perms.accessibilityInstructions())
            throw ExitCode(3)
        }
    }
}

Autopilot.main()
```

- [ ] **Step 2: Build the CLI**

Run: `cd ~/repositories/autopilot && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Smoke-test `doctor` and a bad plan path**

Run:
```bash
cd ~/repositories/autopilot
swift run autopilot doctor || echo "exit=$?"
swift run autopilot run /nonexistent.json || echo "exit=$?"
```
Expected: `doctor` prints Accessibility status; bad path prints "Cannot read plan" and `exit=2`.

- [ ] **Step 4: Write a sample plan and run it end-to-end (requires AX grant + TestHostApp built)**

Run:
```bash
cd ~/repositories/autopilot
cat > /tmp/host-smoke.json <<'JSON'
{
  "schemaVersion": "1.0",
  "name": "host smoke via CLI",
  "target": { "path": "FIXTURE_BIN" },
  "defaults": { "timeoutMs": 4000, "retryIntervalMs": 100 },
  "steps": [
    { "id": "click-ok", "action": "click", "target": { "identifier": "okButton" } },
    { "id": "assert-count", "action": "assert", "target": { "identifier": "countLabel" },
      "assert": { "property": "value", "op": "contains", "expected": "count: 1" } }
  ]
}
JSON
# substitute the built fixture path
sed -i '' "s#FIXTURE_BIN#$PWD/Fixtures/TestHostApp/.build/debug/TestHostApp#" /tmp/host-smoke.json
swift run autopilot run /tmp/host-smoke.json --artifacts /tmp/autopilot-artifacts
echo "exit=$?"
```
Expected: human summary shows both steps `pass` and `exit=0` (if AX granted). If permission missing, `exit=3` with grant instructions.

- [ ] **Step 5: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: autopilot CLI (run + doctor, distinct exit codes)"
```

---

## Phase 5 — MCP server front-end

### Task 15: MCP server over the shared core

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotMCP/MCPServer.swift`
- Modify: `~/repositories/autopilot/Sources/AutopilotMCP/main.swift` (replace stub)

A minimal stdio JSON-RPC 2.0 MCP server exposing three tools: `run_plan` (inline plan object or path), `get_report` (re-read last report), `dump_axtree` (snapshot a running app for authoring). No external MCP SDK dependency — the protocol surface needed is small and hand-rolled to keep the dependency tree minimal.

- [ ] **Step 1: Write `MCPServer.swift`**

Create `~/repositories/autopilot/Sources/AutopilotMCP/MCPServer.swift`:
```swift
import Foundation
import AutopilotCore

/// Minimal MCP (JSON-RPC 2.0 over stdio) server exposing autopilot tools.
final class MCPServer {
    let reporter = Reporter()
    var lastReport: Report?

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            handle(msg)
        }
    }

    func handle(_ msg: [String: Any]) {
        let id = msg["id"]
        guard let method = msg["method"] as? String else { return }
        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "autopilot", "version": "1.0.0"]
            ])
        case "tools/list":
            respond(id: id, result: ["tools": Self.toolDefinitions])
        case "tools/call":
            handleToolCall(id: id, params: msg["params"] as? [String: Any] ?? [:])
        default:
            respond(id: id, error: ["code": -32601, "message": "Method not found: \(method)"])
        }
    }

    func handleToolCall(id: Any?, params: [String: Any]) {
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        switch name {
        case "run_plan": runPlan(id: id, args: args)
        case "get_report": getReport(id: id)
        case "dump_axtree": dumpAXTree(id: id, args: args)
        default: respond(id: id, error: ["code": -32602, "message": "Unknown tool: \(name)"])
        }
    }

    func runPlan(id: Any?, args: [String: Any]) {
        do {
            let data: Data
            let baseDir: URL
            if let path = args["path"] as? String {
                let url = URL(fileURLWithPath: path)
                data = try Data(contentsOf: url); baseDir = url.deletingLastPathComponent()
            } else if let planObj = args["plan"] {
                data = try JSONSerialization.data(withJSONObject: planObj)
                baseDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            } else {
                respond(id: id, error: ["code": -32602, "message": "run_plan needs 'plan' or 'path'"]); return
            }
            let plan = try PlanParser().parse(data: data, baseDirectory: baseDir)
            let artifacts = URL(fileURLWithPath: (args["artifactsDir"] as? String) ?? "artifacts")
            let keepGoing = (args["keepGoing"] as? Bool) ?? false
            let report = try PlanRunner().run(plan, options: RunOptions(keepGoing: keepGoing, artifactsDir: artifacts))
            lastReport = report
            let jsonText = String(data: try reporter.json(report), encoding: .utf8) ?? "{}"
            respondToolText(id: id, text: jsonText)
        } catch {
            respond(id: id, error: ["code": -32603, "message": String(describing: error)])
        }
    }

    func getReport(id: Any?) {
        guard let report = lastReport, let text = try? reporter.json(report),
              let s = String(data: text, encoding: .utf8) else {
            respond(id: id, error: ["code": -32603, "message": "No report yet"]); return
        }
        respondToolText(id: id, text: s)
    }

    func dumpAXTree(id: Any?, args: [String: Any]) {
        // Authoring aid: launch (or attach) and dump the snapshot.
        guard let bundleId = args["bundleId"] as? String ?? (args["path"] as? String) else {
            respond(id: id, error: ["code": -32602, "message": "dump_axtree needs bundleId or path"]); return
        }
        do {
            let target = args["path"] != nil ? TargetApp(path: bundleId) : TargetApp(bundleId: bundleId)
            let launched = try AppLauncher().launch(target)
            let app = AXTree.application(pid: launched.pid)
            // brief settle, polled via a window check
            _ = Targeting().waitForPresence(Selector(role: "AXWindow"), present: true, app: app, timeoutMs: 4000, intervalMs: 100)
            let snap = AXTree.snapshot(app)
            let data = try JSONSerialization.data(withJSONObject: snap, options: [.prettyPrinted])
            respondToolText(id: id, text: String(data: data, encoding: .utf8) ?? "[]")
        } catch {
            respond(id: id, error: ["code": -32603, "message": String(describing: error)])
        }
    }

    // MARK: - JSON-RPC plumbing

    static let toolDefinitions: [[String: Any]] = [
        ["name": "run_plan",
         "description": "Run a GUI test plan (inline 'plan' object or 'path' to JSON). Returns report JSON.",
         "inputSchema": ["type": "object", "properties": [
            "plan": ["type": "object"], "path": ["type": "string"],
            "artifactsDir": ["type": "string"], "keepGoing": ["type": "boolean"]]]],
        ["name": "get_report",
         "description": "Return the JSON report from the most recent run_plan.",
         "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "dump_axtree",
         "description": "Launch an app (bundleId or path) and dump its accessibility tree to help author selectors.",
         "inputSchema": ["type": "object", "properties": [
            "bundleId": ["type": "string"], "path": ["type": "string"]]]],
    ]

    func respondToolText(id: Any?, text: String) {
        respond(id: id, result: ["content": [["type": "text", "text": text]]])
    }

    func respond(id: Any?, result: [String: Any]) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { msg["id"] = id }
        emit(msg)
    }

    func respond(id: Any?, error: [String: Any]) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "error": error]
        if let id { msg["id"] = id }
        emit(msg)
    }

    func emit(_ msg: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
```

- [ ] **Step 2: Replace `main.swift`**

Replace `~/repositories/autopilot/Sources/AutopilotMCP/main.swift`:
```swift
import Foundation

MCPServer().run()
```

- [ ] **Step 3: Build**

Run: `cd ~/repositories/autopilot && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Smoke-test the JSON-RPC handshake via stdin**

Run:
```bash
cd ~/repositories/autopilot
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | swift run AutopilotMCP
```
Expected: two JSON lines — an `initialize` result advertising serverInfo `autopilot`, and a `tools/list` result listing `run_plan`, `get_report`, `dump_axtree`.

- [ ] **Step 5: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: MCP server (run_plan, get_report, dump_axtree)"
```

---

## Phase 6 — Vision fallback + medit integration

### Task 16: VisionResolver (deterministic template match)

**Files:**
- Create: `~/repositories/autopilot/Sources/AutopilotCore/Targeting/VisionResolver.swift`
- Modify: `~/repositories/autopilot/Sources/AutopilotCore/Targeting/Targeting.swift` (wire fallback into `resolve`)
- Test: `~/repositories/autopilot/Tests/AutopilotCoreTests/SelectorResolutionTests.swift` (extend with a synthetic-image match test)

Uses Vision's `VNImageRegistrationRequest`-free approach: a straightforward normalized
cross-correlation over CoreGraphics bitmaps. Deterministic — fixed threshold, no LLM. The
core correlation function is pure and unit-tested on synthetic bitmaps; live screen capture
is exercised manually.

- [ ] **Step 1: Write the failing test for the pure correlation matcher**

Append to `~/repositories/autopilot/Tests/AutopilotCoreTests/SelectorResolutionTests.swift`:
```swift
@Suite struct VisionMatchTests {
    /// Build a grayscale buffer (row-major, 0...1) of given size with a bright square.
    func buffer(width: Int, height: Int, square: (x: Int, y: Int, size: Int)?) -> [[Double]] {
        var rows = Array(repeating: Array(repeating: 0.0, count: width), count: height)
        if let sq = square {
            for y in sq.y..<(sq.y + sq.size) where y < height {
                for x in sq.x..<(sq.x + sq.size) where x < width {
                    rows[y][x] = 1.0
                }
            }
        }
        return rows
    }

    @Test func findsTemplateLocation() {
        let haystack = buffer(width: 20, height: 20, square: (x: 5, y: 7, size: 4))
        let needle = buffer(width: 4, height: 4, square: (x: 0, y: 0, size: 4))
        let match = VisionResolver.bestMatch(haystack: haystack, needle: needle)
        #expect(match != nil)
        #expect(match!.x == 5)
        #expect(match!.y == 7)
        #expect(match!.score > 0.99)
    }

    @Test func reportsLowScoreWhenAbsent() {
        let haystack = buffer(width: 20, height: 20, square: nil)
        let needle = buffer(width: 4, height: 4, square: (x: 0, y: 0, size: 4))
        let match = VisionResolver.bestMatch(haystack: haystack, needle: needle)
        // all-zero haystack vs bright needle => correlation undefined/low; treated as nil-ish
        #expect(match == nil || match!.score < 0.5)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/repositories/autopilot && swift test --filter VisionMatchTests`
Expected: FAIL — `cannot find 'VisionResolver' in scope`.

- [ ] **Step 3: Write `VisionResolver.swift`**

Create `~/repositories/autopilot/Sources/AutopilotCore/Targeting/VisionResolver.swift`:
```swift
import Foundation
import CoreGraphics
import AppKit

/// Deterministic template matching via normalized cross-correlation.
/// No LLM, no semantic reasoning — a fixed-threshold pixel match returning a point.
public enum VisionResolver {
    public struct Match { public var x: Int; public var y: Int; public var score: Double }

    /// Pure NCC over grayscale buffers. Returns the best top-left match, or nil
    /// if the correlation is undefined (e.g. zero-variance window).
    public static func bestMatch(haystack: [[Double]], needle: [[Double]]) -> Match? {
        let H = haystack.count, W = haystack.first?.count ?? 0
        let h = needle.count, w = needle.first?.count ?? 0
        guard H >= h, W >= w, h > 0, w > 0 else { return nil }

        // Precompute needle mean/variance.
        var nSum = 0.0
        for row in needle { for v in row { nSum += v } }
        let nMean = nSum / Double(h * w)
        var nVar = 0.0
        for row in needle { for v in row { nVar += (v - nMean) * (v - nMean) } }
        guard nVar > 0 else { return nil }

        var best: Match? = nil
        for oy in 0...(H - h) {
            for ox in 0...(W - w) {
                var wSum = 0.0
                for y in 0..<h { for x in 0..<w { wSum += haystack[oy + y][ox + x] } }
                let wMean = wSum / Double(h * w)
                var cov = 0.0, wVar = 0.0
                for y in 0..<h {
                    for x in 0..<w {
                        let a = haystack[oy + y][ox + x] - wMean
                        let b = needle[y][x] - nMean
                        cov += a * b
                        wVar += a * a
                    }
                }
                guard wVar > 0 else { continue }
                let score = cov / (wVar.squareRoot() * nVar.squareRoot())
                if best == nil || score > best!.score {
                    best = Match(x: ox, y: oy, score: score)
                }
            }
        }
        return best
    }

    /// Load a PNG file into a grayscale buffer (0...1).
    public static func grayscaleBuffer(pngPath: String) -> [[Double]]? {
        guard let img = NSImage(contentsOfFile: pngPath),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return grayscale(from: cg)
    }

    static func grayscale(from cg: CGImage) -> [[Double]]? {
        let width = cg.width, height = cg.height
        let cs = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var rows = Array(repeating: Array(repeating: 0.0, count: width), count: height)
        for y in 0..<height { for x in 0..<width { rows[y][x] = Double(pixels[y * width + x]) / 255.0 } }
        return rows
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd ~/repositories/autopilot && swift test --filter VisionMatchTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire the fallback into `Targeting.resolve`**

In `~/repositories/autopilot/Sources/AutopilotCore/Targeting/Targeting.swift`, replace the `guard ok else { ... throw lastError }` block inside `resolve(...)` with:
```swift
        guard ok else {
            // Vision fallback: only if the selector carries a vision block.
            if let vision = selector.vision {
                let shotPath = NSTemporaryDirectory() + "autopilot-vision-\(UUID().uuidString).png"
                guard Screenshot.captureMainDisplay(to: shotPath),
                      let haystack = VisionResolver.grayscaleBuffer(pngPath: shotPath),
                      let needle = VisionResolver.grayscaleBuffer(pngPath: vision.image),
                      let match = VisionResolver.bestMatch(haystack: haystack, needle: needle),
                      match.score >= vision.confidence
                else { throw lastError }
                // Template top-left + half needle size => approximate center, in pixel coords.
                let nW = (needle.first?.count ?? 0), nH = needle.count
                return .point(CGPoint(x: match.x + nW / 2, y: match.y + nH / 2))
            }
            throw lastError
        }
```

Add `import AppKit` at the top of `Targeting.swift` if not already present (needed for `NSTemporaryDirectory`/`Screenshot`).

- [ ] **Step 6: Build + full suite**

Run: `cd ~/repositories/autopilot && swift build && swift test`
Expected: `Build complete!` and all suites PASS.

- [ ] **Step 7: Commit**

```bash
cd ~/repositories/autopilot
git add -A
git commit -m "feat: deterministic vision fallback (NCC template match)"
```

---

### Task 17: medit — add AX identifiers to key controls

**Files (in the `medit` repo):**
- Modify: `~/repositories/medit/Sources/MeditKit/EditorViewController.swift` (editor text view identifier)
- Modify: `~/repositories/medit/Sources/MeditKit/StatusBarView.swift` (line/column labels)
- Modify: `~/repositories/medit/Sources/MeditKit/FindReplaceBar.swift` (find/replace fields)
- Modify: `~/repositories/medit/Sources/MeditKit/SidebarViewController.swift` (sidebar outline)
- Modify: `~/repositories/medit/Sources/MeditKit/GoToLineSheet.swift` (go-to-line field)
- Modify: `~/repositories/medit/Sources/MeditKit/ReloadBanner.swift` (reload banner buttons)

Each control gets a stable `setAccessibilityIdentifier(...)`. The exact view/property to tag must be confirmed by reading each file first; the identifiers to assign are fixed below.

- [ ] **Step 1: Read the six files to locate each control**

Run:
```bash
cd ~/repositories/medit
for f in EditorViewController StatusBarView FindReplaceBar SidebarViewController GoToLineSheet ReloadBanner; do
  echo "=== $f ==="; grep -nE 'NSTextField|NSTextView|NSButton|NSOutlineView|class |func ' "Sources/MeditKit/$f.swift" | head -20
done
```
Expected: prints the control declarations to tag. Use this to find the right insertion point for each identifier below.

- [ ] **Step 2: Assign these exact identifiers (one per control)**

After each control is created/loaded (e.g. in `viewDidLoad`/`awakeFromNib`/init), add:
```swift
// EditorViewController — the main text view:
textView.setAccessibilityIdentifier("editorTextView")

// StatusBarView — line/column labels:
lineLabel.setAccessibilityIdentifier("lineCountLabel")
columnLabel.setAccessibilityIdentifier("columnLabel")

// FindReplaceBar — search + replace fields:
findField.setAccessibilityIdentifier("findField")
replaceField.setAccessibilityIdentifier("replaceField")

// SidebarViewController — the file outline:
outlineView.setAccessibilityIdentifier("sidebarOutline")

// GoToLineSheet — the line-number input:
lineNumberField.setAccessibilityIdentifier("goToLineField")

// ReloadBanner — the reload + dismiss buttons:
reloadButton.setAccessibilityIdentifier("reloadButton")
dismissButton.setAccessibilityIdentifier("dismissReloadButton")
```
Use the actual property names found in Step 1 (the left-hand identifiers above are the new AX ids, not necessarily the Swift variable names). If a property name differs, tag the corresponding control with the AX id shown.

- [ ] **Step 3: Build medit to confirm it still compiles**

Run: `cd ~/repositories/medit && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Run medit's existing unit tests (no regression)**

Run: `cd ~/repositories/medit && swift test`
Expected: All existing `MeditKitTests` PASS.

- [ ] **Step 5: Commit (in the medit repo)**

```bash
cd ~/repositories/medit
git add Sources/MeditKit
git commit -m "test: add accessibility identifiers for autopilot GUI tests"
```

---

### Task 18: medit — starter autopilot plan suite + reset-state

**Files (in the `medit` repo):**
- Create: `~/repositories/medit/uitests/setups/launch.json`
- Create: `~/repositories/medit/uitests/open-and-type.json`
- Create: `~/repositories/medit/uitests/find-replace.json`
- Create: `~/repositories/medit/uitests/README.md`
- Modify: `~/repositories/medit/App/main.swift` (honor a `--reset-state` arg)

- [ ] **Step 1: Add `--reset-state` handling to medit's entry point**

Read `~/repositories/medit/App/main.swift`, then add near the top of app startup:
```swift
// Test hook: start from a clean preferences/state baseline when launched by autopilot.
if CommandLine.arguments.contains("--reset-state") {
    if let domain = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}
```
(Place it before the app reads preferences. If `medit` already centralizes startup in `AppDelegate`, put it in `applicationWillFinishLaunching` instead — confirm by reading the file.)

- [ ] **Step 2: Write the reusable launch setup plan**

Create `~/repositories/medit/uitests/setups/launch.json`:
```json
{
  "schemaVersion": "1.0",
  "name": "launch medit clean",
  "target": {
    "bundleId": "com.jschwefel.medit",
    "launchArgs": ["--reset-state"]
  },
  "defaults": { "timeoutMs": 6000, "retryIntervalMs": 100 },
  "steps": [
    { "id": "wait-window", "action": "waitFor",
      "target": { "role": "AXWindow" }, "args": { "present": true } }
  ]
}
```

- [ ] **Step 3: Write the open-and-type plan (uses include)**

Create `~/repositories/medit/uitests/open-and-type.json`:
```json
{
  "schemaVersion": "1.0",
  "name": "type text into editor",
  "include": ["setups/launch.json"],
  "target": {
    "bundleId": "com.jschwefel.medit",
    "launchArgs": ["--reset-state"]
  },
  "defaults": { "timeoutMs": 6000, "retryIntervalMs": 100 },
  "steps": [
    { "id": "type", "action": "type",
      "target": { "role": "AXTextArea", "identifier": "editorTextView" },
      "args": { "text": "hello\nworld" } },
    { "id": "assert-line-count", "action": "assert",
      "target": { "identifier": "lineCountLabel" },
      "assert": { "property": "value", "op": "contains", "expected": "2" } }
  ]
}
```

- [ ] **Step 4: Write the find/replace plan**

Create `~/repositories/medit/uitests/find-replace.json`:
```json
{
  "schemaVersion": "1.0",
  "name": "find bar opens and accepts input",
  "include": ["setups/launch.json"],
  "target": {
    "bundleId": "com.jschwefel.medit",
    "launchArgs": ["--reset-state"]
  },
  "defaults": { "timeoutMs": 6000, "retryIntervalMs": 100 },
  "steps": [
    { "id": "type-body", "action": "type",
      "target": { "identifier": "editorTextView" },
      "args": { "text": "alpha beta alpha" } },
    { "id": "open-find", "action": "keyPress",
      "target": { "identifier": "editorTextView" },
      "args": { "keys": "cmd+f" } },
    { "id": "find-field-exists", "action": "assert",
      "target": { "identifier": "findField" },
      "assert": { "property": "exists", "op": "exists" } },
    { "id": "type-query", "action": "type",
      "target": { "identifier": "findField" },
      "args": { "text": "alpha" } }
  ]
}
```

- [ ] **Step 5: Write the suite README**

Create `~/repositories/medit/uitests/README.md`:
```markdown
# medit GUI tests (autopilot)

These are declarative GUI test plans executed by `autopilot`
(`~/repositories/autopilot`). They drive the built medit app via the
macOS Accessibility API.

## Prerequisites
- Build autopilot: `(cd ~/repositories/autopilot && swift build)`
- Grant Accessibility permission to the terminal/binary running autopilot
  (`autopilot doctor` checks this).
- medit must be installed or its built binary path supplied via the plan `target`.

## Run a plan
```bash
~/repositories/autopilot/.build/debug/autopilot run \
  ~/repositories/medit/uitests/open-and-type.json \
  --artifacts /tmp/medit-uitests
```
Exit codes: 0 pass, 1 test failure, 2 plan error, 3 permission missing.

## Authoring
Use the MCP `dump_axtree` tool (or read these plans) to discover identifiers.
Tagged controls: editorTextView, lineCountLabel, columnLabel, findField,
replaceField, sidebarOutline, goToLineField, reloadButton, dismissReloadButton.
```

- [ ] **Step 6: Validate the plans parse (schema check, no GUI needed)**

Run:
```bash
cd ~/repositories/autopilot && swift build
for p in ~/repositories/medit/uitests/open-and-type.json ~/repositories/medit/uitests/find-replace.json; do
  # parse-only: a real run needs the app + AX grant; here we just confirm the file is valid JSON
  python3 -c "import json,sys; json.load(open('$p')); print('OK', '$p')"
done
```
Expected: `OK` for both plan files.

- [ ] **Step 7: Commit (in the medit repo)**

```bash
cd ~/repositories/medit
git add uitests App/main.swift
git commit -m "test: starter autopilot plan suite + --reset-state hook"
```

---

## Done

After Task 18, the tool is feature-complete per the spec: deterministic JSON plans,
AX-first targeting with deterministic vision fallback, CLI + MCP front-ends over one
core, composition via `include`, full reporting with failure artifacts, a TestHostApp
for self-testing, and medit wired up as test target #1.

**Recommended verification before declaring done:**
```bash
(cd ~/repositories/autopilot && swift build && swift test)
(cd ~/repositories/autopilot && swift run autopilot doctor)
(cd ~/repositories/medit && swift build && swift test)
```
