# Navigation and DI across modules

## Navigation

Features must navigate to each other without depending on each other's implementation. The pattern (Navigation Compose 2.8+ type-safe routes):

```kotlin
// :feature:tasks:api — what other modules may see
@Serializable data object TasksRoute
@Serializable data class TaskDetailRoute(val taskId: String)

fun NavController.navigateToTasks(navOptions: NavOptions? = null) = navigate(TasksRoute, navOptions)
fun NavController.navigateToTaskDetail(taskId: String, navOptions: NavOptions? = null) =
    navigate(TaskDetailRoute(taskId), navOptions)
```

```kotlin
// :feature:tasks:impl — the screens and the graph entry
fun NavGraphBuilder.tasksGraph(
    onTaskClick: (String) -> Unit,
    onSettingsClick: () -> Unit,
) {
    composable<TasksRoute> {
        TaskListRoute(onTaskClick = onTaskClick, onSettingsClick = onSettingsClick)
    }
    composable<TaskDetailRoute> { TaskDetailRoute() }  // ViewModel reads the id via savedStateHandle.toRoute()
}
```

```kotlin
// :app — the only module that knows every destination
@Composable
fun AppNavHost(navController: NavHostController = rememberNavController()) {
    NavHost(navController, startDestination = TasksRoute) {
        tasksGraph(
            onTaskClick = navController::navigateToTaskDetail,
            onSettingsClick = navController::navigateToSettings,
        )
        settingsGraph(onBack = navController::popBackStack)
    }
}
```

- **Features take navigation as lambdas.** A feature never calls another feature's `navigateTo…`; `:app` passes it in. This also keeps screens previewable and testable.
- **Routes carry IDs, not objects.** The destination's ViewModel loads data from the repository (`savedStateHandle.toRoute<TaskDetailRoute>()`).
- **The `api` module stays tiny**: routes, `navigateTo…` helpers, and at most a few interfaces. It has no Compose screens and no Hilt modules, so depending on it is nearly free.
- **Top-level destinations** (bottom bar, rail) are listed in `:app` as an enum of routes plus icon and label, so adding a tab never touches another feature.
- **Deep links** are declared on the `composable<…>(deepLinks = …)` entry inside the feature's `impl`; the manifest `<intent-filter>` stays in `:app`.
- **Results back to a caller** go through the previous back stack entry's `SavedStateHandle`, or better, through shared state in a repository. Don't pass callbacks across features.

## Hilt

```kotlin
// :core:data
@Module
@InstallIn(SingletonComponent::class)
internal abstract class DataModule {
    @Binds abstract fun bindsTasksRepository(impl: OfflineFirstTasksRepository): TasksRepository
}

internal class OfflineFirstTasksRepository @Inject constructor(/* … */) : TasksRepository
```

- **Every module installs its own bindings**, in `internal` Hilt modules next to the `internal` implementations. The interface is the only public symbol.
- **Hilt aggregates at `:app`.** Bindings exist only if their module is on `:app`'s runtime classpath. A module reached only through `testImplementation`, or a dynamic feature, needs explicit handling; a "missing binding" error at build time usually means a missing `:app` dependency.
- **Apply Hilt through a convention plugin** (`AndroidHiltConventionPlugin` in `build-logic`) so each module needs one line, not the plugin, KSP, and two dependencies.
- **ViewModels live in feature `impl`** with `@HiltViewModel`; `hiltViewModel()` in the feature's `…Route` composable resolves them.
- **Dynamic feature modules** can't contribute to the `SingletonComponent`. Use Dagger component dependencies with an `@EntryPoint` exposed from `:app`.

## Test replacement

```kotlin
// :core:testing (src/main)
@Module
@TestInstallIn(components = [SingletonComponent::class], replaces = [DataModule::class])
internal abstract class TestDataModule {
    @Binds abstract fun bindsTasksRepository(fake: FakeTasksRepository): TasksRepository
}
```

- **Replace at the same boundary the real module binds.** Feature UI tests depend on `:core:testing` and get fakes automatically.
- **Unit tests don't need Hilt.** Construct the ViewModel with the fake directly; reserve Hilt for instrumented tests.
- **`DataModule` must be visible to the test module** for `replaces = [...]`. If it is `internal`, keep the test module in the same Gradle module's test source set, or make `DataModule` public with a comment saying why.
