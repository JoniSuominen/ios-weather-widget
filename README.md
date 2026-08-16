# Pulseboard

Pulseboard is an iOS 17 SwiftUI app for building a calm, glanceable personal dashboard from **Oura, Apple Health, and Google Calendar**. It includes Home Screen and Lock Screen widgets backed by an App Group, so the app and WidgetKit extension share the same snapshot.

## What is included

- A polished Today dashboard with readiness, sleep, steps, heart rate, and the next calendar event.
- A Sources screen for managing Apple Health, Oura, and Google Calendar connections.
- A Widget Studio with layout previews and manual timeline refresh.
- Small and medium Home Screen widgets plus circular, rectangular, and inline Lock Screen widgets.
- A codable shared data model and App Group store ready for real connector results.

The repository deliberately ships preview data so the complete app and widgets are useful in the simulator before integrations are implemented. Today the app is fully local: it makes no network requests and stores its dashboard snapshot and source toggles in the shared App Group `UserDefaults`. No hosted database or user account is required.

Production integrations still require:

1. HealthKit capabilities and read authorization for the HealthKit data types you choose.
2. Either reading the health data Oura writes to Apple Health, or an Oura developer application and OAuth flow for Oura-only metrics.
3. EventKit calendar permission. EventKit can read calendars already connected in iOS—including a Google calendar—without adding the Google Calendar API to Pulseboard.

Never put OAuth client secrets in the app. If direct Oura API access is added, use a secure OAuth design and store user tokens in Keychain. Normalize fetched values into `DashboardMetric`, assign them to `DashboardStore.metrics`, and reload WidgetKit timelines.

See [LOCAL_FIRST.md](LOCAL_FIRST.md) for the no-database architecture, privacy model, and realistic Oura trade-offs.

## Structure

```
WeatherUV/            SwiftUI host app (the target keeps its legacy name)
WeatherUVWidget/      WidgetKit extension
Shared/               Shared dashboard models, persistence, and legacy weather code
project.yml           XcodeGen project definition
.github/workflows/    Simulator build and screenshot workflow
```

## Build

```bash
brew install xcodegen
xcodegen generate
open WeatherUV.xcodeproj
```

Select your Apple Developer team and replace the example bundle identifiers and App Group before running on a device. A GitHub Actions macOS job also generates and builds both targets with signing disabled on every push.

## First-time testing and deployment

If you have never built an iOS app, start with the simulator. It does not require an
Apple Developer account, certificates, or a physical iPhone. Follow the complete
step-by-step guide in [DEPLOYMENT.md](DEPLOYMENT.md).

The short version is:

1. On a Mac, install Xcode from the App Store and launch it once.
2. Install XcodeGen with `brew install xcodegen`.
3. Run `xcodegen generate` in this repository and open `WeatherUV.xcodeproj`.
4. Select the **WeatherUV** scheme and an iPhone simulator, then press Run.
5. For a real phone, replace every `com.example` identifier, configure the matching
   App Group for both targets, choose your Apple Developer team, and run on the phone.

The current Connect buttons demonstrate UI and local connection state; they do not
yet authenticate with Oura, HealthKit, or Google. The cards intentionally show sample
data until those production connectors are implemented.

## Next integration step

Implement each provider behind a small connector protocol (`authorize`, `refresh`, `disconnect`). Keep provider-specific response objects out of WidgetKit: translate them to `DashboardMetric`, write one latest snapshot to the App Group, and ask `WidgetCenter` to reload. This keeps widget rendering fast and resilient when a phone is offline.
