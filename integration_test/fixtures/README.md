# Native playback fixture

`landscape.mp4` is a synthetic four-second, 320×180 H.264/yuv420p test pattern with no audio. It contains no personal or third-party footage.

Generated for the decoder smoke test with:

```sh
ffmpeg -f lavfi -i 'testsrc2=size=320x180:rate=5:duration=4' \
  -c:v libx264 -pix_fmt yuv420p -an -movflags +faststart landscape.mp4
```

FFmpeg is only a fixture-generation tool here. It is not an app dependency or processing implementation. The fixture is passed to the integration test using a Dart define and is not bundled in normal app builds.
