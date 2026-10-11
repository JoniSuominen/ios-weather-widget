# Pulseboard

Pulseboard is an iOS 17 SwiftUI dashboard with configurable Home Screen and Lock Screen widgets. It brings together Oura readiness and sleep, Apple Health steps and resting heart rate, and the next event from calendars configured on your iPhone.

## Features

- **Oura account:** OAuth sign-in with PKCE, direct Oura API reads, token refresh, and disconnect. Account tokens stay in Keychain; the Oura application secret belongs in the separately deployed token broker.
- **Apple Health fallback:** select Apple Health for Oura sleep data shared by the Oura app. This mode needs no Oura sign-in or backend; proprietary Readiness scores require Oura account access.
- **Apple Health and Calendar:** read permitted data through HealthKit and EventKit. Select an explicit list of calendars; titles stay hidden unless enabled. Google Calendar works when the account is configured in iOS Calendar.
- **Widgets:** small and medium Home Screen widgets, plus circular, rectangular, and inline Lock Screen widgets. Each widget has its own layout, metric, and privacy choices through Edit Widget. Lock Screen widgets default to Discreet, hiding health values and event titles, including accessibility labels and gauges. The app's Widget studio previews choices.
- **Honest freshness:** widgets show locally cached snapshots and source update times. Old data remains visibly stale; creating a widget timeline does not mark a source as refreshed.
- **Refresh and privacy:** fetch on launch, returning to the foreground, manual refresh, and best-effort background refresh. Disconnect or delete local data from Sources, with separate results for local Oura credential removal and remote revocation. Failed credential cleanup remains visible after relaunch and offers a retry.

WidgetKit and iOS control background execution and widget reload timing. Background refresh is not a promise of continuous or exact-interval updates. Empty, denied-permission, and unavailable states do not substitute sample values for live data.

## Build

On a Mac with Xcode and an iOS simulator runtime installed:

```bash
brew install xcodegen
xcodegen generate
open WeatherUV.xcodeproj
```

Choose the **WeatherUV** scheme and run on an iPhone simulator. The targets retain their original `WeatherUV` names; the app is named Pulseboard. The GitHub Actions workflow generates the project and runs the simulator checks. See [DEPLOYMENT.md](DEPLOYMENT.md) for signing, Oura setup, and the device release checklist.

To build and install on your own connected iPhone, add your Apple account in Xcode, then run:

```bash
Scripts/install-on-iphone.sh --list
Scripts/install-on-iphone.sh --team YOUR_TEAM_ID --device YOUR_IPHONE_UDID
```

The script signs with your Apple Developer team, installs the app and widget, and launches Pulseboard. It requires a Mac and the matching App Group/HealthKit capabilities. Add `--broker-url https://your-deployed-broker` for direct Oura access.

The **iPhone Build** workflow also produces a downloadable **unsigned arm64 `.xcarchive`** on pushes to `main` and by manual dispatch. It includes the widget, build metadata, and a checksum. This artifact requires Apple signing before installation; it is not an installable IPA or a TestFlight release. Download it from the workflow run's Artifacts section and read its `INSTALLING.md`.

The configured identifiers are:

| Component | Identifier |
| --- | --- |
| App | `com.jonisuominen.pulseboard` |
| Widget | `com.jonisuominen.pulseboard.widget` |
| Shared App Group | `group.com.jonisuominen.pulseboard` |

Register these identifiers and the App Group with the signing Apple Developer team. Contributors must use identifiers they control and update both entitlements and the shared store consistently.

## Enable direct Oura access

The integration code is included; a live Oura connection still requires owner setup:

1. Register an Oura developer application and its callback URI.
2. Configure and deploy the HTTPS token broker following [Backend/README.md](Backend/README.md). Keep the Oura client secret in deployment secrets.
3. Set the Xcode build setting **`OURA_BROKER_URL`** to the broker's HTTPS base URL. It populates **`OuraBrokerURL`** in the app's Info.plist. Regenerate the project after changing `project.yml`.
4. Build the app, select **Oura account** in Sources, and connect. Verify authorization, refresh, cancellation, and disconnect on an iPhone.

The broker publishes public OAuth configuration at `GET /config` and exchanges codes and refresh tokens. It has no user database and does not intentionally persist user tokens. The app fetches Oura metrics directly. With no broker configured, use **Apple Health** mode and enable Oura's Apple Health sharing.

## Repository

```text
WeatherUV/            SwiftUI app and source connectors
WeatherUVWidget/      WidgetKit extension
Shared/               Dashboard models, configuration, and local persistence
Backend/              Oura OAuth token broker and deployment instructions
project.yml           XcodeGen project definition
.github/workflows/    Simulator validation
Scripts/             iPhone archive packaging and local signed installation
```

Read [LOCAL_FIRST.md](LOCAL_FIRST.md) for the storage design and [PRIVACY.md](PRIVACY.md) for data handling. Pulseboard is available under the [MIT license](LICENSE). Release signing, a deployed Oura broker, App Store Connect setup, and physical-device acceptance testing remain the app owner's responsibility.
