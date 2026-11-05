---
description: On-device storage on Android — app-specific vs shared storage, scoped storage, MediaStore, Photo Picker and SAF instead of broad storage permissions, DataStore over SharedPreferences, Room, Keystore-backed encryption, Auto Backup rules, free-space checks, cache quotas, StrictMode, and app size
globs: "**/*.{kt,kts,xml}"
paths:
  - "**/*.{kt,kts,xml}"
must:
  - "Use MediaStore, the Photo Picker, or SAF; never request broad storage or media permissions without a Play-approved core use case."
  - "Use DataStore for small values and Room for structured data; never call SharedPreferences `commit()` on the main thread."
  - "Encrypt secrets with an Android Keystore key; never store tokens in plain preferences or add `security-crypto`."
  - "Give Auto Backup rules that exclude caches, tokens, and Keystore-encrypted files, or disable backup on purpose."
---

# Android Storage Management

Scoped storage, Play's permission policies, and Auto Backup all depend on where and how an app writes data. Writing caches into backed-up storage, asking for broad storage permissions, or doing disk I/O on the main thread leads to Play rejections, restore crashes, and ANRs. These are the must-follow rules. Examples, the decision table, and the audit workflow live in the **`android-memory-storage-pro`** skill (`references/storage-layout.md`, `references/measuring.md`).

## Pick the location by what the data is

- **`filesDir`**: app-created persistent files. Private, removed on uninstall, included in Auto Backup unless excluded.
- **`cacheDir`**: anything you can rebuild. The system deletes it when space is low, starting with apps over their quota (`StorageManager.getCacheQuotaBytes`); read it as optional and stay under the quota.
- **`noBackupFilesDir`**: persistent but device-specific (tokens bound to this install, encrypted files whose Keystore key won't restore).
- **`getExternalFilesDir()`**: large app-specific files (downloads, media you manage). No permission needed, removed on uninstall, readable by other apps on older versions, so never secrets.
- **Shared storage only through the platform APIs**: `MediaStore` to save photos, video, and audio (no permission needed for your own files on API 29+); the Photo Picker (`ActivityResultContracts.PickVisualMedia`) to read the user's media; the Storage Access Framework (`OpenDocument`, `CreateDocument`, `OpenDocumentTree`, with `takePersistableUriPermission`) for documents.
- **No `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE`** except with `android:maxSdkVersion` for old releases; no `requestLegacyExternalStorage`; no `Environment.getExternalStorageDirectory()`. **`MANAGE_EXTERNAL_STORAGE` and `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`** need a Play declaration and a core use case; everything else uses the Photo Picker.

## Preferences, data, and secrets

- **DataStore, not SharedPreferences, in new code.** One `DataStore` instance per file (a top-level `preferencesDataStore` delegate); Proto DataStore for typed settings; migrate with `SharedPreferencesMigration`. Never `SharedPreferences.Editor.commit()` on the main thread.
- **DataStore is for small values.** Structured or growing data goes in Room; large blobs go in files with the path in Room.
- **Secrets are encrypted with an Android Keystore key** (directly or through Tink) before they reach DataStore or a file. `androidx.security:security-crypto` (`EncryptedSharedPreferences`, `EncryptedFile`) is deprecated; don't add it to new code.
- **Close every stream** with `use { }`, and write files that must never be half-written with `AtomicFile` (or write to a temp file, then rename).

## Backup

- **Make Auto Backup a decision**: either `android:allowBackup="false"`, or rules that say what's included: `android:dataExtractionRules` (API 31+, with `<cloud-backup>` and `<device-transfer>`) plus `android:fullBackupContent` for API 30 and lower.
- **Exclude caches, tokens, device IDs, and Keystore-encrypted files.** Keystore keys never leave the device, so a restored encrypted file can't be decrypted and crashes the app on first launch. Auto Backup stops at 25 MB per app.

## Threads, space, and size

- **Disk I/O runs on `Dispatchers.IO`** (injected). Enable `StrictMode` in debug builds with `detectDiskReads()`, `detectDiskWrites()`, `detectLeakedClosableObjects()`, and `detectActivityLeaks()`.
- **Check space before large writes**: `StorageManager.getAllocatableBytes()` then `allocateBytes()`; when it's short, send the user to `StorageManager.ACTION_MANAGE_STORAGE`. Handle `IOException` from a full disk with a message, not a crash.
- **Every disk cache has a size cap**: OkHttp `Cache(dir, maxSize)`, Coil's disk cache size, your own LRU eviction. Delete temporary files when the operation ends.
- **App size**: ship an AAB, enable `isMinifyEnabled` and `isShrinkResources` on release (`r8-shrink-pro`), prefer vectors and WebP, and move large optional content to Play Asset Delivery or Play Feature Delivery. Watch the Play Console app size report; the base module download is capped at 200 MB compressed.
