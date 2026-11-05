# Storage layout

## Location decision table

| Data | API | Permission | Removed on uninstall | Auto Backup | System may delete |
|---|---|---|---|---|---|
| App-created persistent files | `context.filesDir` | None | Yes | Included by default | No |
| Re-creatable caches | `context.cacheDir` | None | Yes | Excluded | Yes, when space is low |
| Persistent, device-specific files | `context.noBackupFilesDir` | None | Yes | Excluded | No |
| Large app-specific files (downloads, managed media) | `context.getExternalFilesDir(type)` | None (API 19+) | Yes | Included by default | No |
| Large re-creatable files | `context.externalCacheDir` | None | Yes | Excluded | Yes |
| Structured data | Room (`getDatabasePath`) | None | Yes | Included by default | No |
| Small settings | DataStore (`filesDir/datastore/`) | None | Yes | Included by default | No |
| Photos, video, audio the user should keep | `MediaStore` | None for your own items (API 29+) | No | No | No |
| Documents the user picks or creates | Storage Access Framework | Per-URI grant | No | No | No |

Findings to look for:

- Downloads, thumbnails, or response caches in `filesDir`: never cleaned up, and backed up unless excluded.
- Files the app needs (user downloads, offline content) in `cacheDir`: deleted when space is low.
- Secrets or personal data in `getExternalFilesDir()`: readable by other apps on older Android versions and on devices with removable storage.
- Hard-coded `/sdcard/…` or `/storage/emulated/0/…` paths.

## Shared storage and permissions

Since targetSdk 30, scoped storage is enforced: apps can't browse shared storage with file paths.

