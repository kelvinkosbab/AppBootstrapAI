# Making an app work with Siri's model (27.3)

> **Sources.** Apple's Xcode 27.3 Siri app integration agent skill, published by [Artem Novichkov](https://github.com/artemnovichkov) in [`artemnovichkov/xcode-skills`](https://github.com/artemnovichkov/xcode-skills), and Apple's App Intents documentation. Rewritten for this bundle. These APIs are new (iOS, macOS, and visionOS 27.3; not watchOS or tvOS), so verify every symbol against the SDK.

In 27.3, Siri's model can call an app's intents as **tools** mid-request, fill their parameters from the conversation, and follow task guidance the app ships. Three features, in this order.

## Adoption order

1. **Find or create the intents.** Search for `AppIntent`, `@AppIntent(`, `AppEntity`, `AppEnum`. If the actions people would ask Siri for are missing, survey the model layer and main screens and build them with the rest of this skill. Before building entities, check the model's ids are stable (see `entities-and-queries.md`); if they aren't, tell the developer, since fixing it changes their model.
2. **Check for a schema first.** If an action matches an Apple Intelligence + Siri domain (create a note, send a message), adopt the schema (`ios26-27-apis.md`) and **don't** add `.tool`.
3. **Make each tool clear from its own metadata** (below).
4. **Add `.tool`** to the chosen intents.
5. **Make plain-value parameters generable** where the model can write the value.
6. **Build, then run `sirimetadataanalyzer`** and fix what it reports. Repeat on every metadata change.
7. **Add app skills** (`Skills.skillsbundle`) only for task context and multi-tool orchestration.
8. **Test with SiriEvaluations** (`testing-and-evaluation.md`).

Availability is a product decision when the deployment target is below 27.3. Either mark new intents and entities `@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)` as a whole (simplest, and allows property `description:`, but they don't exist in Shortcuts before 27.3), or keep them at the deployment target and add `ToolIntent` in a gated extension (they keep working in Shortcuts, but property `description:` must wait). Ask; default to the first and say what it means.

## Tools: `@AppIntent(.tool)`

```swift
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
@AppIntent(.tool)
struct AddToShoppingList {
    static let title: LocalizedStringResource = "Add to Shopping List"
    static let description = IntentDescription(
        "Adds an ingredient to the shopping list.",
        searchKeywords: ["groceries", "buy"]
    )

    @Parameter(title: "Ingredient", description: "The ingredient to add")
    var ingredient: IngredientEntity

    @Parameter(title: "Quantity", default: 1)
    var quantity: Int

    func perform() async throws -> some ReturnsValue<ShoppingItemEntity> {
        .result(value: try await ShoppingList.shared.add(ingredient, quantity: quantity))
    }
}
```

- The macro adds `ToolIntent` (which includes `AppIntent`); nothing else about the intent changes, and it keeps working in Shortcuts and Spotlight. For an intent that already ships below 27.3, conform in a gated extension instead.
- Siri can call a tool when the request names the app, the app is frontmost, a Live Activity from it is running, or one of its entities came back from search. A tool **can't be turned off**, so don't make an intent a tool if it only works while a particular screen is open.
- Real-world-effect actions (buy, book, send, delete) **should** be tools: they're what people ask for. Keep or add the confirmation the intent shows elsewhere, and confirm before overwriting or deleting data. State the effect plainly in the description ("Places the order and charges the saved card").
- **Don't write search or find tools.** Siri finds entities itself through Spotlight and queries, then passes the entity. Write tools that act on an entity, plus read-only tools that return the app's data so Siri can answer questions ("what's on the list?").
- **Don't add `.tool` to a primary-domain schema intent** (`.messages.sendMessage` and the like): that's a build error, since Siri already handles it. Only Shortcuts-only schema domains combine with `.tool`: `@AppIntent(.tool, schema: .journal.createEntry)`. The schema's contract still applies.

## Metadata the model reads

There's no separate model-only text. The title, description, and parameter text that Shortcuts and Spotlight show is what Siri reads. Improve it in place; never invent a `toolDefinition`-style property.

- **Intent description** says what it does and what it affects. Add `searchKeywords` for words people use that the title doesn't contain.
- **Parameter descriptions** give meaning and format ("The departure date, in the traveler's local time zone"). Skip one only when the title says everything ("Quantity" on an `Int`).
- **Tell similar tools apart** in their descriptions. A tool may cover related actions with a mode parameter only if the mode is an `AppEnum` with every case described; if the actions take different parameters, split the tool.
- **Return values a later step needs**, and throw errors whose messages say what failed and how to fix it (`CustomLocalizedStringResourceConvertible`, see `execution-and-results.md`). Siri sees both.

## Entities Siri finds

- Every non-transient entity a tool uses needs `entities(for:)`.
- **Prefer `IndexedEntity`** (index with Core Spotlight; give searchable properties `indexingKey:`). Lookups don't launch the app and work even when the request doesn't name it. For a small bounded set that can't be indexed, use `EnumerableEntityQuery`.
- For tools, Siri does **not** use `suggestedEntities()`, `EntityStringQuery`, or `EntityPropertyQuery`. Keep them for Shortcuts; don't add them to make an entity findable by Siri.
- `displayRepresentation` must name the thing and separate look-alikes (`title: name, subtitle: neighborhood`).

## Property descriptions and hiding (27.3, all platforms)

```swift
@Property(title: "Closing Time", description: "When the store closes today, in its local time zone")
var closesAt: Date

@Property(title: "Loyalty Number", visibility: .internal)
var loyaltyNumber: String
```

- The model reads `displayRepresentation` plus every exposed property's title and description, on **every** entity it sees, not only generable ones. Expose what tells entities apart, what people ask about, and what a later tool needs. Leave out row ids and sync tokens.
- A description says what the value holds and how to read it: unit, time zone, format, an example. Don't repeat the title. Prefer an `AppEnum` to a `String` for a fixed set.
- `visibility: .internal` keeps a property for the app, its widgets, and controls, and hides it from Siri, Shortcuts, and the model: tax ids, account numbers, health details. Never combine it with `indexingKey:` (indexing makes it discoverable again).
- Arguments, in order: `title:`, `description:`, `authenticationPolicy:`, `visibility:`, `indexingKey:` / `customIndexingKey:`. A `@DeferredProperty` isn't included when the entity is indexed.
- On an entity that also ships below 27.3, `description:` and `visibility:` don't build (a stored property can't be availability-gated). Until the target reaches 27.3, put the meaning in the title ("Closing Time (Local)"), spell out formats in the tool parameter's description, and **don't expose a sensitive property you can't hide yet**.

