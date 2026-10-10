# Auditing a multi-module build

## Inventory

```bash
# Included modules
grep -oE '":[A-Za-z0-9:_-]+"' settings.gradle.kts | tr -d '"' | sort

# Kotlin files per module
for f in $(find . -name build.gradle.kts -not -path './build-logic/*' -not -path '*/build/*'); do
  d=$(dirname "$f"); printf "%-36s %5d\n" "$d" "$(find "$d/src" -name '*.kt' 2>/dev/null | wc -l)"
done | sort -k2 -n

# What is still in :app (everything but Application, MainActivity, and the NavHost is a candidate)
find app/src/main -name '*.kt' | xargs wc -l | sort -n

# Build flags that make modules pay off
grep -E 'org.gradle.(parallel|caching|configuration-cache)|nonTransitiveRClass' gradle.properties

# The resolved project graph for one module
./gradlew :app:dependencies --configuration releaseRuntimeClasspath | grep -E 'project :'
```

Count before reading files. The counts set the priorities.

## Dependency-rule check

This script reads `settings.gradle.kts` and every included module's `build.gradle.kts`, resolves both `project(":…")` and type-safe `projects.…` accessors, and reports `impl` modules used outside `:app`, feature→feature edges that bypass an `:api` module, features reaching data sources, core modules depending on features, and `api(...)` in feature modules. Test-only configurations are ignored. Adjust `DATA_SOURCES` and the prefixes for the project.

```python
#!/usr/bin/env python3
"""Check a Gradle project's module graph against layer rules.

Usage: python3 check-module-graph.py [project-root]
Reads settings.gradle.kts includes and each module's build.gradle.kts.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
DATA_SOURCES = (":core:database", ":core:network", ":core:datastore")
DEP = re.compile(
    r'(?<![\w.])(\w+)\(\s*(?:project\(\s*"(:[\w:-]+)"\s*\)|projects\.([\w.]+))'
)


def modules():
    settings = (ROOT / "settings.gradle.kts").read_text()
    names = re.findall(r'"(:[\w:-]+)"', " ".join(re.findall(r"include\(([^)]*)\)", settings)))
    return sorted(set(names))


def accessor_key(path):
    # :feature:task-list:impl -> feature.taskList.impl (Gradle's type-safe accessor form)
    parts = path.strip(":").split(":")
    camel = [re.sub(r"[-_](\w)", lambda m: m.group(1).upper(), p) for p in parts]
    return ".".join(camel)


def main():
    mods = modules()
    by_accessor = {accessor_key(m): m for m in mods}
    problems = []
    for mod in mods:
        build = ROOT / mod.strip(":").replace(":", "/") / "build.gradle.kts"
        if not build.exists():
            problems.append(f"{mod}: included but {build} is missing")
            continue
        for config, path, accessor in DEP.findall(build.read_text()):
            dst = path or by_accessor.get(accessor)
            if dst is None or config.startswith(("test", "androidTest", "debug")):
                continue
            if dst.endswith(":impl") and mod != ":app":
                problems.append(f"{mod} → {dst}: only :app may depend on an impl module")
            if mod.startswith(":feature:") and dst.startswith(":feature:"):
                same = mod.split(":")[2] == dst.split(":")[2]
                if not same and not dst.endswith(":api"):
                    problems.append(f"{mod} → {dst}: feature→feature edge (use the :api module)")
            if mod.startswith(":feature:") and dst in DATA_SOURCES:
                problems.append(f"{mod} → {dst}: features go through :core:data")
            if mod.startswith(":core:") and dst.startswith(":feature:"):
                problems.append(f"{mod} → {dst}: core depends on a feature")
            if config == "api" and mod.startswith(":feature:"):
                problems.append(f"{mod}: api({dst}) in a feature module; use implementation")
    for p in problems:
        print(p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
```

Against a project where `:feature:settings` uses `:feature:tasks:impl` and `:feature:tasks:impl` uses `:core:database`, it prints:

```text
:feature:settings → :feature:tasks:impl: only :app may depend on an impl module
:feature:settings → :feature:tasks:impl: feature→feature edge (use the :api module)
:feature:tasks:impl → :core:database: features go through :core:data
```

and exits 1. It is a text scan: dependencies added inside convention plugins or through variables won't show up, so pair it with the Gradle plugin below for the authoritative check.

## Searches

```bash
# Logic left in :app
rg -l '(ViewModel|Repository|@Dao|@GET|@POST|@Entity)' app/src/main

# Resources reached through another module's R (breaks with non-transitive R)
rg -n 'import com\.example\.app\.R$' --glob '!app/**'

# Public Hilt modules and implementations that should be internal
rg -n '^(abstract )?(class|object) \w+Module\b' -g '**/src/main/**/*.kt'   # lines without `internal`

# Features importing data-source types directly
rg -ln 'import .*\.(database|network)\.' feature

# Modules missing tests
for d in $(find feature core -name build.gradle.kts -exec dirname {} \;); do
  [ -d "$d/src/test" ] || echo "no unit tests: $d"
done
```

## Enforcing the graph in Gradle

[module-graph-assertion](https://github.com/jraska/modules-graph-assert) checks the resolved graph, including dependencies added by convention plugins. A configuration in the root `build.gradle.kts` along these lines (verify the DSL against the plugin's README for the version you pin):

```kotlin
plugins {
    alias(libs.plugins.module.graph.assertion)
}

moduleGraphAssert {
    maxHeight = 6
    restricted = arrayOf(
        ":feature:.* -X> :feature:.*:impl",          // no feature reaches another feature's impl
        ":feature:.* -X> :core:(database|network|datastore)",
        ":core:.* -X> :feature:.*",
    )
    allowed = arrayOf(":app -> .*", ":feature:.* -> :core:.*", ":feature:.* -> :feature:.*:api", ":core:.* -> :core:.*")
}
```

Run it with `./gradlew assertModuleGraph`. For a picture of the graph, Now in Android's `build-logic` includes a graph task that writes a Mermaid diagram per module; generate one for the README.

## Check by hand

- **`:app` is the only module with `NavHost`**, and the only module depending on `impl` modules.
- **`:api` modules contain no screens and no Hilt modules.**
- **`:core:model` applies `kotlin("jvm")`**, not an Android plugin.
- **Shared modules set `resourcePrefix`**, and no module imports another module's `R` for resources it doesn't own.
- **`CLAUDE.md` lists every module** in `settings.gradle.kts`.

## CI job

```yaml
# .github/workflows/android-modules.yml
name: Android modules
on:
  pull_request:
    paths: ['android/**', '.github/workflows/android-modules.yml']
jobs:
  check:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: android } }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: gradle/actions/setup-gradle@v4      # remote build cache + configuration cache
      - run: python3 scripts/check-module-graph.py .
      - run: ./gradlew assertModuleGraph testDebugUnitTest lintDebug --configuration-cache
```

Drop the `working-directory` for a single-platform repo. For large builds, run only affected modules on pull requests (for example with a dependency-aware task selector) and the full suite on `main`.
