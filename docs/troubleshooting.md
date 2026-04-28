# Troubleshooting

## Xcode or Simulator Not Found

Run:

```sh
xcode-select -p
xcrun simctl list devices available
```

Install Xcode, open it once to finish setup, and select the active developer directory if needed:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Missing ImageMagick

`resize` and `render-marketing` need `magick`.

```sh
brew install imagemagick
magick --version
```

## Missing ffmpeg

`record-preview` needs `ffmpeg`.

```sh
brew install ffmpeg
ffmpeg -version
```

## Simulator Permissions

macOS may require screen recording or automation permissions for simulator capture workflows. If screenshots or recordings are blank, grant permissions to Terminal or your IDE in System Settings, then restart the simulator.

## Output Paths

Screenshot plans write to `EVIDENCE_OUTPUT_DIR`, then `APPSTORE_SCREENSHOT_DIR`, then `EvidenceOutput`.

CLI build evidence writes to `evidence_dir` from `.evidence.toml`, defaulting to `docs/build-evidence`.

## Config Validation

`.evidence.toml` requires:

```toml
scheme = "ExampleApp"
bundle_id = "com.example.app"
simulator_udid = "YOUR-SIMULATOR-UDID"
```

Validation errors name the field that needs attention. Keep app-specific bundle IDs, schemes, and generated artifacts in the consuming app repository.

## Nested Xcode Workspace Or Project

If `evidence capture-screenshots` runs from a directory above the Xcode workspace (for example, `.evidence.toml` lives at the repo root and the iOS project is in `ios/`), `xcodebuild` cannot find the scheme on its own and the run fails. Tell the CLI which workspace or project to use by setting one of:

```toml
xcode_workspace = "ios/MyApp.xcworkspace"
# or
xcode_project = "ios/MyApp.xcodeproj"
```

Set at most one of the two — `evidence` forwards the value to `xcodebuild` as `-workspace` or `-project`. Setting both is rejected at config-load time.
