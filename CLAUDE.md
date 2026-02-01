# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Philosophy

这个项目不追求酷炫的界面交互。相反的，我们追求清晰简明、符合直觉的界面和操作逻辑；追求代码的简明和最少化、易读性和长期可维护性、可扩展性，追求架构的稳定性；追求极客的快捷操作感受。总的定位是：这是一个很高效的学习象棋的工具软件。

## Project Overview

XiangqiNotebook (象棋笔记本) is a cross-platform Chinese chess learning and note-taking application built with SwiftUI, supporting iPhone, iPad, and macOS. It features path marking, position scoring, bookmarks, annotations, and practice modes for chess study and review.

## Build and Test Commands

This is an Xcode project. Common development tasks:

- **Build**: `xcodebuild -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook build`
- **Run Tests**: `xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS'`
- **Run Single Test**: `xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS' -only-testing:XiangqiNotebookTests/TestClassName/testMethodName`
- **Run Tests on iOS**: Use `-destination 'platform=iOS Simulator,name=iPhone 15'` or similar

**Note on ARM64**: If running tests on Apple Silicon Mac, wrap the command with `arch -arm64 /bin/bash -c '...'` to ensure proper architecture.

## Architecture Overview

### MVVM Pattern with Strict Layer Separation
- **Views**: Only access ViewModels, never Models directly
- **ViewModels**: Coordinate between Views, Models, and Services
- **Models**: Independent data layer using ObservableObject
- **Services**: Platform abstraction through protocols

### Core Data Flow
```
Views ↔ ViewModels ↔ Session ↔ DatabaseView ↔ Database
           ↕                         ↕
    Platform Services          DatabaseData
           ↕
  Storage Layer (DatabaseStorage/SessionStorage)
           ↕
    iCloudFileCoordinator (singleton)
```

### Key Components

**DatabaseData and SessionData**:
- `DatabaseData`: Core game data (positions, moves, games, books, bookmarks, statistics)
  - Managed by `Database` for business logic
  - Persisted by `DatabaseStorage` for file I/O
- `SessionData`: UI state and session information (current game, UI settings, navigation state)
  - Managed by `SessionManager` for business logic
  - Persisted by `SessionStorage` for file I/O
- Core data structures in DatabaseData:
  - `fenObjects2`: Dictionary mapping fenId → FenObject (game positions)
  - `moveObjects`: Dictionary mapping moveId → Move (game moves)
  - `gameObjects`: Dictionary for complete games
  - `bookObjects`: Dictionary for chess book organization
- Data change notification via `@Published dataChanged: Bool`

**ViewModel.swift**:
- Main business logic coordinator
- Holds `@Published private(set) var sessionManager: SessionManager`
- Accesses current session via `sessionManager.currentSession`
- Manages UI state and user interactions
- All data operations go through SessionManager and Session

**SessionManager**:
- Manages multiple Session instances (main session and practice session)
- Handles filter scope switching by creating new Session with appropriate DatabaseView
- Coordinates between different views (full database, red opening, black opening, etc.)
- Factory method: `.create(from:database:)` creates SessionManager from SessionData
- Ensures data consistency when switching between sessions

**DatabaseView** (Data filtering layer):
- Provides filtered view of Database based on scope (red/black opening, real games, focused practice, etc.)
- Encapsulates all fenId-based filtering logic internally
- Core methods enforce strict filtering semantics (source AND target must be in scope):
  - `getFenObject(_:)`: Returns FenObject if fenId is in scope
  - `containsFenId(_:)`: Checks if fenId belongs to current scope
  - `moves(from:)`: Returns moves where both source and target are in scope
  - `move(from:to:)`: Finds move if both endpoints are in scope
- Provides direct passthrough for non-filtered data (fenToId, moveObjects, bookObjects, etc.)
- Constructed via factory methods (`.full()`, `.redOpening()`, `.blackOpening()`, etc.)
- Session holds and manages the current DatabaseView instance

**Storage Layer**:
- `DatabaseStorage`: Static methods for database file I/O, handles iCloud coordination for database files
- `SessionStorage`: Static methods for session file I/O, handles iCloud coordination for session files
- `iCloudFileCoordinator`: Singleton managing file coordination for iCloud synchronization
  - Provides `coordinatedRead()` and `coordinatedWrite()` for safe concurrent access
  - Tracks save operations to prevent self-triggered file change notifications
  - Used by both DatabaseStorage and SessionStorage for iCloud URLs

**Platform Services**:
- `iOSPlatformService.swift` and `MacOSPlatformService.swift`
- Abstract platform-specific functionality (alerts, file operations, etc.)

### File Organization
- `Models/`: Core data models and storage layer
  - Data models: `FenObject`, `Move`, `GameObject`, `DatabaseData`, `SessionData`
  - Business logic: `MoveRules`, `GameOperations`, `Database`, `SessionManager`
  - Data view layer: `DatabaseView` (filtering and scoped access to Database)
  - Storage: `DatabaseStorage`, `SessionStorage`, `iCloudFileCoordinator`
- `Views/`: UI components split by platform (iOS/, Mac/, board/)
- `ViewModels/`: Business logic and view state management
- `Services/`: Platform abstraction layer
- `Resources/`: Game assets (board and piece images in PNG/SVG)

### Key System Features
- **Practice Mode**: Automatic practice count tracking, limited game extension, hidden path display
- **Filter System**: Red/Black opening filters with dynamic board orientation
- **Lock Mechanism**: Step locking to prevent misoperations, supports history navigation
- **Path Management**: Auto-generates all possible paths with DFS algorithm, path counting statistics
- **Bookmark System**: Save important positions for quick navigation and categorized management
- **Data Persistence**: Complete Codable implementation for data serialization/deserialization
- **iCloud Sync**: Automatic file coordination using NSFileCoordinator for safe concurrent access

