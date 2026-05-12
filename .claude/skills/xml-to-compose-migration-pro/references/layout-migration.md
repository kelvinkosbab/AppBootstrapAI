# Layout Migration: XML → Compose

XML layouts map to Compose layout Composables. The translation isn't always literal — Compose's Modifier-based model often produces cleaner code than the XML equivalent.

## Direct equivalents

| XML | Compose |
|-----|---------|
| `<LinearLayout android:orientation="vertical">` | `Column` |
| `<LinearLayout android:orientation="horizontal">` | `Row` |
| `<FrameLayout>` | `Box` |
| `<ScrollView>` | `Modifier.verticalScroll(rememberScrollState())` |
| `<HorizontalScrollView>` | `Modifier.horizontalScroll(rememberScrollState())` |
| `<View android:layout_width="match_parent">` | `Spacer(modifier = Modifier.fillMaxWidth())` |
| `<TextView>` | `Text` |
| `<ImageView>` | `Image` (with `painterResource` or `rememberAsyncImagePainter` for Coil) |
| `<Button>` | `Button { Text(...) }` or `TextButton` |
| `<EditText>` | `OutlinedTextField` / `TextField` |
| `<Switch>` | `Switch` |
| `<CheckBox>` | `Checkbox` |
| `<RadioButton>` | `RadioButton` |
| `<ProgressBar style="?android:progressBarStyle">` | `CircularProgressIndicator` |
| `<ProgressBar style="?android:progressBarStyleHorizontal">` | `LinearProgressIndicator` |
| `<View android:background="?attr/dividerColor">` | `HorizontalDivider` / `VerticalDivider` |

## Dimension attributes

