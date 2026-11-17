# Owned preview lifetime and derived cache

Library previews extend the existing storage queue without introducing an authoritative database.
The library marker and item metadata remain version 1; import/mutation intents retain their existing versions.

## Ownership and process boundary

`LibraryPreviewService` verifies assets, then calls `NativeLibrary.withPreviewContext`. A render has three phases:

1. **Snapshot, on the library's serial queue:** validate the selected item and actual stored entry indices,
   and retain its exact original source bytes and source hash.
2. **Render, off the queue:** cache lookup and publication re-enter the queue as short operations;
   worker execution and PNG validation do not hold it, so other library operations proceed meanwhile.
3. **Publish, on the queue:** reload the item and require the snapshot's source hash; a replaced or deleted source
   fails with `SOURCE_CHANGED` and publishes nothing.

Concurrent renders of different items may run; each service still runs one worker at a time.

The worker never reads or writes library files: it receives request bytes on stdin and returns a report and PNG on stdout.
It therefore holds no ownership lease; only the owner validates and publishes derived files.
The launcher uses `posix_spawn` with `POSIX_SPAWN_CLOEXEC_DEFAULT`, explicitly passing only stdin/stdout/stderr,
and an empty environment.
The lock, source, cache, control-directory, and unrelated descriptors, and the parent's environment variables, are excluded.
No source/cache mutation interface or library path is sent to JavaScriptCore or the worker request.
The descriptor allowlist is not an OS sandbox boundary.

The worker starts in a dedicated process group. The supervisor observes its exit using `waitid(...WNOWAIT)`
so the leader PID/PGID cannot be reused before group shutdown.
It stops the group, reaps the leader, and drains bounded pipes before accepting a result or returning an error.
The original worker deadline, cancellation, resident-memory checks, and parent-death pipe remain active.

`NativeLibrary.close()` sets a closing flag, signals every in-flight render's sticky cancellation token,
waits until each render has returned and its worker is reaped, then drains the queue and releases the lease.
The token covers startup, worker execution, validation, and publication.
If the owner process dies, its lease is released at once; an orphaned helper cannot keep the library owned
and cannot publish, because publication belongs to the owner.

## Identity

Each entry uses the existing `LibraryCacheIdentity` schema 1:

`schemaVersion`, `itemId`, `sourceSha256`, `entryPath`, `generator`, `assetIdentity`.

The filename key is SHA-256 of its canonical sorted-key JSON plus a newline.
The source hash describes exact original root bytes; entry paths contain actual stored indices.
The asset identity binds a verified immutable release.
The generator binds rendering/report compatibility and all output settings.
Default 2x/2048/transparent rendering uses `native-preview-v1`; variants append tier, dimension, and checkerboard settings.
Changes to renderer/report compatibility require a new generator version.
Metadata-only name/comment changes do not alter image identity.

## Cache metadata and publication

```text
cache/
  source-index.json
  <item UUID>/
    <key>.png
    <key>.json
    .tmp-<UUID>
```

Complete cache metadata uses schema 2 with exactly:

`schemaVersion`, `identity`, `imageSha256`, `imageBytes`, `report`, `reportSha256`.

`identity` remains schema 1. `report` stores exact JSON report bytes as base64 through Codable Data.
The image/report hashes bind the complete bytes. Limits are 64 MiB PNG, 2 MiB report bytes, and 4 MiB cache metadata.
The storage layer validates bounded structure and hashes; the renderer additionally validates the report and independently decodes the PNG.
Legacy identity-only schema 1 metadata is recognized for maintenance and can be completed by regeneration.
Unknown/future schemas and unexpected fields are protected by preview reads and scoped cleanup.

Before writing, the owner revalidates the selected source hash, control/directory identities, destination names,
known metadata, and existing file hashes. Asset selections must not overlap the library root.
Cache symlinks, shared file inodes, cross-device descendants, and ambiguous case aliases are refused.

Publication performs:

1. Independently validate the worker's returned PNG and report after worker exit.
2. Stage image and metadata under fresh `.tmp-<UUID>` filenames with checked file flushing.
3. Revalidate destination preconditions and atomically publish the PNG.
4. Atomically publish the metadata and synchronize the directory.

A pair is usable only when recognized metadata and the PNG/report hashes agree.
Interrupted staging is derived evidence rather than an authoritative recovery intent.
An image published before metadata may be reused only if it matches an existing complete record; otherwise it regenerates.
Refresh can replace known cache members using checked atomic renames.
Unknown metadata is not silently replaced by a preview, including with `--refresh`.

`source-index.json` is the storage layer's derived kind and entry-icon index (see the storage contract). Scoped cleanup retains it,
`all` removes it, and the next listing rebuilds it; an interrupted index write leaves a root `.tmp-<UUID>` that
abandoned cleanup selects.
`cache-cleanup` recognizes both identity-only and complete cache metadata.
Default abandoned cleanup selects staging files and orphaned images without treating unknown metadata as permission to delete.
Obsolete cleanup compares source, selected entry, assets, and the requested generator.
Explicit all-cache cleanup and item replacement/deletion discard safely confined derived content.

Source originals, authoritative metadata, and `operations/` are never changed by preview publication.
Cache failures do not require authoritative replay and do not make source operations depend on artwork.
Concurrent external editing, power-loss guarantees, hostile helpers, and cache quotas are not established by this contract.
