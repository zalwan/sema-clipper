# SEMA Clipper — video selection and clip range

An Android Flutter prototype for **Choose video → preview → select a clip range**. Everything operates on the selected local file; there is no upload, backend, authentication or persistence.

## Run

Developed with Flutter **3.44.4**, Dart **3.12.2**, Java 21 and an Android SDK with accepted licenses. Use an Android device/emulator; this project does not configure web or desktop targets.

```sh
cd sema_clipper
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

Choose a locally stored landscape video, wait for its preview, then tap play/pause. Use the range slider to choose the clip's start and end; moving either handle pauses and seeks the preview to that boundary. **Change video** opens the picker again. Canceling retains the previous preview, paused. An unsupported, corrupt or inaccessible file produces a readable error and lets you choose again.

Source videos may be any length. The selected clip defaults to the first 60 seconds, or the full source when it is shorter, and is constrained to 1–60 seconds. Duration shows the full source length (`mm:ss`, or `h:mm:ss` for an hour or more). Portrait sources also preserve their original aspect ratio.

## Small project structure

| Files | Responsibility |
|---|---|
| `lib/main.dart`, `lib/app/app.dart` | Entry point and Material app |
| `lib/core/theme/app_theme.dart` | Colors and button styling |
| `lib/features/clipper/clipper_page.dart` | Picker, selected path, loading/error state and player ownership |
| `lib/features/clipper/widgets/empty_video_state.dart` | Initial guidance |
| `lib/features/clipper/widgets/video_preview.dart` | Natural-ratio video, play/pause and playback position |
| `lib/features/clipper/widgets/clip_range_selector.dart` | Start/end slider, boundary labels and selected duration |
| `lib/features/clipper/format_duration.dart` | Duration display logic |
| `test/` | Duration and widget behavior tests with native-platform fakes |
| `integration_test/`, `test_driver/` | Real Android decoder smoke test and screenshot capture |
| `android/` | Generated Android host, app label and take-home signing configuration |

A single `StatefulWidget` owns the video controller. Selection is serialized, cancellation preserves the prior video, and replacement/page teardown dispose it. A pending picker result is ignored after unmount. Decoder initialization has a 30-second timeout and playback errors return to a recoverable state. Flutter's video player handles normal app-background playback lifecycle. There are no state-management or repository abstractions.

## Dependencies

- `file_picker ^13.1.0`: single-video selection through the system picker, using `FilePicker.pickFile(type: FileType.video)`. It supplies the cached local path; the app never reads the entire video into Dart memory.
- `video_player ^2.14.0`: native decoding, metadata, preview and playback control. Format/codec support depends on the Android device.
- Test only: `flutter_test`, `integration_test` (Flutter SDK), `video_player_platform_interface` for faking the native playback boundary. `flutter_lints` supplies static-analysis rules.

The lockfile is included for reproducible package resolution. Package references: [file_picker](https://pub.dev/packages/file_picker), [video_player](https://pub.dev/packages/video_player).

## Validation

```sh
flutter analyze
flutter test
flutter build apk --debug
flutter run -d emulator-5554 --debug --no-resident
```

For the Android decoder test (Linux shell; on macOS replace `base64 -w0 file` with `base64 < file | tr -d '\n'`):

```sh
flutter drive -d emulator-5554 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/video_smoke_test.dart \
  --dart-define=SMOKE_VIDEO_BASE64="$(base64 -w0 integration_test/fixtures/landscape.mp4)"
```

The integration test substitutes **only the picker result** with a generated local file. It uses the real Android video player for initialization, dimensions, duration, play/pause, cancellation, corrupt-file recovery and replacement. Screenshots are written under `build/screenshots/`. This does **not** automate choosing a file inside Android's native picker; that needs the manual check below.

The preview foundation was validated on 29 September 2026 with the Pixel 8 / Android API 37 emulator and a native decoder smoke test. The range-selection slice was validated on 2 October 2026: `flutter analyze` passed, all **17** unit/widget tests passed, and the debug APK built. No physical-phone or native-picker end-to-end check has been performed.

### Manual device check

1. Put an ordinary landscape MP4 on the device; include a source longer than 60 seconds.
2. Open Choose video, select it in the native picker and check the source and default clip durations.
3. Move both clip handles, confirm the preview seeks to each boundary, then play/pause. Background and return to the app. Confirm video is not stretched in either orientation.
4. Open Change video and cancel; then select a second file. Confirm the old video stops and duration changes.
5. Try a corrupt or unsupported local file, then recover by choosing the valid MP4 again.
6. Repeat on a physical Android phone, including a large video and an actual gallery/document provider.

## Android considerations and limits

- Minimum Android API comes from the Flutter template (API 24 with the validated SDK). No broad storage/media, camera or microphone permission is requested by app code; file access comes through the system picker.
- Debug/profile manifests retain Flutter's INTERNET permission for the debugger. The main manifest adds no network permission and the app makes no network requests. Native video dependencies contribute normal permissions such as network-state and wake-lock permissions during manifest merging.
- The system picker may expose cloud providers; choose a video already on the phone for an offline demo. A provider that cannot produce a local path gets a clear retry message.
- Selected paths may refer to plugin-managed cache. No persistent URI grants or saved sessions are implemented. Do not treat these paths as durable across restarts/cache cleanup.
- Release builds currently use the debug signing key for this take-home prototype. A unique application ID and release signing setup are needed before distribution.
- The range UI records start and end positions but does not render a trimmed output yet. Caption, 9:16 conversion, FFmpeg, export and the share sheet remain unimplemented.

## Next processing step

Next, separately prove a maintained, Android-compatible FFmpeg integration on real devices with a tiny local fixture: selected range → defined 9:16 crop/pad policy → escaped single-line caption → local output. Confirm codec availability, binary licensing, Android ABI/16 KB page support, cancellation and cleanup before connecting that pipeline to this screen. Export and sharing follow successful output verification.