- **Saving media**: insert into `MediaStore` (`MediaStore.Images.Media.EXTERNAL_CONTENT_URI` etc.), write through `contentResolver.openOutputStream(uri)`. Set `IS_PENDING = 1` while writing and `0` when done so other apps don't see partial files.
- **Picking media**: the Photo Picker. No permission, works across versions via `ActivityResultContracts.PickVisualMedia` / `PickMultipleVisualMedia` (back-ported through Google Play services where the system picker isn't available).

```kotlin
val pickPhoto = rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
    uri?.let(viewModel::onPhotoPicked)
}
Button(onClick = { pickPhoto.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly)) }) { … }
```

- **Documents**: SAF `OpenDocument` / `CreateDocument` / `OpenDocumentTree`. Call `contentResolver.takePersistableUriPermission` to keep access across restarts.
- **Permissions that are findings**:
  - `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` without `android:maxSdkVersion` (32 and 28 respectively are typical).
  - `android:requestLegacyExternalStorage` (ignored from targetSdk 30).
  - `Environment.getExternalStorageDirectory()` / `getExternalStoragePublicDirectory()` (deprecated; scoped storage).
  - `MANAGE_EXTERNAL_STORAGE`: Play allows it only for core use cases (file managers, backup, antivirus, document management) with a declaration. Anything else is a rejection.
  - `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`: Play's photo and video permissions policy limits them to apps whose core function needs broad, persistent access (galleries, editors). Picking a profile photo or attachment uses the Photo Picker. On Android 14+, apps that do hold them must handle partial access (`READ_MEDIA_VISUAL_USER_SELECTED`).

## DataStore and SharedPreferences

```kotlin
// One instance per file, at top level
val Context.settingsDataStore by preferencesDataStore(
    name = "settings",
    produceMigrations = { context -> listOf(SharedPreferencesMigration(context, "settings")) },
)
```

- Creating two DataStore instances for the same file throws at runtime; keep the delegate at top level or provide it as a Hilt `@Singleton`.
- DataStore reads and writes are asynchronous and transactional (Flow + `edit { }`). It's for small key-value data or a small typed proto, not lists that grow.
- SharedPreferences in existing code: `apply()` writes asynchronously but the system waits for pending writes at `onStop`/`onPause`, which causes ANRs with large files; `commit()` blocks the calling thread. Both load the whole file into memory on first access. Migrate to DataStore when touching that code.

## Room and large data

- Structured and relational data in Room. Room refuses main-thread queries by default; don't disable that (`allowMainThreadQueries()` is a finding outside tests).
- Store large blobs (images, audio, documents) as files and keep the path or ID in Room. A row over the cursor window limit (about 2 MB) can't be read back.
- Delete files when their row is deleted; orphaned files are a common source of unbounded growth.

## Secrets and encryption

- Keep keys in the Android Keystore (`KeyGenParameterSpec`, AES-GCM). Encrypt values before writing them to DataStore or files, either directly with `Cipher` or with Tink using a Keystore-backed master key.
- `androidx.security:security-crypto` (`EncryptedSharedPreferences`, `EncryptedFile`, `MasterKey`) is deprecated. Existing uses should migrate; new code shouldn't add it.
- Keystore keys never leave the device and don't restore from backup. Exclude Keystore-encrypted files from backup (or use `noBackupFilesDir`), and handle decryption failure by clearing the value and signing the user in again rather than crashing.

## Auto Backup

Auto Backup (API 23+) uploads app data to the user's Google Drive, up to 25 MB per app, and device-to-device transfer copies it to a new phone.

```xml
<application
    android:allowBackup="true"
    android:dataExtractionRules="@xml/data_extraction_rules"
    android:fullBackupContent="@xml/backup_rules"
    … >
```

```xml
<!-- res/xml/data_extraction_rules.xml (API 31+) -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="sharedpref" path="auth.xml" />
        <exclude domain="file" path="downloads/" />
        <exclude domain="database" path="cache.db" />
    </cloud-backup>
    <device-transfer>
        <exclude domain="sharedpref" path="auth.xml" />
    </device-transfer>
</data-extraction-rules>
```

- `fullBackupContent` (same `<include>`/`<exclude>` vocabulary under `<full-backup-content>`) covers API 30 and lower.
- Exclude tokens, device IDs, FCM tokens, Keystore-encrypted data, large re-downloadable files, and caches.
- With no rules, everything in `filesDir`, databases, and shared preferences is backed up. If that's over 25 MB, backup silently stops.
- `allowBackup="false"` is a valid decision for apps whose data lives on a server; make it on purpose.
- Test with `adb shell bmgr backupnow <package>` then reinstall and `adb shell bmgr restore <package>`.

## Writing safely

- Close streams with `use { }`; leaked file descriptors trigger StrictMode and eventually "too many open files".
- `androidx.core.util.AtomicFile` (or write to a temp file and `renameTo`) for files that must never be half-written: settings exports, downloaded indexes, manifests.
- Disk I/O on `Dispatchers.IO`, injected so tests can substitute it.

## Free space and cache quotas

```kotlin
val storageManager = context.getSystemService<StorageManager>()!!
val uuid = storageManager.getUuidForPath(context.filesDir)
if (storageManager.getAllocatableBytes(uuid) >= neededBytes) {
    FileOutputStream(target).use { out -> storageManager.allocateBytes(out.fd, neededBytes) /* then write */ }
} else {
    context.startActivity(Intent(StorageManager.ACTION_MANAGE_STORAGE).putExtra(StorageManager.EXTRA_REQUESTED_BYTES, neededBytes))
}
```

- `getAllocatableBytes` counts space the system can free by clearing other apps' caches, so it's the right number to check.
- `getCacheQuotaBytes(uuid)` is how much cache the system considers fair for your app; apps over quota lose their cache first.
- Every disk cache has a cap: OkHttp `Cache(File(context.cacheDir, "http"), 50L * 1024 * 1024)`, Coil `diskCache { maxSizeBytes(…) }`, and LRU eviction for your own caches.
- Heavy apps show their storage use and offer per-item delete and "Clear cache" in settings.

## App size

- Ship an Android App Bundle; Play serves per-device splits (ABI, density, language).
- Release builds enable `isMinifyEnabled` and `isShrinkResources` (`r8-shrink-pro`).
- Vector drawables for icons; WebP (or AVIF on newer targets) for raster images; remove unused languages with `androidResources { localeFilters }` only when the app truly doesn't support them.
- Large optional content: Play Asset Delivery (install-time, fast-follow, on-demand packs) for assets; Play Feature Delivery for optional features.
- The base module's compressed download is capped at 200 MB. Watch the Play Console app size report per release.
