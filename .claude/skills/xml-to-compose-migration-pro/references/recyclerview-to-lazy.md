# RecyclerView → LazyColumn / LazyRow

`LazyColumn` (vertical) and `LazyRow` (horizontal) replace `RecyclerView` for the vast majority of list use cases. The mental model is different: instead of an `Adapter` + `ViewHolder` + `DiffUtil`, you write a Composable per item type and provide stable `key`s.

## Minimal translation

**Before** — typical RecyclerView setup:

```kotlin
// MyAdapter.kt
class UserAdapter(
    private val onClick: (User) -> Unit
) : ListAdapter<User, UserAdapter.ViewHolder>(UserDiffCallback) {

    inner class ViewHolder(private val binding: ItemUserBinding) :
        RecyclerView.ViewHolder(binding.root) {
        fun bind(user: User) {
            binding.name.text = user.name
            binding.email.text = user.email
            binding.root.setOnClickListener { onClick(user) }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        ViewHolder(ItemUserBinding.inflate(LayoutInflater.from(parent.context), parent, false))

    override fun onBindViewHolder(holder: ViewHolder, position: Int) =
        holder.bind(getItem(position))
}

object UserDiffCallback : DiffUtil.ItemCallback<User>() {
    override fun areItemsTheSame(old: User, new: User) = old.id == new.id
    override fun areContentsTheSame(old: User, new: User) = old == new
}

// In Fragment:
binding.recyclerView.adapter = UserAdapter(::onUserClick)
viewModel.users.observe(viewLifecycleOwner) { adapter.submitList(it) }
```

Plus `res/layout/item_user.xml` for the item layout.

**After** — Compose:

```kotlin
@Composable
fun UserList(
    users: List<User>,
    onUserClick: (User) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(modifier = modifier) {
        items(users, key = { it.id }) { user ->
            UserRow(user = user, onClick = { onUserClick(user) })
        }
    }
}

@Composable
private fun UserRow(
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
        Column {
            Text(user.name, style = MaterialTheme.typography.bodyLarge)
            Text(user.email, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
```

That's the whole thing. The `Adapter` / `ViewHolder` / `DiffUtil` ceremony is gone. The XML item layout is gone.

## Stable keys are mandatory

`key = { it.id }` is the line that does the work `DiffUtil` did in RecyclerView — it lets Compose match items across emissions so insertions/deletions don't trigger full re-composition of every visible item.

```kotlin
items(users, key = { it.id }) { user -> /* ... */ }
```

Without keys:

- Every emission of a new `users` list causes every visible item to recompose.
- State `remember`'d inside an item Composable is destroyed when items shift positions.
- Animations across list changes can't tell which item moved.

With keys:

- Compose reuses the existing Composable for an item whose key matches across emissions.
- `remember { mutableStateOf(...) }` inside an item survives reordering.
- `LazyColumn` can animate item moves (`Modifier.animateItem()`).

**The key must be unique and stable.** Database IDs are good. List index is bad (`key = { index }` defeats the whole point). UUIDs generated at composition time are *very* bad.

## Multiple item types (RecyclerView's `getItemViewType`)

```kotlin
sealed interface FeedItem {
    data class UserItem(val user: User) : FeedItem
    data class HeaderItem(val title: String) : FeedItem
    data class AdItem(val ad: Ad) : FeedItem
}

@Composable
fun Feed(items: List<FeedItem>, modifier: Modifier = Modifier) {
    LazyColumn(modifier = modifier) {
        items(
            items = items,
            key = { item ->
                when (item) {
                    is FeedItem.UserItem -> "user-${item.user.id}"
                    is FeedItem.HeaderItem -> "header-${item.title}"
                    is FeedItem.AdItem -> "ad-${item.ad.id}"
                }
            },
            contentType = { it::class }   // hint to Compose for view-type reuse
        ) { item ->
            when (item) {
                is FeedItem.UserItem -> UserRow(item.user)
                is FeedItem.HeaderItem -> SectionHeader(item.title)
                is FeedItem.AdItem -> AdCard(item.ad)
            }
        }
    }
}
```

