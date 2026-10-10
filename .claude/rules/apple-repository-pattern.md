---
description: Apple data layer and the repository pattern — protocol-based repositories returning Sendable domain models, actor or Sendable implementations under Swift 6, local store as the single source of truth with AsyncSequence observation, DTO/persistence/domain mapping, typed errors, in-flight dedup, injection at the composition root, and in-memory fakes for tests
globs: "**/*.swift"
---

# Apple Repository Pattern (Data Layer)

Opt-in (`--features …,architecture`). A repository owns one kind of app data (tasks, profile, settings), hides *where* it comes from (network, Core Data, SwiftData, files, Keychain), and is the one place that data changes. View models talk to repository **protocols**; they never touch `URLSession`, `NSManagedObjectContext`, or `ModelContext`. This pairs with the presentation-side conventions in [`apple-swiftui-mvvm.md`](./apple-swiftui-mvvm.md) and the module layering in [`apple-modular-architecture.md`](./apple-modular-architecture.md).

## When It Pays Off — and When It Doesn't

- **Use a repository** when data comes from more than one source (cache + network), must be shared across screens, needs offline support, or the view model must be unit-tested without a server or database.
- **Skip it** for a small SwiftData app whose views read with `@Query` and nothing else touches the data — `@Query` *is* the observation layer, and wrapping it adds ceremony without a seam anyone uses. Introduce a repository when a second source, sync, or testability need appears.
- **No generic `Repository<Entity>` CRUD protocol.** Different data has different freshness, sync, and error rules; a generic base hides them.

## Shape

```swift
// Domain module — no Foundation networking, no persistence imports.
public struct Task: Sendable, Hashable, Identifiable {
    public let id: Task.ID
    public var title: String
    public var isCompleted: Bool
    public typealias ID = Tagged<Task, UUID>   // or a small struct wrapper
}

public protocol TasksRepository: Sendable {
    func tasks() -> AsyncStream<[Task]>                         // live data: a stream
    func refresh() async throws(TasksError)                     // one-shot: async throws
    func complete(_ id: Task.ID) async throws(TasksError)
}

public enum TasksError: Error, Sendable, Equatable {
    case offline, unauthorized, notFound, server
}
```

- **Protocol in a domain/interface module, implementation in a data module.** Features depend on the protocol; the app's composition root (`AppCore`) wires the implementation.
- **Live data as `AsyncSequence`** (`AsyncStream`, or an `AsyncSequence` built on `NotificationCenter` / `NSPersistentStoreRemoteChange` / an observation bridge); **one-shots as `async throws`**. Don't return a snapshot array for data the UI should keep observing.
- **Domain models are `Sendable` value types** — never `NSManagedObject`, SwiftData `@Model` instances, or `Codable` DTOs across the boundary. Managed objects aren't `Sendable` and are bound to their context.
- **Typed throws** with a domain error enum (Swift 6) so view models can switch exhaustively. See the `swift-error-handling-pro` skill.
- **Name by data type** (`TasksRepository`), not by screen.

## Implementation Under Swift 6

```swift
actor RemoteFirstTasksRepository: TasksRepository {
    private let api: TasksAPI                 // remote data source (URLSession-backed)
    private let store: TasksStore             // local data source (Core Data / SwiftData / file)
    private var inFlightRefresh: _Concurrency.Task<Void, any Error>?

    init(api: TasksAPI, store: TasksStore) {
        self.api = api
        self.store = store
    }

    nonisolated func tasks() -> AsyncStream<[Task]> {
        store.observeTasks()                  // local store is the source of truth
    }

    func refresh() async throws(TasksError) {
        if let inFlightRefresh {              // dedupe concurrent refreshes
            do { try await inFlightRefresh.value } catch { throw TasksError(error) }
            return
        }
        let job = _Concurrency.Task {
            let dtos = try await api.fetchTasks()
            try await store.upsert(dtos.map(Task.init(dto:)))
        }
        inFlightRefresh = job
        defer { inFlightRefresh = nil }
        do { try await job.value } catch { throw TasksError(error) }
    }

    func complete(_ id: Task.ID) async throws(TasksError) {
        do {
            try await store.markCompleted(id)  // local first: UI updates via the stream
            try await api.complete(id)
        } catch { throw TasksError(error) }
    }
}
```

