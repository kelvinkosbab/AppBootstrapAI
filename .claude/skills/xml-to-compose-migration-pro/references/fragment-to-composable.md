# Fragment → Composable

A typical Android Fragment is doing four things: holding a lifecycle, hosting a layout, observing ViewModel state, and handling user interactions. Composables collapse this into a single function with much less ceremony.

## The mapping

| Fragment concern | Composable equivalent |
|------------------|------------------------|
| `onCreateView` returning a View | The Composable's body |
| `ViewBinding` (`binding.textView.text = ...`) | Function parameters and Composable composition |
| `viewLifecycleOwner.lifecycleScope` for coroutines | `LaunchedEffect` / `rememberCoroutineScope` |
| `viewLifecycleOwner.repeatOnLifecycle(STARTED)` | `collectAsStateWithLifecycle()` |
| Fragment arguments (`requireArguments()`) | Function parameters via `NavBackStackEntry.arguments` (see `navigation-migration.md`) |
| `findNavController().navigate(...)` | `navController.navigate(...)` passed in or from `LocalNavController` |
| `viewModels()` / `activityViewModels()` | `viewModel()` / `hiltViewModel()` |
| `registerForActivityResult(...)` | `rememberLauncherForActivityResult(...)` |
| `setFragmentResult` / `setFragmentResultListener` | `NavBackStackEntry.savedStateHandle` for navigation-result returns |

## A typical Fragment, translated

**Before:**

```kotlin
@AndroidEntryPoint
class SettingsFragment : Fragment() {

    private var _binding: FragmentSettingsBinding? = null
    private val binding get() = _binding!!

    private val viewModel: SettingsViewModel by viewModels()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentSettingsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        binding.saveButton.setOnClickListener { viewModel.save() }
        binding.nameField.doAfterTextChanged { viewModel.onNameChanged(it.toString()) }

        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.state.collect { state ->
                    binding.nameField.setText(state.name)
                    binding.saveButton.isEnabled = state.isValid
                    binding.errorText.text = state.error
                    binding.errorText.isVisible = state.error.isNotEmpty()
                }
            }
        }
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }
}
```

**After:**

```kotlin
@Composable
fun SettingsScreen(
    onSaveComplete: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    // One-shot side effect for the navigation
    LaunchedEffect(state.saveStatus) {
        if (state.saveStatus == SaveStatus.Success) {
            onSaveComplete()
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        OutlinedTextField(
            value = state.name,
            onValueChange = viewModel::onNameChanged,
            label = { Text(stringResource(R.string.name)) },
            isError = state.error.isNotEmpty(),
            supportingText = {
                if (state.error.isNotEmpty()) Text(state.error)
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        Button(
            onClick = viewModel::save,
            enabled = state.isValid
        ) {
            Text(stringResource(R.string.save))
        }
    }
}
```

Lines: 38 (Fragment + binding boilerplate) → 24 (Composable). The lifecycle handling, the binding cleanup, the `repeatOnLifecycle` ceremony — all gone.

## Activity results (camera, gallery, permissions)

```kotlin
@Composable
fun CameraScreen() {
    val context = LocalContext.current
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED
        )
    }

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasPermission = granted
    }

    if (!hasPermission) {
        Button(onClick = { launcher.launch(Manifest.permission.CAMERA) }) {
            Text("Grant camera permission")
        }
    } else {
        CameraPreview(/* ... */)
    }
}
```

`rememberLauncherForActivityResult` returns a `ManagedActivityResultLauncher` that survives recomposition and config changes. Same `ActivityResultContracts` you'd use in a Fragment.

## Lifecycle effects

Compose has explicit effect Composables for lifecycle work:

| Fragment hook | Composable equivalent |
|---------------|------------------------|
| `onViewCreated` once-only setup | `LaunchedEffect(Unit) { ... }` |
| Re-run when a key changes | `LaunchedEffect(key) { ... }` |
| Pair of setup + teardown | `DisposableEffect(key) { onDispose { ... } }` |
| Run-after-composition publish | `SideEffect { ... }` |
| Coroutine for click handler | `rememberCoroutineScope()` |
| Re-run on screen resume | `LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { ... }` (from `lifecycle-runtime-compose`) |

