# WeatherUV

A minimal iOS app whose whole point is **glanceable widgets for current temperature and UV index**, in the smallest widget footprints iOS offers:

- **Home Screen — small** (`systemSmall`, the smallest Home Screen size): temperature, weather icon, and a color-coded UV badge.
- **Lock Screen — accessory widgets** (iOS 17+), the smallest surfaces on iOS:
  - **Circular** — a UV gauge (most glanceable).
  - **Rectangular** — temperature + condition, and UV level.
  - **Inline** — `☀️ 21° · UV 4` next to the clock.

Weather comes from the free [Open-Meteo](https://open-meteo.com) API — **no account or API key required**.

## How the project is structured

```
WeatherUV/            Host app (SwiftUI). Shows current conditions + settings.
WeatherUVWidget/      WidgetKit extension: small + accessory widgets.
Shared/               Code shared by both targets (networking, model, location, storage).
project.yml           XcodeGen spec — the source of truth for the Xcode project.
.github/workflows/    Cloud build on a GitHub Actions macOS runner.
```

An iOS app must ship a host app to contain a widget extension — widgets can't exist on their own. The app also lets you pick the location source.

### Location

- **Auto (GPS)** — default. The app asks for "When In Use" location permission, resolves your coordinate, and stores it in a shared App Group.
- **Fixed city** — search a city in the app and pin it.

The widget only ever *reads* the stored coordinate (it never uses live GPS), so it stays reliable. Both targets share data via the App Group `group.com.example.WeatherUV`.

## Building — no Mac required

Real iOS widgets require WidgetKit, which only compiles on macOS. This repo builds itself **in the cloud** using a GitHub Actions macOS runner — you don't need a Mac to verify it compiles.

Every push runs `.github/workflows/ios-build.yml`, which:

1. Installs [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. Runs `xcodegen generate` to produce `WeatherUV.xcodeproj`.
3. Runs `xcodebuild build` for the iOS Simulator with signing disabled — this compiles **both** the app and the embedded widget.
4. (Best effort) boots a simulator, launches the app, and uploads a screenshot artifact named `app-screenshot`.

> Note: CI can screenshot the **app UI**, but rendering the actual Home/Lock Screen **widget** in CI isn't reliably automatable — widget visuals are validated by compilation (and SwiftUI previews when you have a Mac).

## Running it on a real iPhone (later)

Getting a native iOS app onto a physical iPhone needs Apple code signing. Without a Mac, the path is:

1. Enroll in the **Apple Developer Program** ($99/yr).
2. Archive the app in CI (or [Xcode Cloud](https://developer.apple.com/xcode-cloud/)) and upload to **TestFlight**.
3. Install via the **TestFlight** app on your iPhone — no Mac needed for this step.

If you get access to a Mac, just run:

```bash
brew install xcodegen
xcodegen generate
open WeatherUV.xcodeproj
```

Then select your signing **Team** in Signing & Capabilities for both targets and run.

## Customizing

- **Bundle identifier / App Group:** the defaults use `com.example`. If you change the prefix, update all three of: `project.yml` (both `PRODUCT_BUNDLE_IDENTIFIER`), the two `*.entitlements` files, and `appGroupID` in `Shared/SharedStore.swift`. Keep the app, the widget, and the App Group under the same prefix.
- **Units:** `WeatherService.fetch` accepts `unit: "celsius"` or `"fahrenheit"`.
- **Refresh cadence:** the widget timeline refreshes ~every 30 minutes (`WeatherUVWidget/Provider.swift`).
