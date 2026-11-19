# Contributor Atlas

A local, native macOS app for exploring this repository’s contributors. SwiftUI,
Swift Charts and AppKit; no web server, backend deployment, npm dependencies, or
external analytics service. Requires macOS 14+ and Xcode command-line tools to build.

```sh
# From the repository root:
tools/contributor-atlas/build-app.sh --install
open "$HOME/Applications/Contributor Atlas.app" --args --repo "$PWD"

# Development and tests:
swift run --package-path tools/contributor-atlas ContributorAtlas --repo "$PWD"
swift test --package-path tools/contributor-atlas

# Machine-readable analysis of the same data model:
swift run --package-path tools/contributor-atlas ContributorAtlas --repo "$PWD" --report
```

The build also produces `dist/Contributor Atlas.app`. It is locally ad-hoc signed;
public distribution would need an Apple Developer signature and notarization.
The app remembers the last selected repository. **⌘O** opens another repository,
**⌘R** refreshes history, and **⇧⌘E** exports filtered commits as CSV.
**⌘[ / ⌘]** navigate back/forward; **⌘1–5** switch sections. The native toolbar
also has back/forward buttons and a collapsible, resizable sidebar.

## Views

- **Overview:** GitHub-style annual contribution calendar, daily timeline, hourly
  histogram, grouped contributor table with sparklines, weekday/hour heatmap.
- **Contributors:** comparative activity and work-area matrix; select a person for
  individual calendars, frequency, work profile, frequently touched files, and commits.
- **Work areas:** contributor × area matrix and participation by category. Select a
  matrix cell to intersect person and work-area filters.
- **Commit history:** paginated, searchable evidence with a changed-file inspector.
- **Methodology:** definitions, scope, identity heuristics and path rules.

All filters intersect: date range, person, area, search, people/bots, merges,
selected day, weekday, and hour. Click heatmap cells or bars to drill down; clear
chips to remove individual constraints. Timezones: Los Angeles, UTC, author-local.
Export includes all matching commits, not only the visible page.

## Data contract

History is pinned to the checkout’s HEAD at refresh. It includes reachable branch
commits and excludes merges by default. Author dates drive activity; mailmapped
authors drive attribution. Committers, coauthor trailers, PR reviews, issue activity,
and uncommitted edits are outside scope. Shallow history produces a visible notice;
the app never fetches or modifies the repository. Git reads path changes with rename
and external diff handling disabled, so it needs tree metadata, not historical file
contents. Git may obtain missing tree objects in a partial clone.

Matching normalized names and exact emails form identity groups. This heuristic can
be disabled in Filters (then only equal mailmapped emails group). Each person’s
inspector exposes their email aliases. Named automated accounts are detected with
explicit patterns; this cannot determine whether human commits used AI tools.

Commits/day divides by all calendar days in the selected interval, including zero
days. Commits/hour divides by 24 times that interval. These rates are not hours worked.
Preset periods end on the latest authored repository date. All-history bounds come
from repository timestamps, regardless of active contributor or category filters.

Work areas classify paths using `WorkArea.classify` in `Sources/AtlasCore/Models.swift`.
The primary group is the largest changed-file-touch category in the filtered data.
Each path per commit counts once. The matrix counts area-touching commits, so a commit
can count in multiple columns. Work-area filters limit displayed file evidence to the
selected area. Merges, when enabled, have no expanded file evidence. Renames count old
and new paths. Large imports, generated changes, and formatting can skew touch counts;
these are descriptions of recorded activity, not inferred job titles or performance.

## Implementation & verification

`AtlasCore` owns Git parsing, identity grouping, path classification and pure analytics.
The app performs Git loading and analytics away from the UI thread, cancels superseded
filter results, and presents errors without replacing the last successful snapshot.
Calendar components and file categories are indexed once per repository snapshot.
Contributor aggregates mutate in place rather than repeatedly copying growing maps.
A 24-entry LRU cache restores recently visited analyses synchronously; navigation has
no debounce. Only typed search waits 140 ms. Refresh clears the cache.

Back/forward restores section, contributor, all filters, range label, and calendar year.
Synchronous changes from one action form one history entry; continuous search typing
coalesces. A new destination after going back clears the forward branch. History is
bounded to 80 entries and resets on repository refresh. Scroll offsets, pagination,
and transient sheets are not navigation-history entries.

The window uses NavigationSplitView, the native sidebar List, standard title bar and
system toolbar. macOS 26+ adds Liquid Glass to the floating filter bar via glassEffect;
macOS 14–15 use regular material. Reduce Transparency uses an opaque filter surface.
Native components follow system accent, light/dark appearance and accessibility
preferences; there are no custom navigation animations or obligatory transitions.
Charts retain readable content surfaces, following Apple's [material guidance](https://developer.apple.com/design/human-interface-guidelines/materials).

Run `ContributorAtlas --repo /path/to/repo --benchmark` from the built app executable
for uncached overview/contributor aggregation and cached lookup timings. These measure
analytics, not end-to-end frame presentation or Git-loading latency.
CSV cells are escaped and neutralized against spreadsheet formula execution.

Tests cover zero-day denominators, merge handling, timezone boundaries and DST,
transitive aliases, intersecting filters, category precedence, NUL-delimited path
parsing and a real temporary Git repository. The standalone package does not change
Cosign web/mobile UI, Convex functions, shared access contracts or production data.
