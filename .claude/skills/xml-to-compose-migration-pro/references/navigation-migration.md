# Navigation Component → Navigation-Compose

XML `nav_graph.xml` files translate to a `NavHost` Composable with `composable(route = "...")` entries. The mental shift: routes are strings (or type-safe sealed classes), not XML destinations with auto-generated `Args` classes.

## Minimal translation

**Before** — `res/navigation/nav_graph.xml`:

```xml
<navigation
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    app:startDestination="@id/homeFragment">

    <fragment
        android:id="@+id/homeFragment"
        android:name="com.example.HomeFragment">
        <action
            android:id="@+id/action_home_to_settings"
            app:destination="@id/settingsFragment" />
    </fragment>

    <fragment
        android:id="@+id/settingsFragment"
        android:name="com.example.SettingsFragment">
        <argument
            android:name="userId"
            app:argType="string" />
    </fragment>
</navigation>
```

**After** — Kotlin:

```kotlin
@Composable
fun AppNavHost(modifier: Modifier = Modifier) {
    val navController = rememberNavController()

    NavHost(
        navController = navController,
        startDestination = "home",
        modifier = modifier
    ) {
        composable("home") {
            HomeScreen(
                onNavigateToSettings = { userId ->
                    navController.navigate("settings/$userId")
                }
            )
        }

        composable(
            route = "settings/{userId}",
            arguments = listOf(navArgument("userId") { type = NavType.StringType })
        ) { backStackEntry ->
            val userId = backStackEntry.arguments?.getString("userId").orEmpty()
            SettingsScreen(
                userId = userId,
                onBack = { navController.popBackStack() }
            )
        }
    }
}
```

## Type-safe routes (recommended)

String-based routes are error-prone. Better: a sealed-class hierarchy that encodes routes + arguments:

```kotlin
sealed class Route(val template: String) {
    data object Home : Route("home")

    data class Settings(val userId: String) : Route("settings/$userId") {
        companion object {
            const val TEMPLATE = "settings/{userId}"
            val arguments = listOf(navArgument("userId") { type = NavType.StringType })
        }
    }
}

@Composable
fun AppNavHost() {
    val navController = rememberNavController()
    NavHost(navController, startDestination = Route.Home.template) {
        composable(Route.Home.template) {
            HomeScreen(onNavigate = { navController.navigate(Route.Settings("42").template) })
        }
        composable(
            route = Route.Settings.TEMPLATE,
            arguments = Route.Settings.arguments
        ) { backStackEntry ->
            SettingsScreen(userId = backStackEntry.arguments!!.getString("userId")!!)
        }
    }
}
```

Or use the **Navigation-Compose type-safe API** (newer, requires Kotlin Serialization):

```kotlin
@Serializable data object Home
@Serializable data class Settings(val userId: String)

NavHost(navController, startDestination = Home) {
    composable<Home> { HomeScreen(...) }
    composable<Settings> { backStackEntry ->
        val args: Settings = backStackEntry.toRoute()
        SettingsScreen(userId = args.userId)
    }
}

// Navigate:
navController.navigate(Settings(userId = "42"))
```

The type-safe API is the modern direction. Use it for new code.

## Deep links

```kotlin
composable(
    route = "settings/{userId}",
    arguments = listOf(navArgument("userId") { type = NavType.StringType }),
    deepLinks = listOf(navDeepLink { uriPattern = "https://example.com/settings/{userId}" })
) { /* ... */ }
```

Configure the `<intent-filter>` in `AndroidManifest.xml` as before; `navDeepLink` wires it through.

## Bottom navigation

```kotlin
@Composable
fun MainScreen() {
    val navController = rememberNavController()
    val currentRoute = navController.currentBackStackEntryAsState()
        .value?.destination?.route

    Scaffold(
        bottomBar = {
            NavigationBar {
                BottomTabs.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = currentRoute == tab.route,
                        onClick = {
                            navController.navigate(tab.route) {
                                popUpTo(navController.graph.startDestinationId) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Icon(tab.icon, contentDescription = null) },
                        label = { Text(tab.label) }
                    )
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = BottomTabs.Home.route,
            modifier = Modifier.padding(padding)
        ) {
            BottomTabs.entries.forEach { tab ->
                composable(tab.route) { tab.screen() }
            }
        }
    }
}
```

`popUpTo(startDestinationId) { saveState = true }` + `restoreState = true` is the magic that makes back-stack-per-tab work — without it, tabs share a single back stack and lose state on switch.

## Nested navigation graphs

```kotlin
NavHost(navController, startDestination = "auth") {
    navigation(startDestination = "auth/login", route = "auth") {
        composable("auth/login") { LoginScreen(...) }
        composable("auth/signup") { SignupScreen(...) }
    }
    navigation(startDestination = "main/home", route = "main") {
        composable("main/home") { HomeScreen(...) }
        composable("main/profile") { ProfileScreen(...) }
    }
}

// Navigate from auth to main:
navController.navigate("main") {
    popUpTo("auth") { inclusive = true }   // clear auth from back stack
}
```

## Result passing

See `fragment-to-composable.md` — `savedStateHandle` on the previous back stack entry, or shared ViewModels keyed to a nav-graph route.

## Migration steps for an XML nav graph

1. **Identify destinations** — each `<fragment>` becomes a `composable("route")`.
2. **Identify arguments** — `<argument>` becomes `navArgument("name") { type = ... }`.
3. **Identify actions** — `<action>` becomes a navigation lambda passed to the source screen (`onNavigateToSettings: (String) -> Unit`).
4. **Identify deep links** — `<deepLink>` becomes `navDeepLink { uriPattern = ... }`.
5. **Identify global actions** — these become methods on the `navController` accessible to every composable in the host.
6. **Identify nested graphs** — `<navigation>` becomes a `navigation(...)` block inside the parent `NavHost`.
7. **Delete the XML graph** *after* every destination is migrated.

## Common pitfalls

- **Forgetting to provide `arguments = listOf(...)`** on the destination — routes resolve, arguments are null at runtime.
- **`navController` lost across configuration changes** — `rememberNavController()` is correct; storing it in a `remember` without that helper is wrong.
- **Navigating from a side effect that runs on every recomposition** — `LaunchedEffect(key) { if (condition) navController.navigate(...) }` is the right shape; calling `navController.navigate(...)` directly in the Composable body navigates many times.
- **Bottom-tab nav without `popUpTo(startDestinationId) { saveState = true }`** — accumulating back stack, app feels broken after a few tab switches.
- **String-typed routes scattered across files** — strings drift. Centralize in a `Routes` object or use the type-safe Serializable API.
- **Hybrid XML nav + NavHost in the same app** — only viable during a transition. Aim for a single nav source by the end of migration.
- **Forgetting `popUpTo` on auth → main transitions** — user can press back from main and end up at the login screen. `popUpTo("auth") { inclusive = true }` clears auth from the back stack.
