# SEMA Clipper

## What it does

SEMA Clipper is an Android Flutter prototype that picks a local video, previews it, selects a 1–60 second range, burns in one caption line, and exports a 1080×1920 MP4. Landscape input is scaled to fill the vertical frame and center-cropped. The result can be previewed, saved to the gallery, or sent to Android's share sheet.

There is no backend, account, analytics, or upload.

## How to run

The project was developed with Flutter 3.44.4, Dart 3.12.2, Java 21, and an Android SDK. Run these commands from this repository root:

```sh
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

Choose a landscape video already stored on the device, set both range handles, type a caption of at most 80 characters, and tap **Export clip**. Export remains in the foreground; it can be cancelled while FFmpeg is running.

## Where processing runs and why

All decoding, trimming, cropping, caption rendering, and encoding happen on the Android device with FFmpeg. This keeps the flow offline, avoids server and upload costs, avoids sending a private source video elsewhere, and removes the wait for a large upload. The cost is a much larger app binary, CPU and battery use during export, and performance and codec differences between phones.

The verified pipeline uses `ffmpeg_kit_flutter_new`, a maintained FFmpeg Kit fork with FFmpeg 8.1.2 and its full-GPL Android build. It provides libx264, AAC, drawtext/libfreetype, scaling, and cropping in one package. The generated video uses H.264, optional AAC audio, `yuv420p`, and fast-start metadata. Because this dependency is GPL, licensing must be reviewed before distributing the app.

## Architecture

- `ClipperPage` owns the single-screen UI, source and result video controllers, range state, caption, and export state.
- `ClipRangeSelector` clamps the chosen interval to 1–60 seconds and seeks the source preview to a moved boundary.
- `ClipProcessor` validates input and builds the FFmpeg command without depending on widgets.
- `FfmpegKitCommandRunner` is the small native processing boundary and supports cancellation.
- `DeviceClipExportActions` saves through Android MediaStore or opens the platform share sheet.
- A bundled DejaVu Sans font makes drawtext output independent of fonts installed on the phone.
- Unit and widget tests replace native boundaries; integration tests exercise Android decoding, FFmpeg, probing, and MediaStore.

## Dependencies

- [`file_picker`](https://pub.dev/packages/file_picker) opens the Android system picker and returns a local file path.
- [`video_player`](https://pub.dev/packages/video_player) provides native source and result playback.
- [`ffmpeg_kit_flutter_new`](https://pub.dev/packages/ffmpeg_kit_flutter_new) performs the on-device trim, crop, caption, and encode pipeline.
- [`saver_gallery`](https://pub.dev/packages/saver_gallery) inserts the result through MediaStore on Android 10+ without broad storage permission.
- [`share_plus`](https://pub.dev/packages/share_plus) opens the native share sheet with the exported MP4.

The remaining packages are Flutter SDK test support, the video player platform interface used by fakes, and lint rules. `pubspec.lock` is committed for reproducible resolution.

## Verification

Run the static, unit/widget, and APK checks:

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Run the native decoder UI smoke test:

```sh
flutter drive -d <android-device-id> \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/video_smoke_test.dart \
  --dart-define=SMOKE_VIDEO_BASE64="$(base64 -w0 integration_test/fixtures/landscape.mp4)"
```

Run the real processing and MediaStore test:

```sh
flutter drive -d <android-device-id> \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/ffmpeg_pipeline_test.dart \
  --dart-define=SMOKE_VIDEO_BASE64="$(base64 -w0 integration_test/fixtures/landscape.mp4)"
