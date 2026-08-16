# Pulseboard

Pulseboard is an iOS 17 SwiftUI app for building a calm, glanceable personal dashboard from **Oura, Apple Health, and Google Calendar**. It includes Home Screen and Lock Screen widgets backed by an App Group, so the app and WidgetKit extension share the same snapshot.

## What is included

- A polished Today dashboard with readiness, sleep, steps, heart rate, and the next calendar event.
- A Sources screen for managing Apple Health, Oura, and Google Calendar connections.
- A Widget Studio with layout previews and manual timeline refresh.
- Small and medium Home Screen widgets plus circular, rectangular, and inline Lock Screen widgets.
- A codable shared data model and App Group store ready for real connector results.

The repository deliberately ships preview data so the complete app and widgets are useful in the simulator before credentials are configured. The source buttons currently persist connection state locally; production integrations still require:

1. HealthKit capabilities and read authorization for the HealthKit data types you choose.
2. An Oura developer application, OAuth callback URL, and token exchange service.
3. A Google Cloud OAuth client and Calendar API scope.

Never put OAuth client secrets in the app. Exchange authorization codes in a backend, store user tokens in Keychain, normalize fetched values into `DashboardMetric`, then assign them to `DashboardStore.metrics` and reload WidgetKit timelines.

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

## Next integration step

Implement each provider behind a small connector protocol (`authorize`, `refresh`, `disconnect`). Keep provider-specific response objects out of WidgetKit: translate them to `DashboardMetric`, write one latest snapshot to the App Group, and ask `WidgetCenter` to reload. This keeps widget rendering fast and resilient when a phone is offline.
