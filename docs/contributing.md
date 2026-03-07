# Contributing to Mocker

Thank you for your interest in contributing! This guide covers everything you need to get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Making Changes](#making-changes)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Implementing Apple Containerization TODOs](#implementing-apple-containerization-todos)

## Code of Conduct

Be respectful and constructive. We follow the [Contributor Covenant](https://www.contributor-covenant.org/).

## Development Setup

### Prerequisites

- macOS 26+ (for full container support) or macOS 14+ (for development with placeholders)
- Swift 6.0+
- Xcode 16+

### Clone and Build

```bash
git clone https://github.com/yourname/mocker.git
cd mocker

# Build in debug mode
swift build

# Run tests
swift test

# Run the CLI directly
swift run mocker --help
```

### Recommended Editor Setup

**VS Code** with the Swift extension:
```bash
code .
# Install: Swift for VS Code (sswg.swift-lang)
```

**Xcode:**
```bash
open Package.swift
```

### Clean State for Testing

```bash
# Remove all Mocker state (containers, images, networks, volumes)
rm -rf ~/.mocker

# Rebuild and test
swift build && swift run mocker system info
```

## Project Structure

See [architecture.md](architecture.md) for a full breakdown. Key directories:

```
Sources/MockerKit/   # Core library — most feature work goes here
Sources/Mocker/      # CLI commands — UI/formatting work goes here
Sources/MockerApp/   # MenuBar GUI — SwiftUI work goes here
Tests/               # Unit and integration tests
docs/                # Documentation
```

## Making Changes

### 1. Fork and Branch

```bash
git checkout -b feat/my-feature
# or
git checkout -b fix/bug-description
```

### 2. Make Your Changes

Follow the patterns in existing code:
- New commands: add a file in `Sources/Mocker/Commands/`
- New engine methods: add to the relevant actor in `MockerKit`
- New models: add to `Sources/MockerKit/Models/`

### 3. Write Tests

Add tests for any new functionality in `Tests/MockerKitTests/`:

```swift
@Test("My new feature works")
func testMyFeature() throws {
    // ...
}
```

### 4. Verify

```bash
swift build
swift test
swift run mocker --help  # smoke test
```

## Coding Standards

### Swift Style

- Use Swift 6 strict concurrency — all actors must be properly `await`ed
- Prefer `actor` for any stateful component
- Use `async throws` for all I/O operations
- Prefer `struct` over `class` for value types
- Use `guard` for early returns

### Docker Compatibility

When implementing or modifying commands, check against Docker's output:

```bash
# Check Docker behavior
docker run --help
docker inspect <container>

# Compare with Mocker
swift run mocker run --help
swift run mocker inspect <container>
```

Key compatibility rules:
- Error messages must match: `Error response from daemon: ...`
- `inspect` always returns a JSON array `[{...}]`
- `stop` and `rm` echo back the user's input identifier (not the resolved name)
- Short IDs are exactly 12 characters

### Naming

- Container/image/network/volume names: follow Docker conventions
- Swift types: PascalCase for types, camelCase for properties/methods
- CLI flags: kebab-case matching Docker (`--no-stream`, `--project-name`)

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add mocker login command
fix: correct container name echo in stop command
docs: update cli-reference with new flags
test: add tests for network connect/disconnect
refactor: extract image validation into helper
chore: update Yams dependency to 5.2
```

Maximum 72 characters for the subject line.

## Testing

### Running Tests

```bash
# All tests
swift test

# Specific suite
swift test --filter MockerKitTests
swift test --filter MockerTests

# Specific test
swift test --filter "ContainerConfigTests/testParsePortMapping"
```

### Test Structure

```
Tests/
├── MockerKitTests/
│   ├── ContainerConfigTests.swift   # PortMapping, VolumeMount parsing
│   ├── ImageReferenceTests.swift    # ImageReference.parse()
│   └── ComposeFileTests.swift       # YAML parsing
└── MockerTests/
    └── CLITests.swift               # CLI smoke tests
```

### Writing Tests

Use the `Testing` framework (Swift 6):

```swift
import Testing
@testable import MockerKit

@Suite("MyFeature Tests")
struct MyFeatureTests {
    @Test("Parse valid input")
    func testParseValid() throws {
        let result = try MyType.parse("valid-input")
        #expect(result.value == "expected")
    }

    @Test("Parse invalid input throws")
    func testParseInvalid() {
        #expect(throws: MockerError.self) {
            try MyType.parse("")
        }
    }
}
```

### Integration Testing

For commands that affect state, use a temporary config:

```swift
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
let config = MockerConfig(dataRoot: tempDir.path)
try config.ensureDirectories()
// ... test with this config
```

## Submitting a Pull Request

1. **Ensure tests pass:** `swift test`
2. **Ensure it builds:** `swift build`
3. **Self-review your diff** — remove debug prints, check for typos
4. **Write a clear PR description:**
   - What problem does this solve?
   - How was it tested?
   - Any breaking changes?

### PR Title Format

Follow Conventional Commits format:
- `feat: add mocker login command`
- `fix: prevent duplicate images on repeated pull`
- `docs: add compose guide`

## Implementing Apple Containerization TODOs

The highest-impact contributions are replacing placeholder implementations with real Apple Containerization framework calls. Look for `// TODO:` comments:

```bash
grep -r "TODO:" Sources/MockerKit/
```

### Key Integration Points

**Image Pull** (`ImageManager.swift`):
```swift
// TODO: Use Containerization framework to actually pull the image
// Replace with Apple Containerization image pull API
```

**Container Start** (`ContainerEngine.swift`):
```swift
// TODO: Use Containerization framework to start the container
// Replace with Container() init + start()
```

**Container Logs** (`ContainerEngine.swift`):
```swift
// TODO: Stream real logs from the container process
```

### Guidelines for TODO Implementation

1. Keep the existing method signature — callers should not change
2. The placeholder `ContainerInfo` returned should match the real framework's data
3. Add error handling for framework-specific errors, mapping to `MockerError`
4. Update the relevant tests

## Questions?

Open an issue with the `question` label, or start a GitHub Discussion.