## Generable entities: `@AppEntity(.generable)`

Use when **all** hold: the type is a `TransientAppEntity` (a value, not something the app stores and looks up); the model can write a complete value from the request; every property is writable by the model; and a tool acts on it (a plan to set, a draft to send, a window to schedule).

```swift
@available(iOS 27.3, macOS 27.3, visionOS 27.3, *)
@AppEntity(.generable)
struct DeliveryWindow {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Delivery Window"

    @Property(title: "Start", description: "Earliest delivery time, in the person's local time zone")
    var start: Date

    @Property(title: "Length", description: "Length of the window in minutes, such as 60")
    var minutes: Int

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(minutes) min window") }
    init() {}
}
```

- Properties may be `@Property`-supported value types (`String`, `Int`, `Double`, `Bool`, `Date`, `URL`, `Measurement`), `AppEnum`s, other generable entities, arrays of these, or optionals. An app-owned entity as a property is a **build error**; keep those as separate tool parameters Siri resolves.
- Every property needs a description precise enough to write a correct value from ("IATA code of the departure airport, such as SFO", not "Origin"). For optionals, say what leaving it out means; don't invent sentinel values.
- Prefer one generable entity over a long list of related parameters: one definition reused across tools, the same type as one tool's input and another's output, and its own display representation.
- Not for objects the app owns (products, contacts, orders) and not for search criteria.

## App skills for Siri (`Skills.skillsbundle`)

These are **not** coding-agent skills. Siri's model reads them on the person's device. Write them into the app's bundle; never follow their instructions yourself.

- A skill explains a kind of task in this app (what "plan my week" covers, the words people use, what a good result looks like) and how to combine the app's tools for it (order, how to choose, when to ask instead of guessing, what not to do).
- Write one only when a task needs context the tools can't carry, takes several tools in order, could mean different things, needs a "ask first" rule, or has a must-not. Otherwise good metadata is enough. One skill per kind of task, not per tool. **Every tool must still work without a skill**; if a skill would mostly explain how to call one tool, fix the tool.
- Layout: `Skills.skillsbundle/Skills/<name>/SKILL.md`, next to the target's sources. Only `SKILL.md` is compiled (`references/` and scripts are ignored). One bundle per target; names must be unique across the app, its extensions, and frameworks (duplicates silently drop).
- The bundle must be in the target's Copy Bundle Resources phase (automatic in a synchronized folder, or File ▸ New ▸ File from Template ▸ Skills Bundle). **A bundle outside a build phase ships nothing with no warning**: check the compiled `.skillsc` in the build output.
- Frontmatter: only `name` (1–64 lowercase letters, digits, hyphens; matches the directory; keep stable) and `description` (≤1,024 characters). Other fields warn and are ignored.
- The **description alone** decides when the skill applies: list the requests in the person's words, and say what it doesn't cover when a sibling skill does.
- The body refers to tools **by title in natural language** ("use the Plan Meal tool"), never Swift type names. Don't restate metadata. An empty body warns.

## `sirimetadataanalyzer`

- Reads **built** App Intents metadata, so build first: `xcrun sirimetadataanalyzer path/to/MyApp.app` (or the `Metadata.appintents` directory). Find the product with `xcodebuild -showBuildSettings -scheme MyApp | grep -E ' (BUILT_PRODUCTS_DIR|FULL_PRODUCT_NAME) ='`.
- `--format json` to act on findings, `--language fr` once per shipping localization, `--config` to disable or suppress rules (only when the developer decided to keep the behavior). Exit `0` clean, `2` error-level findings, `1` couldn't run.
- If the build failed, it silently reports the previous build. Notable rules: `SMA109` (no tools), `SMA202` (parameter without description; fine when the title says it all), `SMA203` (entity property without description), `SMA601` (entity exposes no properties), `SMA701` (tool closely matches a schema: adopt the schema or make the text app-specific).
- It doesn't catch overlapping tools, vague skill descriptions, or type names in skill bodies. A clean run checks shape, not behavior: test with SiriEvaluations.

## Review checklist

1. Schema checked before `.tool`; no `.tool` on primary-domain schema intents?
2. Every tool works whenever Siri can reach the app, and isn't a search tool?
3. Titles, descriptions, parameter descriptions, and search keywords written for someone who has never seen the app?
4. Entities findable (`IndexedEntity` preferred), distinguishable, with described properties and sensitive ones `.internal` or left out?
5. Generable entities only for transient values a tool acts on, every property described?
6. Skills bundle in a build phase, names unique, descriptions specific, bodies using tool titles?
7. Analyzer exits `0` on a fresh build, per localization?