- **Namespace keys across types** (`"user-..."`, `"header-..."`) so a user with `id=42` and an ad with `id=42` don't collide.
- **`contentType = { ... }`** is the rough equivalent of `getItemViewType` — Compose uses it to optimize Composable reuse across scrolling. Optional but recommended for heterogeneous lists.

## Headers and stickies

```kotlin
LazyColumn {
    item { Text("Section A", style = MaterialTheme.typography.titleLarge) }
    items(sectionAItems, key = { it.id }) { /* row */ }

    item { Text("Section B", style = MaterialTheme.typography.titleLarge) }
    items(sectionBItems, key = { it.id }) { /* row */ }
}
```

- **`item { ... }`** (singular) adds one Composable to the list.
- **`items(list, key = ...) { ... }`** (plural) adds many.
- **Sticky headers**: `stickyHeader { ... }` (from `LazyColumn` scope) for headers that pin to the top while scrolling through their section.

## Pagination (Paging 3 + Compose)

```kotlin
val items: LazyPagingItems<User> = viewModel.usersPaged.collectAsLazyPagingItems()

LazyColumn {
    items(
        count = items.itemCount,
        key = items.itemKey { it.id }
    ) { index ->
        val user = items[index] ?: return@items   // null while loading
        UserRow(user = user)
    }

    when (items.loadState.append) {
        is LoadState.Loading -> item { CircularProgressIndicator() }
        is LoadState.Error -> item { ErrorRow(onRetry = items::retry) }
        else -> Unit
    }
}
```

Requires the `androidx.paging:paging-compose` artifact.

## Item animations

```kotlin
LazyColumn {
    items(users, key = { it.id }) { user ->
        UserRow(
            user = user,
            modifier = Modifier.animateItem()   // animates insertion/removal/move
        )
    }
}
```

`Modifier.animateItem()` (previously `animateItemPlacement()`) requires stable keys — it uses them to track item identity across emissions.

## ScrollToTop / scrollTo

```kotlin
val listState = rememberLazyListState()

LazyColumn(state = listState) { /* ... */ }

// Elsewhere — scroll programmatically:
val scope = rememberCoroutineScope()
Button(onClick = { scope.launch { listState.animateScrollToItem(0) } }) {
    Text("Top")
}
```

`LazyListState` exposes `firstVisibleItemIndex`, `firstVisibleItemScrollOffset`, and `layoutInfo` for advanced cases (e.g., "show 'jump to top' button when scrolled past N items"). See the Android Compose best-practices rule for `derivedStateOf` patterns around these.

## Grids

`RecyclerView` with `GridLayoutManager` → `LazyVerticalGrid` / `LazyHorizontalGrid`:

```kotlin
LazyVerticalGrid(
    columns = GridCells.Fixed(3),   // or GridCells.Adaptive(minSize = 120.dp)
    contentPadding = PaddingValues(16.dp),
    horizontalArrangement = Arrangement.spacedBy(8.dp),
    verticalArrangement = Arrangement.spacedBy(8.dp)
) {
    items(photos, key = { it.id }) { photo -> PhotoCell(photo) }
}
```

`GridCells.Adaptive(minSize = ...)` is the responsive variant — columns are computed at runtime based on available width. Often what you want for tablets.

## Common pitfalls

- **No `key` specified.** First thing to fix in any LazyColumn review. Without it, performance and state preservation both suffer.
- **`key = { index }` or `key = { it.toString() }`.** Defeats the whole purpose. Use a real identifier.
- **Heavy work in the item Composable body.** Composes 60 times a second during scroll. Memoize with `remember`, push work to the ViewModel.
- **`Modifier.fillMaxWidth()` on every item.** Items in a `LazyColumn` are already full-width by default. Adding `fillMaxWidth()` is redundant noise.
- **Forgetting `contentType` for heterogeneous lists.** Compose will still work but won't reuse Composables across types, hurting scroll performance.
- **Loading an entire massive list into memory** instead of using Paging. RecyclerView's lazy loading had this problem too; `LazyColumn` doesn't paginate by itself.
- **Item state stored in `remember` without keys.** State survives only if the item's `key` survives. If you `remember { mutableStateOf(0) }` inside an item Composable without keys, the state gets destroyed every time the list reshuffles.
