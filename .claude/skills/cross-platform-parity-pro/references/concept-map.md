# Concept map: Apple ↔ Android

Use this to translate *concepts*, then write the target side idiomatically. Rows are equivalents in role, not drop-in replacements — read the "watch out" column.

## Language

| Concept | Swift | Kotlin | Watch out |
|---|---|---|---|
| Value type | `struct` | `data class` (reference type with value semantics via `copy`) | Kotlin data classes are references; mutate with `copy(...)`, keep fields `val`. |
| Sum type | `enum` with associated values | `sealed interface` + `data class` / `data object` | Exhaustive `switch` ↔ exhaustive `when` (as an expression). |
| Optional | `T?`, `if let`, `guard let` | `T?`, `?.let {}`, `?: return` | `!` ↔ `!!` — both are findings in shipping code. |
| Protocol / interface | `protocol` (+ extensions for defaults) | `interface` (with default methods) | Protocol extensions on concrete types ↔ extension functions. |
| Generic constraint | `some P` / `any P` | `T : P` / `P` | Swift `any P` boxes; Kotlin interfaces are always reference types. |
| ID wrapper | `struct TaskID: Hashable` or `Tagged` | `@JvmInline value class TaskId(val value: String)` | |
| Errors | typed `throws(DomainError)` / `Result` | exceptions, or `Result` / sealed result | Pick the per-project convention on each side (repository rules). |
| Access control | `public` / `internal` / `private` / `fileprivate` | `public` / `internal` (module) / `private` (file or class) / `protected` | Both default-public vs default-internal differ: Swift defaults to `internal`, Kotlin to `public` — mark Kotlin APIs `internal` deliberately. |
| Extensions | `extension Type` | extension functions / properties | Kotlin extensions are static dispatch, can't add stored state. |
| Naming | `lowerCamelCase` funcs, `UpperCamelCase` types, argument labels | same casing, no argument labels — use named arguments | `func move(from:to:)` ↔ `fun move(from: Int, to: Int)` called with named args. |

## Concurrency

| Concept | Swift | Kotlin |
|---|---|---|
| One-shot async | `async throws` | `suspend fun` |
| Stream | `AsyncSequence` / `AsyncStream` | `Flow` (cold) |
| Observable current value | `@Observable` property | `StateFlow` |
| UI isolation | `@MainActor` | `Dispatchers.Main` / `viewModelScope` (Main by default) |
| Background work | `actor`, `@concurrent` / nonisolated async | `withContext(Dispatchers.IO / Default)` with injected dispatchers |
| Structured children | `async let`, `TaskGroup` | `async {}` / `coroutineScope {}` |
| Lifetime-bound task | `.task {}` modifier (cancels with the view) | `LaunchedEffect` / `viewModelScope` |
| Outlives the screen | app-level `Task` owned by a service; `BGTaskScheduler` | `@ApplicationScope` scope; WorkManager |
| Cancellation | `Task.isCancelled`, `CancellationError` | cooperative, `CancellationException` (never swallow) |
| Thread-safety marker | `Sendable` | immutability by convention (no compiler check) |

## UI layer

| Concept | SwiftUI | Compose |
|---|---|---|
| Screen state holder | `@MainActor @Observable final class XViewModel` | `@HiltViewModel class XViewModel : ViewModel()` |
| Exposed state | observable properties (or one `state` struct) | one `StateFlow<XUiState>` |
| Owning the VM | `@State var viewModel` / injected `@Bindable` | `hiltViewModel()` in the Route |
| Reading state in UI | automatic observation | `collectAsStateWithLifecycle()` |
| Local UI state | `@State` | `remember { mutableStateOf() }` / `rememberSaveable` |
| Survives process death | `@SceneStorage` | `SavedStateHandle` / `rememberSaveable` |
| Two-way binding | `Binding<T>` / `$x` | `value` + `onValueChange` |
| Stateless view | `View` taking values + closures | `@Composable` taking state + lambdas (`XScreen`) |
| Environment values | `@Environment(\.key)` / `@Entry` | `CompositionLocal` |
| Side effect on appear | `.task {}` / `.onAppear` | `LaunchedEffect(key)` |
| Lists | `List` / `LazyVStack` + `ForEach(id:)` | `LazyColumn { items(key = ) }` |
| Navigation | `NavigationStack(path:)` + `navigationDestination` | Navigation Compose (type-safe routes) |
| Modal | `.sheet` / `.fullScreenCover` | `ModalBottomSheet` / `Dialog` / a nav destination |
| Adaptive two-pane | `NavigationSplitView` | `ListDetailPaneScaffold` |
| Tab / nav bar | `TabView` | `NavigationSuiteScaffold` / `NavigationBar` |
| Theme | design-system tokens + `.tint` | `AppTheme` / `MaterialTheme` |
| Icons | `AppIcon` facade over SF Symbols | `AppIcons` over Material Symbols drawables |
| Preview | `#Preview` | `@Preview` (+ multipreview annotations) |

