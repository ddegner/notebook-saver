# Cat Scribe — Coding Instructions

## Project structure

- **NotebookSaver/** — main app target (Cat Scribe)
- **CatScribeShareExtension/** — share extension (lightweight launcher only)
- **Xcode 16**, `PBXFileSystemSynchronizedRootGroup` format (objectVersion 77)
- Swift 6 strict concurrency enabled

## Swift conventions

### Nested type conformances

Declare protocol conformances **on the type declaration itself**, not in a separate extension, when the type is `private` or `fileprivate`. External extensions cannot access private nested types.

```swift
// CORRECT
private enum Phase: Equatable { case loading, saved, failed(String) }

// WRONG — compile error: Phase is inaccessible from outside scope
private enum Phase { case loading, saved, failed(String) }
extension Phase: Equatable {}
```

### Swift 6 concurrency

- `withCheckedThrowingContinuation` body on `@MainActor` is **non-`@Sendable`** (SE-0420) — `NSItemProvider` and other non-Sendable types can be captured safely here.
- `withThrowingTaskGroup.addTask` requires a `@Sendable` closure — do **not** capture non-Sendable types (e.g. `NSItemProvider`).
- `nonisolated(unsafe) static let` is required for `UserDefaults` shared statics on types that need to satisfy Sendable (see `SharedDefaults.suite`).
- Synchronous blocking APIs like `VNImageRequestHandler.perform()` must be wrapped in `DispatchQueue.global(qos: .userInitiated).async { }` inside `withCheckedThrowingContinuation` to avoid starving the cooperative thread pool.

### Settings keys

All `UserDefaults` keys live in `SettingsKey` (enum, static lets). Add new keys there, not inline as string literals.

### Shared state between app and extension

- App Group identifier: `group.com.daviddegner.NotebookSaver`
- Shared `UserDefaults` suite: `SharedDefaults.suite`
- Shared image handoff: file written to App Group container, path stored in `SharedDefaults.suite["pendingSharedImagePath"]`
- Keychain service identifier: `SharedDefaults.keychainService` (`"com.daviddegner.NotebookSaver"`) — fixed string, not `Bundle.main.bundleIdentifier`, so both targets access the same item

## Share extension architecture

The extension is a **lightweight launcher** — it must not run OCR or any heavy processing.

Flow:
1. Extension saves image to App Group container as `pendingSharedImage.jpg`
2. Extension calls `extensionContext?.open(url) { _ in ctx.completeRequest(returningItems: nil) }` — `completeRequest` is called **inside** the completion handler so the extension process stays alive until iOS has actually switched to Cat Scribe. Using `completionHandler: nil` causes the process to tear down before iOS processes the URL open, so Cat Scribe never opens.
3. Main app wakes, reads `pendingSharedImagePath`, clears it, runs OCR via normal pipeline

## Info.plist — document type registration

`LSHandlerRank` must be `"Alternate"` (not `"Default"`) for Cat Scribe to appear in the iOS share sheet's "Open in" section alongside Photos. `Default` rank is suppressed when another app owns the type.

After changing `LSHandlerRank` or `LSItemContentTypes`, a **fresh install** (delete + reinstall) is required — iOS caches document type registrations at install time.

## Xcode project file

Do not manually edit `project.pbxproj` or add files by hand — Xcode 16 uses `PBXFileSystemSynchronizedRootGroup` which manages membership automatically from the filesystem. Add new source files through Xcode only.

## Reading before editing

Always read a file before modifying it. Do not guess at existing code structure.
