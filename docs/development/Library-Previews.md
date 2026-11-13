# Cached library previews

Render a saved item while its native library remains exclusively owned, then reuse a validated derived image.
The caller publishes the cache after the worker exits; the worker receives source bytes only.

## Generate and reuse a preview

Prepare a verified asset release using the [standalone preview guide](Preview.md#prepare-a-private-release).
The examples below use that guide's `.cache/renderer-assets` release and a disposable library:

```sh
library=.cache/Preview-Library
just library init "$library"
just library import "$library" Tests/LibraryCoreTests/Fixtures/Blueprints/RS.txt --name Preview
```

Assign the returned `result.id` to `item_id`, then render it:

```sh
just library preview "$library" "$item_id" --assets .cache/renderer-assets
just library preview "$library" "$item_id" --assets .cache/renderer-assets
just library preview "$library" "$item_id" --assets .cache/renderer-assets --refresh
```

The first call returns `cacheHit: false`; the second reuses a validated image with `cacheHit: true`.
`--refresh` renders again under the same identity. It does not overwrite unknown cache formats.
The JSON result includes `key`, `generator`, `cacheHit`, `cachePath`, `durationMs`, and `report`.
`cachePath` is relative to the chosen library root and names the completed PNG.
Stdout contains metadata rather than PNG bytes.

`durationMs` measures the current request. On a hit, `report` retains the stored worker's original measurements and warnings.
Every request still validates its source, assets, and cached image. Reuse avoids starting the renderer worker;
it does not imply an instantaneous lookup or an indexing cache.

## Select entries and settings

Import a book and assign its returned ID to `book_id`:

```sh
just library import "$library" Tests/LibraryCoreTests/Fixtures/Blueprints/v0.59.0.txt --name "Large Book"
just library preview "$library" "$book_id" --entry 1.1 --assets .cache/renderer-assets
```

Entry paths use actual stored indices. Select a blueprint or planner leaf rather than a book container.
The root source remains byte-for-byte unchanged, including surrounding whitespace and unknown fields.
Comments, names, creation dates, and metadata are not updated by previewing.

`--tier 1x`, `--max-dimension 64...4096`, and `--checkerboard` select rendering variants.
Defaults are 2x assets, a maximum dimension of 2048, and a transparent background.
Each combination has a distinct cache identity, even if two small outputs happen to share dimensions.

The default generator is `native-preview-v1`. Other settings produce a generator containing the chosen options.
Use the returned `generator` with `cache-cleanup obsolete --generator` when selecting a particular variant.
Without that override, obsolete cleanup compares against the default rendering configuration and may select other variants.

## Lifetime and maintenance

Keep `preview-worker` adjacent to `fb-native` when installing binaries; repository builds produce both.
The command holds ownership through selection, rendering, independent PNG validation, and publication.
Another application or CLI process cannot open the same library during that work.
Within the owning process, rendering runs off the library queue, so listing, comments, and other operations proceed.
If the item's source changes before publication, the render fails with `SOURCE_CHANGED` and saves nothing.

The shared `LibraryPreviewService` API runs synchronously; an application should call it from background work.
`cancel()` cancels its current request. `NativeLibrary.close()` marks the library as closing,
cancels every in-flight preview, waits for worker cleanup, and then closes the owner lease.
Cancellation remains effective before worker launch. Pure asset preflight may finish reading before observing cancellation;
it cannot launch a worker against a closed library.

The worker never receives the ownership lease, so abrupt parent death releases the library immediately,
even if an orphaned helper is still running. The existing pipe lifeline normally ends that helper promptly.
The supervisor stops the worker's process group before reaping its leader.

Source replacement and item deletion invalidate all of that item's cached variants.
Moving, renaming, and commenting preserve reuse while the source bytes and entry selection remain unchanged.
Known corrupt or incomplete images regenerate. Unknown/future or malformed cache metadata remains protected;
ordinary source operations continue to work, and explicit all-cache cleanup can discard that derived content.

Interrupted preview writes can leave `.tmp-<UUID>` files or an uncommitted image.
`cache-cleanup` identifies abandoned derived files; it never deletes authoritative recovery staging.
A late cancellation may leave an already completed, valid cache entry.
Do not edit library or asset files concurrently with a live owner.

See the [preview cache contract](../contracts/Preview-Cache.md) and [validation](../validation/Library-Previews.md).
The macOS interface, visible-item scheduling, native statistics, and workload qualification remain separate work.