## Data, DI, platform services

| Concept | Apple | Android |
|---|---|---|
| Repository | `protocol XRepository: Sendable` + `actor` impl | `interface XRepository` + `@Singleton` impl bound with `@Binds` |
| DI | init injection; composition root in `AppCore`; `@Environment` for deep views | Hilt (`@Inject`, `@Module`, `@InstallIn`) |
| Local DB | SwiftData / Core Data (`@ModelActor`, background context) | Room (DAO `Flow` queries) |
| Key-value | `UserDefaults` / `@AppStorage` | DataStore |
| Secrets | Keychain | Android Keystore-backed encryption (Jetpack Security's `EncryptedSharedPreferences` is deprecated) |
| HTTP | `URLSession` (+ swift-openapi-generator client) | Retrofit / Ktor (+ openapi-generator client) |
| JSON | `Codable` | Moshi / kotlinx.serialization |
| Background work | `BGTaskScheduler` | WorkManager |
| Push | APNs (`UNUserNotificationCenter`) | FCM (`FirebaseMessagingService`) |
| Deep links | Universal Links + `onOpenURL` | App Links + nav deep links |
| Logging | `Logger` (os) | Timber |
| On-device AI | Foundation Models | Gemini Nano / ML Kit GenAI |

## Resources and accessibility

| Concept | Apple | Android |
|---|---|---|
| Strings | `Localizable.xcstrings` via a `Strings` facade (`LocalizedStringResource`) | `strings.xml` via `stringResource(R.string.x)` |
| Key | `task_list.empty_title` | `task_list_empty_title` (dots → underscores) |
| Format args | `\(value)` in the catalog's default value | positional `%1$s`, `%2$d` |
| Plurals | catalog plural variations | `<plurals>` + `pluralStringResource` |
| Screen-reader label | `.accessibilityLabel` | `contentDescription` / `semantics {}` |
| Merge a row | `.accessibilityElement(children: .combine)` | `Modifier.semantics(mergeDescendants = true)` |
| Heading | `.accessibilityAddTraits(.isHeader)` | `semantics { heading() }` |
| Custom actions | `.accessibilityActions {}` | `customActions = listOf(CustomAccessibilityAction(...))` |
| Text scaling | Dynamic Type text styles | `sp` + M3 type scale |
| Reduce motion | `\.accessibilityReduceMotion` | animator duration scale / `isReduceMotionEnabled` |
| Touch target | 44×44 pt | 48×48 dp |

## Testing

| Concept | Apple | Android |
|---|---|---|
| Unit test framework | Swift Testing (`@Test`, `#expect`, `#require`) | JUnit + `kotlin.test` / assertions |
| Async test | `async` test function | `runTest {}` |
| Stream assertions | iterate the `AsyncSequence` with a bound | Turbine `flow.test {}` |
| Fakes | in-memory `actor` conforming to the protocol | `FakeXRepository` backed by `MutableStateFlow` |
| UI test | XCUITest by `accessibilityIdentifier` | Compose UI test by `testTag` / semantics |
| Main dispatcher | `@MainActor` suite | `MainDispatcherRule` |
| Screenshot | snapshot libraries (optional) | Roborazzi / Paparazzi / Compose Preview Screenshot Testing |