| XML | Compose |
|-----|---------|
| `android:layout_width="match_parent"` | `Modifier.fillMaxWidth()` |
| `android:layout_width="wrap_content"` | (default — don't add anything) |
| `android:layout_width="100dp"` | `Modifier.width(100.dp)` |
| `android:layout_height="0dp" android:layout_weight="1"` | `Modifier.weight(1f)` (inside `Row`/`Column`) |
| `android:padding="16dp"` | `Modifier.padding(16.dp)` |
| `android:paddingHorizontal="16dp"` | `Modifier.padding(horizontal = 16.dp)` |
| `android:layout_marginStart="8dp"` | `Modifier.padding(start = 8.dp)` (Compose folds margin into padding) |

**Compose has no `margin` — only `padding`.** This is a deliberate simplification. The visual effect of `margin` in a layout is achieved by padding on the *outer* container or by `Spacer`s.

## `ConstraintLayout`

For complex constraint-based layouts, Compose has a `ConstraintLayout` Composable in the `androidx.constraintlayout:constraintlayout-compose` artifact:

```kotlin
ConstraintLayout(modifier = Modifier.fillMaxSize()) {
    val (title, subtitle, image) = createRefs()

    Text("Hello", modifier = Modifier.constrainAs(title) {
        top.linkTo(parent.top, margin = 16.dp)
        start.linkTo(parent.start, margin = 16.dp)
    })

    Text("World", modifier = Modifier.constrainAs(subtitle) {
        top.linkTo(title.bottom, margin = 4.dp)
        start.linkTo(title.start)
    })

    Image(painter = ..., contentDescription = null,
        modifier = Modifier.constrainAs(image) {
            top.linkTo(parent.top)
            end.linkTo(parent.end)
        })
}
```

**Most XML `ConstraintLayout`s should NOT translate to Compose's `ConstraintLayout`.** They're easier to write as nested `Column` / `Row` / `Box`. Reach for `ConstraintLayout` only when the constraint graph is genuinely non-trivial (overlapping elements, complex chain bias, guidelines).

## Weight (LinearLayout's killer feature)

```xml
<LinearLayout android:orientation="horizontal">
    <View android:layout_width="0dp"
          android:layout_height="match_parent"
          android:layout_weight="1" />
    <View android:layout_width="0dp"
          android:layout_height="match_parent"
          android:layout_weight="2" />
</LinearLayout>
```

```kotlin
Row(modifier = Modifier.fillMaxSize()) {
    Spacer(modifier = Modifier.weight(1f))
    Spacer(modifier = Modifier.weight(2f))
}
```

Same proportional sizing. Weight is only available *inside* a `Row` or `Column` — it's an extension property on those scopes.

## Alignment and gravity

| XML | Compose |
|-----|---------|
| `android:gravity="center"` (on a parent) | `Box(contentAlignment = Alignment.Center)` / `Row(horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically)` |
| `android:layout_gravity="end"` (on a child) | `Modifier.align(Alignment.End)` (Row/Column scope) |
| `android:textAlignment="center"` | `Text(textAlign = TextAlign.Center)` |
| `android:gravity="start|center_vertical"` (on TextView) | `Text(textAlign = TextAlign.Start)` + vertical centering via parent |

## Spacing

```kotlin
// Instead of <View android:layout_height="16dp" />:
Spacer(modifier = Modifier.height(16.dp))

// Or use Arrangement on the parent:
Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
    Text("First")
    Text("Second")  // automatically 16.dp below First
    Text("Third")   // automatically 16.dp below Second
}
```

`Arrangement.spacedBy(N.dp)` is cleaner than peppering `Spacer`s between children. Use it when the spacing is uniform.

## Visibility

| XML | Compose |
|-----|---------|
| `android:visibility="visible"` | (just render the Composable) |
| `android:visibility="gone"` | `if (condition) { Composable() }` (the Composable is not in the tree) |
| `android:visibility="invisible"` | `Modifier.alpha(0f)` (still takes space) |
| Animated visibility | `AnimatedVisibility(visible = condition) { Composable() }` |

There's no direct `gone` analog — Compose uses control flow. `if (x) Foo()` produces the same result as `View.GONE` but the View isn't measured at all.

## A real-world translation

```xml
<!-- res/layout/item_user.xml -->
<LinearLayout
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:padding="16dp"
    android:gravity="center_vertical">

    <ImageView
        android:layout_width="40dp"
        android:layout_height="40dp"
        android:contentDescription="@string/avatar"
        android:src="@drawable/ic_avatar" />

    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:layout_marginStart="12dp"
        android:orientation="vertical">

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textAppearance="?attr/textAppearanceBodyLarge" />

        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:textAppearance="?attr/textAppearanceBodyMedium" />
    </LinearLayout>

    <ImageView
        android:layout_width="24dp"
        android:layout_height="24dp"
        android:contentDescription="@null"
        android:src="@drawable/ic_chevron" />
</LinearLayout>
```

```kotlin
@Composable
fun UserRow(
    user: User,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Image(
            painter = painterResource(R.drawable.ic_avatar),
            contentDescription = stringResource(R.string.avatar),
            modifier = Modifier.size(40.dp)
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp)
        ) {
            Text(user.name, style = MaterialTheme.typography.bodyLarge)
            Text(user.email, style = MaterialTheme.typography.bodyMedium)
        }
        Icon(
            painter = painterResource(R.drawable.ic_chevron),
            contentDescription = null,  // decorative
            modifier = Modifier.size(24.dp)
        )
    }
}
```

The Compose version is ~25 lines vs 35 for the XML, and it's compile-time-checked Kotlin.

## Common pitfalls

- **Translating margin to margin.** Compose has no margin. Use `padding` on the next outer container, or use `Arrangement.spacedBy`.
- **Translating XML 1:1 instead of idiomatically.** A `LinearLayout` with a single child and `gravity="center"` translates to `Box(contentAlignment = Alignment.Center) { Foo() }`, not a `Column` with `Modifier.fillMaxWidth().wrapContentHeight()`.
- **`Modifier.fillMaxWidth()` overusage** — it's the default for many layout Composables (e.g., `Column` doesn't need it). Only specify when you're overriding a wrap-content default.
- **Modifier order matters.** `Modifier.padding(8.dp).background(Color.Red)` ≠ `Modifier.background(Color.Red).padding(8.dp)`. The first has red inset by padding; the second has padding inside the red. See `apple-compose-best-practices.md` (the Android Compose rule) for the layout-then-drawing-then-input order.
- **Using XML `?attr` references in Compose.** Compose uses `MaterialTheme.colorScheme.X` / `MaterialTheme.typography.Y`, not `?attr/colorPrimary`. See `themes-styles.md`.
- **Forgetting `contentDescription` on `Image`.** Decorative images pass `null`; meaningful ones pass `stringResource(...)`. Lint catches this.
