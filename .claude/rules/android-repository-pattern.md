---
description: Android data layer and the repository pattern — repositories as the single source of truth exposing Flow and main-safe suspend functions, offline-first with Room as the source of truth, network/local data sources, DTO/entity/domain model mapping, Hilt bindings, work that outlives the caller, and fake repositories for tests
globs: "**/*.{kt,kts}"
---

# Android Repository Pattern (Data Layer)

Opt-in (`--features …,architecture`). The data layer of Android's recommended architecture: **ViewModel → (optional use case) → repository → data sources**. A repository owns one type of app data (tasks, user profile, settings), hides *where* it comes from, and is the **single source of truth** for it. ViewModels never touch Retrofit, Room, or DataStore directly. The presentation side is covered in [`android-mvvm-architecture.md`](./android-mvvm-architecture.md).

## Responsibilities

- **Expose data** to the rest of the app as domain models.
- **Centralize changes** — every write to that data goes through the repository.
- **Resolve conflicts** between sources (cache vs network) and decide freshness.
- **Contain business rules about the data** (deduplication, merging, validation before persisting).
- **Not**: UI formatting, string resources, navigation, or knowledge of which screen is asking.

## Shape

```kotlin
interface TasksRepository {
    fun observeTasks(): Flow<List<Task>>          // streams: cold Flow, never one-shot lists for live data
    fun observeTask(id: TaskId): Flow<Task?>
    suspend fun refresh()                          // one-shot operations: suspend
    suspend fun complete(id: TaskId)
}

internal class OfflineFirstTasksRepository @Inject constructor(
    private val taskDao: TaskDao,                  // local data source (Room) — the source of truth
    private val network: TasksNetworkDataSource,   // remote data source (Retrofit)
    @Dispatcher(IO) private val ioDispatcher: CoroutineDispatcher,
) : TasksRepository {

    override fun observeTasks(): Flow<List<Task>> =
        taskDao.observeAll().map { entities -> entities.map(TaskEntity::asDomain) }

    override fun observeTask(id: TaskId): Flow<Task?> =
        taskDao.observe(id.value).map { it?.asDomain() }

    override suspend fun refresh() = withContext(ioDispatcher) {
        val remote = network.fetchTasks()                      // DTOs
        taskDao.upsertAll(remote.map(NetworkTask::asEntity))   // DB emits; observers update
    }

    override suspend fun complete(id: TaskId) = withContext(ioDispatcher) {
        taskDao.markCompleted(id.value)                        // local first: UI updates instantly
        network.completeTask(id.value)                         // then sync (or enqueue WorkManager)
    }
}
```

- **Interface in the API, implementation internal.** Consumers depend on `TasksRepository`; the implementation is bound with Hilt `@Binds` in the data module. The interface is the seam for fakes.
- **Streams as `Flow`, one-shots as `suspend`.** Don't expose `LiveData`, callbacks, or `MutableStateFlow` from repositories.
- **Main-safe**: every public function can be called from `Dispatchers.Main`; blocking work moves to an injected dispatcher inside the repository or data source. Room and Retrofit `suspend`/`Flow` APIs are already main-safe.
- **Name by data type** (`TasksRepository`, `UserDataRepository`), not by screen (`HomeRepository`).

## Single Source of Truth — Offline-First

- **The local database is the source of truth.** The network only *writes into* it; the UI only *reads from* it (via the repository's `Flow`). This gives offline support, instant UI, and one place where data changes.
- **Reads**: observe the DB; trigger `refresh()` on screen entry or pull-to-refresh, and surface refresh failure separately from the (still valid) cached data.
- **Writes**: write locally first, then sync. For writes that must reach the server even if the app dies, enqueue a **WorkManager** job (with constraints and backoff) rather than a coroutine.
- **Small key-value state** (settings, flags) belongs in **DataStore** behind its own repository, not `SharedPreferences`.
- Network-only repositories (no cache) are fine for data that must always be fresh — but still return domain models and map errors.

## Model Separation

| Model | Lives in | Example |
|---|---|---|
| Network DTO | `:core:network` | `NetworkTask` (`@JsonClass`/`@Serializable`) |
| Database entity | `:core:database` | `TaskEntity` (`@Entity`) |
| Domain / external model | `:core:model` | `Task` (plain `data class`, no annotations) |

- **Repositories map** DTO → entity → domain with small extension functions (`asEntity()`, `asDomain()`). ViewModels and UI see only domain models.
- **Never leak `@Entity` or DTO types** past the repository — a schema change or API rename would ripple into UI code.
- Domain models are immutable; use value classes (`@JvmInline value class TaskId(val value: String)`) for IDs.

## Errors

- **Data sources throw; repositories decide.** Either let exceptions propagate to the caller (ViewModel maps them to UiState with `catch`), or return `Result`/a sealed result type — pick one convention per project and stick to it.
- **Map transport errors** (`IOException`, `HttpException`) into domain-meaningful outcomes at the repository boundary; ViewModels shouldn't import Retrofit.
- **Never swallow `CancellationException`** (no blanket `runCatching` around suspend calls without rethrowing it) — see [`android-coroutines-best-practices.md`](./android-coroutines-best-practices.md).

## Lifetimes and Scope

- **Repositories are `@Singleton`** (or scoped to the data they own) so in-memory caches and in-flight dedup are shared.
- **Work that must outlive the caller** (finish a sync even if the user leaves the screen) runs in an injected application-wide `CoroutineScope` (`@ApplicationScope`, `SupervisorJob() + Dispatchers.Default`) — never `GlobalScope`, never the ViewModel's scope.
- **In-memory caches** are guarded with a `Mutex` when mutated from multiple coroutines.

## Modules and DI

- `:core:data` (repositories + `@Binds` module) depends on `:core:database`, `:core:network`, `:core:datastore`, `:core:model`. Features depend on `:core:data` (or `:core:domain`), never on network/database modules directly. See [`android-gradle-conventions.md`](./android-gradle-conventions.md).

```kotlin
@Module
@InstallIn(SingletonComponent::class)
internal abstract class DataModule {
    @Binds abstract fun bindsTasksRepository(impl: OfflineFirstTasksRepository): TasksRepository
}
```

## Testing

- **Fakes over mocks.** Provide `FakeTasksRepository` (backed by a `MutableStateFlow`) in a shared test module (`:core:testing` / `:core:data-test`); ViewModel tests use it, UI tests bind it with Hilt `@TestInstallIn`.
- **Test real repositories** against in-memory Room (`Room.inMemoryDatabaseBuilder`) and a fake network data source; assert flows with Turbine.
- See [`android-testing-strategy.md`](./android-testing-strategy.md).

## When Not To

- A screen that renders static content or a single DataStore flag doesn't need its own repository — reuse the settings repository.
- **No generic `Repository<T, ID>` CRUD base interface** — data types have different freshness, sync, and error rules; a generic base hides them.
- **No pass-through layers**: a repository that only forwards to one Retrofit call is still worthwhile (it's the seam and the mapping point), but a use case that only forwards to that repository is not.

## Common Pitfalls

- **ViewModels calling Retrofit or DAOs directly.**
- **Returning `List<T>` from a suspend function for data the UI should observe** — the screen goes stale when another screen edits it. Expose `Flow`.
- **Network as the source of truth with a side cache** — two sources the UI can disagree with. Make the DB the source; the network writes into it.
- **Entities/DTOs in UiState.**
- **Sync launched in `viewModelScope`** — cancelled when the user navigates away.
- **Repositories scoped per screen** — caches and dedup reset constantly.
- **`runCatching` swallowing cancellation.**