```

On macOS, replace `base64 -w0 file` with `base64 < file | tr -d '\\n'`.

On 2 October 2026, `flutter analyze`, all 31 unit/widget tests, and `flutter build apk --debug` passed. A Pixel 8 Android API 37 x86_64 emulator decoded the fixture and ran the production processor. FFprobe confirmed H.264, 1080×1920, and a duration within 0.5 seconds of the requested two seconds; MediaStore also reported a successful save. The system picker, native share destination, and full workflow have not yet been tested on a physical phone.

## Trade-offs and known limitations

- Center-cropping fills 9:16 but removes content from the left and right of landscape footage.
- Export is foreground-only and has indeterminate progress. Leaving or killing the app interrupts it.
- The `ultrafast` H.264 preset reduces export time at the cost of larger files; a universal debug APK is also large because it contains FFmpeg native libraries for multiple ABIs.
- Caption styling is fixed, single-line, and limited to 80 characters. Newlines are removed and drawtext control characters are escaped.
- Source codec support and export speed vary by device. 1080×1920 software encoding can be slow or hot on older phones.
- Gallery saving is designed and emulator-tested for Android 10+ scoped storage. Older Android releases have not been validated and the app intentionally requests no broad storage permission.
- Share-sheet launch is wired through `share_plus`, but choosing and completing a destination remains a manual platform flow.
- A chosen file may be a picker-managed cache path and is not retained as a durable project after restart.
- The Android application ID and release signing still use take-home defaults. Configure both before distribution.
- The FFmpeg plugin currently emits a Flutter warning about its Kotlin Gradle plugin application style, so future Flutter compatibility should be monitored.

## Next steps

- Offer a blurred-background pad mode so the full landscape frame remains visible.
- Add server-side rendering as an opt-in path for weak devices.
- Move long exports to an Android foreground/background worker with resumable progress.
- Support multi-line captions, style choices, placement, and safe-area controls.
- Add an iOS implementation and device test matrix.
- Persist jobs so interrupted exports can resume.

## How I used AI tools

Codex was used to audit the existing repository, research the maintained FFmpeg option, scaffold the processor and UI changes, write unit/widget/integration tests, debug emulator failures, and draft this README. The generated work was reviewed in this session against the assignment: package documentation and licensing, FFmpeg arguments and escaping, Android permissions, the resulting diffs, and each test assertion were inspected. Codex also ran the local verification commands and examined the real output with FFprobe. No manual edits or physical-phone checks by the submitter are claimed; those checks are listed below so the final recording can be based on personally verified behavior.

## Demo script (2–3 minutes)

1. Open SEMA Clipper and choose a landscape MP4 from the Android picker.
2. Play the source briefly, move both range handles, and point out the duration is capped at 60 seconds.
3. Enter a short caption and tap **Export clip**; show the cancellable processing state.
4. Play the exported result and show its vertical 9:16 frame and burned-in caption.
5. Tap **Save to gallery**, open the saved video, and confirm playback.
6. Return to the app, tap **Share**, and show the native share sheet without sending it.

## Physical-phone checklist before recording

1. Connect an Android 10+ phone with USB debugging enabled and confirm it appears in `flutter devices`.
2. Run `flutter run -d <phone-id>` from the repository root.
3. Copy a normal landscape MP4 with audio to the phone; use a file longer than 60 seconds if possible.
4. Pick it through the real system picker. Confirm the preview, source duration, play/pause, orientation changes, and return from background all behave normally.
5. Move the start and end handles. Confirm the preview seeks to each boundary and the selected duration never exceeds 60 seconds.
6. Enter text containing `:`, `'`, `\\`, and `%`; export a short clip and confirm the caption renders as one readable line near the lower third.
7. Play the result. Confirm it is 9:16, not stretched, has the expected start/end content, and retains audio.
8. Start another export and cancel it. Confirm the UI returns to a usable state and no partial result is offered.
9. Save a successful result. Open the Gallery/Photos app, find the **SEMA Clipper** video, and play it with audio.
10. Tap **Share**, choose one installed target, and confirm that target receives a playable MP4. Avoid sending private footage during the test.
11. Try a silent source and one other phone-recorded codec. Confirm export succeeds or the app shows a readable processing error.
12. Change video, cancel the picker once, then choose another video. Also try an invalid/corrupt file and confirm recovery works.
13. Check free storage before a longer export and verify the no-space message on a storage-constrained test device if one is available.
14. Repeat the exact flow intended for the recording once without developer intervention, then record the demo.