- **`actor`** when the repository holds mutable state (caches, in-flight tasks); a **`final class` with only `let` `Sendable` dependencies** when it's stateless. Never `@unchecked Sendable` — see [`apple-swift6-strict-concurrency.md`](./apple-swift6-strict-concurrency.md).
- **Not `@MainActor`.** Repository work is I/O and mapping; pinning it to the main actor blocks UI. The `@MainActor` view model awaits it.
- **Core Data**: do work in `performBackgroundTask` / a background context and return mapped value types. **SwiftData**: use a `@ModelActor` for background reads/writes and map to value types before returning. See `coredata-swift6-pro` / `swiftdata-pro`.
- **Dedupe in-flight requests** (as above) so three screens appearing at once don't fire three identical fetches.
- **`(Task)` name clash**: if your domain has a `Task` type, qualify Swift's as `_Concurrency.Task` — or pick a different domain name.

## Single Source of Truth

- **Local store is the source of truth; the network writes into it.** The UI observes the store through the repository's stream, so data edited on one screen updates every screen, and the app works offline.
- **Refresh failures don't erase data** — surface "couldn't refresh" separately from the cached content.
- **Writes go local first**, then sync. Writes that must survive app termination use a background task (`BGTaskScheduler` / `BGProcessingTask`) or a persisted outbox the repository drains on launch.
- **Secrets** (tokens) live in the Keychain behind their own small store — not in `UserDefaults`, not in the repository's cache.

## Model Mapping

| Model | Where | Notes |
|---|---|---|
| DTO | Networking module | `Decodable`, mirrors the API, internal |
| Persistence model | Storage module | `NSManagedObject` / `@Model`, internal |
| Domain model | Models module | `Sendable` struct, public |

- Mapping is small `init(dto:)` / `init(managed:)` initializers in the data module. A schema or API rename stops at the repository.

## Errors

- Data sources throw transport/storage errors; the repository **maps them** to the domain error (`URLError.notConnectedToInternet` → `.offline`). View models never import networking types to interpret errors.
- Don't swallow `CancellationError` into a domain error — let cancellation propagate (or map it to a distinct case the caller ignores).

## Injection

- **Construct repositories once at the composition root** (`AppCore`) and pass them into view models' initializers ([`apple-swiftui-mvvm.md`](./apple-swiftui-mvvm.md): long-lived dependencies captured at init).
- To reach deep views, put the *protocol* in the environment (`@Entry var tasksRepository: any TasksRepository = UnimplementedTasksRepository()`) — a default that fails loudly beats a silent live one in previews.
- No singletons (`static let shared`) as the access path — they make tests share state.

## Testing

- **In-memory fakes over mocks**: `actor InMemoryTasksRepository: TasksRepository` backed by a dictionary and an `AsyncStream` continuation; ship it in a test-support module so view-model tests and previews both use it.
- **Contract tests**: one parameterized Swift Testing suite run against the fake *and* the real implementation (with a stubbed `URLProtocol` and an in-memory store) proves the fake behaves like production.
- See [`apple-testing-strategy.md`](./apple-testing-strategy.md).

## Common Pitfalls

- **View models calling `URLSession` / `ModelContext` / `NSManagedObjectContext` directly** — no seam, no offline story.
- **Returning managed objects or `@Model` instances** across actor boundaries — non-`Sendable`, context-bound, compile errors under Swift 6 (or worse, `@unchecked Sendable` to silence them).
- **`@MainActor` repositories** doing network and disk work on the main thread.
- **Snapshot arrays for live data** — screens go stale when another screen edits the data.
- **Network as the source of truth with an ad-hoc cache** — two sources the UI can disagree with.
- **Untyped `throws` + string matching** on errors in view models.
- **A generic CRUD `Repository<T>`** that hides per-type sync and freshness rules.
- **Repository for a pure `@Query` screen** — ceremony without a seam anyone uses.
