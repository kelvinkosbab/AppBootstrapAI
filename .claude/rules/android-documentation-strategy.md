---
description: KDoc strategy for Android — what to document, public API discipline, Composable docs, deprecation, Dokka conventions, and project-specific markdown
globs: "**/*.{kt,kts}"
---

# Android Documentation Strategy

KDoc is Kotlin's doc-comment format, rendered by Dokka into HTML/markdown. This rule covers *what* code needs docs and *how to shape them* — Compose, coroutines, Hilt, and the Android-specific quirks (KSP-generated code, `@Composable` receivers, suspend functions).

## What to Document

Every public top-level declaration, public class, public function, public property:

- **Summary** — one line, ends with a period. Becomes the IDE tooltip and Dokka's index entry.
- **Discussion** — a paragraph or two when the surface needs explanation.
- **`@param name`** for each parameter. *Don't* skip parameters whose name happens to match the doc — name them so the rendered docs make sense in isolation.
- **`@return`** for non-`Unit` returns.
- **`@throws ExceptionType`** for documented exceptions, including `CancellationException` if relevant for suspend functions.
- **`@property name`** on the *class* doc for primary-constructor properties (Kotlin doesn't have separate accessors, so per-property KDoc on the class itself is the convention).
- **`@sample fully.qualified.path.to.SampleFunction`** for non-obvious usage. Dokka build *fails* on missing samples — let it.
- **`@see`** for related symbols.

For Composables specifically, also document:

- **What state the Composable reads vs. hoists.**
- **Which side effects fire** (`LaunchedEffect`, `DisposableEffect`).
- **Semantics it exposes to TalkBack** (role, contentDescription, mergeDescendants).
- **Whether it's skippable** (parameters are stable / immutable types) or always restartable.

For Hilt modules:

- **`@Module`** docs explain *what's bound* and *in what scope*.
- **`@Provides`** docs explain non-obvious construction (e.g., why a singleton, why a factory wrapper).

## What NOT to Document

- **The signature in prose.** *"Returns a `String` representing the user's name"* on `val name: String` is noise.
- **Generated code.** Hilt-generated factories, KSP outputs, Room-generated DAOs — Dokka skips them and so should you.
- **Trivial properties** the name already explains.
- **`override fun`** that purely delegates to `super` — let the IDE pull the parent doc. Document overrides only when behavior actually differs.
- **`@Preview` functions** — they exist for Android Studio; no consumer ever sees them rendered as docs.

## KDoc Mechanics

```kotlin
/**
 * Returns the user with the given identifier, or `null` if no such user exists.
 *
 * Hits the network on cache miss; the call is suspending and respects task
 * cancellation. Cancelling the surrounding [CoroutineScope] aborts the lookup
 * without throwing.
 *
 * @param userId The user's stable identifier.
 * @param scope The [CoroutineScope] used for the network request.
 * @return The matching [User], or `null` if no record exists.
 * @throws IOException if the network is unavailable and there's no cache hit.
 * @sample com.example.samples.findUserSample
 * @see User
 */
suspend fun findUser(userId: String, scope: CoroutineScope): User? = ...
```

- **First line is the summary**, ending with a period. Dokka and the IDE show only the first paragraph in tooltips.
- **Blank line** between summary and discussion.
- **Symbol references in square brackets:** `[User]`, `[findUser]` — Dokka resolves them to links. Don't use single backticks for symbols you want linked (those are *just* code formatting).
- **Markdown is supported:** `*emphasis*`, `**strong**`, `[link text](https://example.com)`, lists, code fences.

## Composable Documentation

```kotlin
/**
 * A counter row that increments on tap.
 *
 * State is hoisted — pass [count] in and [onIncrement] out. Internal use of
 * [Modifier.semantics] (`mergeDescendants = true`) makes the row a single
 * TalkBack node with [Role.Button] semantics.
 *
 * @param count The current value to display.
 * @param onIncrement Called when the row is tapped.
 * @param modifier Hoisted modifier; defaults to [Modifier].
 */
@Composable
fun CounterRow(
    count: Int,
    onIncrement: () -> Unit,
    modifier: Modifier = Modifier
) { ... }
```

- Document **what state the Composable reads** so callers know what to hoist.
- Document **the a11y surface** so TalkBack-level reviewers don't have to read the body.
- Mention `@Stable` / `@Immutable` parameter requirements if the Composable's skipping depends on them.

## Deprecation Discipline

```kotlin
@Deprecated(
    message = "Use findUserById(id) — the new API is suspending and respects cancellation.",
    replaceWith = ReplaceWith("findUserById(id)"),
    level = DeprecationLevel.WARNING
)
fun lookupUser(id: String): User? { ... }
```

- **`message:` is mandatory** — the *why* and the *what to use instead*.
- **`replaceWith:`** for clean renames; the IDE auto-fix surfaces it.
- **Escalate** `WARNING` → `ERROR` → `HIDDEN` over consecutive releases. Don't leave deprecations in the codebase forever.
- **No deprecation without a migration story.** "Deprecated, we'll figure it out" is decay.

## Suspend / Coroutines Documentation

- **Cancellation behavior** — does the function check `Task.isCancelled` mid-flight? Does it throw `CancellationException` or return early? Does it have non-cancellable cleanup (`NonCancellable`)?
- **Dispatcher requirements** — *"Must be called from the main thread"* / *"Switches to `Dispatchers.IO` internally"*.
- **`@throws CancellationException`** if the function deliberately re-throws cancellation; otherwise omit (it's the default).

## Dokka

- Build with `./gradlew dokkaHtml` (or `dokkaGfm` for GitHub-flavored Markdown output).
- **`module.md`** at the module root supplies the module-level intro Dokka renders at the top of the API site.
- **External documentation links** for stdlib / AndroidX / Compose:

  ```kotlin
  // build.gradle.kts
  tasks.dokkaHtml.configure {
      dokkaSourceSets.configureEach {
          externalDocumentationLink {
              url.set(URL("https://developer.android.com/reference/"))
          }
      }
  }
  ```

  This makes `[Activity]` / `[Composable]` resolve to live Android docs.

## ktlint and KDoc

- ktlint enforces blank-line-before-KDoc on most public declarations.
- Run `./gradlew ktlintFormat` before commits — it auto-fixes spacing inside KDoc.

## Common Pitfalls

- **Restating the signature in prose.**
- **Single backticks for symbol references** — those don't link in Dokka. Use `[Symbol]` brackets.
- **Multi-paragraph first lines** — only the first paragraph reaches the IDE tooltip / Dokka summary.
- **`@param this`** — KDoc has no `this`-parameter convention. If you mean the receiver type, document the receiver in the discussion.
- **Out-of-date `@sample` references** — Dokka fails the build on missing samples. Wire that into CI.
- **KDoc on overrides that delegate to super** — let the IDE pull the parent doc.
- **`@Composable` docs that don't mention state hoisting** — the most important question for any Composable consumer.
- **Hilt module docs that say "binds dependencies"** — that's the annotation's job; document *what* and *why*.
- **Markdown that Dokka doesn't render** — stick to backticks, brackets, asterisks, links, lists, fenced code.