## Development Guidelines

### Using DatabaseView for Data Access

**Core Principles:**
- Always access fenId-based data through `DatabaseView`, never directly through `DatabaseData`
- Use `containsFenId(_:)` for entry validation before accessing fenId-based data
- All move-related methods enforce strict filtering: both source AND target must be in scope

**Common Patterns:**

1. **Check if a position is in scope:**
```swift
if databaseView.containsFenId(fenId) {
    // Position is accessible in current view
}
```

2. **Get a FenObject:**
```swift
if let fenObject = databaseView.getFenObject(fenId) {
    // Work with the fenObject
}
```

3. **Get moves from a position:**
```swift
// Always validate source first
guard databaseView.containsFenId(sourceFenId) else { return [] }
let moves = databaseView.moves(from: sourceFenId)
// All returned moves have targets also in scope
```

4. **Find a specific move:**
```swift
if let move = databaseView.move(from: sourceFenId, to: targetFenId) {
    // Move exists and both endpoints are in scope
}
```

**Direct Access (Non-filtered):**
- Use DatabaseView's passthrough properties for data that doesn't need filtering:
  - `fenToId`, `moveObjects`, `moveToId`, `bookObjects`, `gameObjects`
- These provide direct access to underlying DatabaseData without filtering

### Test-Driven Development Workflow

**CRITICAL: Every code change MUST be validated with unit tests before completion.**

When making any code changes:

1. **After Every Code Modification:**
   - Run the full test suite: `xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS'`
   - At minimum, run tests related to the modified components
   - Never mark a task as complete without running tests

2. **Test Execution Requirements:**
   - All tests MUST pass before considering the change complete
   - If any test fails:
     - Analyze the failure and identify the root cause
     - Fix the code (or test if it's a test issue)
     - Re-run tests until all pass
     - Do NOT proceed with other tasks until tests pass

3. **When to Run Tests:**
   - After modifying any Model layer code (DatabaseData, SessionData, FenObject, Move, etc.)
   - After modifying any business logic (Database, SessionManager, GameOperations, MoveRules)
   - After refactoring any core functionality
   - Before committing any changes
   - When user explicitly requests testing

4. **Test Scope Guidelines:**
   - **Preferred**: Run the complete test suite to catch integration issues
   - **Minimum**: Run tests for the specific classes/components modified
   - **Example**: If modifying DatabaseView, run tests that exercise DatabaseView functionality

5. **Reporting Test Results:**
   - Always inform the user about test execution and results
   - If tests fail, explain what failed and what you're doing to fix it
   - If tests pass, confirm that code changes are validated

### Platform-Specific Development
- Use conditional compilation for platform differences: `#if os(macOS)`, `#if os(iOS)`
- iPhone: Touch-optimized, simplified UI
- iPad: Enhanced interface with more controls
- Mac: Full desktop experience with multiple windows and keyboard shortcuts

### iCloud File Coordination
When working with iCloud files:
- Always use `iCloudFileCoordinator.shared` for file coordination
- Check if URL is iCloud using `DatabaseStorage.isICloudURL()` or `SessionStorage.isICloudURL()`
- Use `coordinatedRead()` for reading files
- Use `coordinatedWrite()` for writing files
- The coordinator handles semaphore-based synchronization automatically

### Testing

**Test Coverage:**
Tests are located in `XiangqiNotebookTests/` covering:
- Core game logic (MoveRules, GameOperations)
- Data models (FenObject, DatabaseData, SessionData)
- Move validation and board state management
- DatabaseView filtering and scoping logic
- Storage layer operations

**Test Commands Quick Reference:**
```bash
# Run all tests (REQUIRED after code changes)
xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS'

# Run specific test class
xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS' -only-testing:XiangqiNotebookTests/TestClassName

# Run single test method
xcodebuild test -project XiangqiNotebook.xcodeproj -scheme XiangqiNotebook -destination 'platform=macOS' -only-testing:XiangqiNotebookTests/TestClassName/testMethodName
```

**Test Execution Policy:**
- Tests MUST be run after every code change
- All tests MUST pass before code changes are considered complete
- Test failures must be fixed immediately before proceeding

## Code Conventions

- **ALWAYS run and pass unit tests after code changes** - Never consider a change complete without validated tests
- Follow existing Swift/SwiftUI patterns in the codebase
- Use `@Published` for observable properties in ViewModels
- Maintain strict layer separation: Views → ViewModels → Models → Storage
- Platform services should use protocol-based abstraction
- Game logic should be platform-agnostic in Models layer
- Storage layer uses static methods for file I/O operations
- All iCloud file operations must go through `iCloudFileCoordinator.shared`
- Always use DatabaseView for fenId-based data access, never access DatabaseData directly
- Validate fenId scope with `containsFenId(_:)` before performing operations

## Common Pitfalls to Avoid

1. **Don't skip testing after code changes** - NEVER mark a task complete without running and passing all relevant tests
2. **Don't access Models directly from Views** - Always go through ViewModels
3. **Don't bypass DatabaseView** - Never access `DatabaseData.fenObjects2` directly; always use `DatabaseView.getFenObject(_:)`
4. **Don't forget scope validation** - Always check `databaseView.containsFenId(_:)` before accessing fenId-based data
5. **Don't bypass iCloudFileCoordinator** - All iCloud file operations must use the coordinator