See `android-compose-best-practices.md` (the Compose rule) for which to pick when.

## Navigation arguments

```kotlin
// Fragment with Safe Args:
private val args: SettingsFragmentArgs by navArgs()
val userId = args.userId

// Composable with Navigation-Compose:
@Composable
fun SettingsScreen(
    userId: String,            // passed in as a parameter
    viewModel: SettingsViewModel = hiltViewModel()
) { ... }

// In the NavHost:
NavHost(navController, startDestination = "home") {
    composable(
        route = "settings/{userId}",
        arguments = listOf(navArgument("userId") { type = NavType.StringType })
    ) { backStackEntry ->
        val userId = backStackEntry.arguments?.getString("userId") ?: return@composable
        SettingsScreen(userId = userId, onSaveComplete = { navController.popBackStack() })
    }
}
```

See `navigation-migration.md` for type-safe routes.

## Returning results to the previous screen

Fragment's `setFragmentResult` → Navigation-Compose's `savedStateHandle`:

```kotlin
// In the destination screen:
navController.previousBackStackEntry
    ?.savedStateHandle
    ?.set("settings_updated", true)
navController.popBackStack()

// In the origin screen:
val result = navController.currentBackStackEntry
    ?.savedStateHandle
    ?.getLiveData<Boolean>("settings_updated")
    ?.observeAsState()
```

Or use a shared ViewModel with a navigation-graph scope (`hiltViewModel<MyVM>(navBackStackEntry)` keyed to a parent route). Generally cleaner than `savedStateHandle` for non-trivial result passing.

## What goes away

- **No `onCreateView` / `onDestroyView`** — composition handles lifecycle.
- **No `_binding` / `binding` ceremony** — children compose directly.
- **No `viewLifecycleOwner.lifecycleScope.launch { repeatOnLifecycle(STARTED) { ... } }`** — `collectAsStateWithLifecycle()` packages this.
- **No `findNavController()` ceremony** — `navController` is a parameter (passed in or via `LocalNavController.current` if you've set up an injection point).
- **No `inflate(layoutInflater)`** — Compose has no separate inflation.
- **No XML preview** — replaced by `@Preview` Composables.

## What stays the same

- **ViewModels.** Existing ViewModels move over unchanged — see `viewmodel-bridge.md`.
- **`@AndroidEntryPoint`** — Activities still need it (your `MainActivity` keeps it). Composables don't.
- **Activity callbacks** (`onBackPressed`) — handled via `BackHandler { ... }` Composable.
- **Process death / saved instance state** — `rememberSaveable` for screen-local state; `SavedStateHandle` for ViewModel state.

## Migrating a stateful Fragment with multiple sub-screens

Fragments that internally swap child fragments or use `viewLifecycleOwner` for tab-like behavior often translate to a Composable with internal state:

```kotlin
@Composable
fun OnboardingScreen(viewModel: OnboardingViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    when (state.currentStep) {
        OnboardingStep.Welcome -> WelcomeStep(onNext = viewModel::next)
        OnboardingStep.Permissions -> PermissionsStep(onGranted = viewModel::next)
        OnboardingStep.Profile -> ProfileStep(onComplete = viewModel::finish)
    }
}
```

The `when` branches replace the old "show fragment A, then transition to fragment B" pattern. State lives in the ViewModel; navigation between steps is just state changes.

## Common pitfalls

- **Recreating the screen on every recomposition.** The Composable runs many times a frame. State must be in `remember` / `rememberSaveable` / a `ViewModel` — not local variables.
- **Calling `viewModel.doSomething()` directly in the Composable body.** That runs on every recomposition. Wrap in `LaunchedEffect`, `Button { onClick = ... }`, or trigger from state changes.
- **`LiveData.observe(viewLifecycleOwner, ...)` in a Composable.** Use `liveData.observeAsState()` or migrate the ViewModel to `StateFlow`.
- **`Fragment.requireContext()` patterns** — Composables use `LocalContext.current` instead.
- **Forgetting `BackHandler`** for back-button intercepts. Compose doesn't proxy to `Activity.onBackPressed` automatically.
- **Process death** — local Composable state (`remember { mutableStateOf(...) }`) is lost. Use `rememberSaveable` for state that should survive, or push it to the ViewModel's `SavedStateHandle`.
