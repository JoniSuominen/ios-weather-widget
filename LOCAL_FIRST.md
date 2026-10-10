# Pulseboard data architecture

Pulseboard stores the current dashboard on the iPhone and shares a small snapshot with its widgets. It does not require a hosted user database or a Pulseboard account. Direct Oura access adds a network dependency and a separately operated OAuth token broker.

## Data flow

```text
HealthKit ──────────┐
EventKit ───────────┼─> host app ─> App Group snapshot ─> WidgetKit
Oura API ───────────┘
       OAuth only: app <─> HTTPS token broker <─> Oura
```

HealthKit supplies steps, resting heart rate, and Oura-origin sleep samples when Apple Health mode is selected. EventKit supplies the next event from calendars configured on the iPhone, including Google Calendar. These frameworks run in the host app; the widget extension reads the shared snapshot rather than asking for permissions or fetching source data.

In Oura account mode, the app signs in through Oura using OAuth authorization code flow with PKCE and state validation. A separately deployed broker keeps the confidential Oura client secret outside the app binary. It exchanges and refreshes account tokens without a user database or intentional token persistence. The app stores tokens in Keychain and reads Oura metrics directly from Oura's API. See [Backend/README.md](Backend/README.md) for deployment requirements.

## On-device storage

The shared App Group holds the latest display metrics, source connection state, source freshness, and widget configuration. It does not hold OAuth tokens. Detailed health and calendar history stays in its originating system store or service. Calendar titles shown in a widget are still personal data; users should choose widget placement accordingly.

The app fetches data on launch, foreground activation, manual refresh, and when iOS grants a background refresh opportunity. A background refresh is requested after about 30 minutes, but iOS may delay it or never run it. Widgets render cached data, retain the actual source update time, and identify snapshots at least an hour old as stale. Refreshing a widget timeline alone does not make a cached value fresh.

Disconnect removes a source's local display data and account credentials. Oura account disconnect attempts remote revocation; without network access, local deletion can succeed while remote revocation cannot. **Delete local data** clears Pulseboard's snapshots, configuration, connection state, and credentials. It does not delete records from Apple Health, Calendar, or Oura. Revoke provider permissions in iOS Settings or your Oura account when needed.

## Operating commitments

- Keep OAuth secrets, signing keys, and deployment credentials out of Git and the app binary.
- Request the HealthKit, EventKit, and Oura permissions needed by the displayed metrics.
- Do not add analytics, advertising, or a health-history upload by default.
- Keep broker request/response bodies, authorization codes, and tokens out of hosting logs. Review the hosting platform's access logs and retention separately.
- Treat freshness, denied permissions, empty results, and offline failure as user-visible states.
- Update the [privacy policy](PRIVACY.md) and App Store disclosures when deployed behavior changes.

An App Group is local storage, not a cloud database. Provider apps may synchronize data themselves, and iOS backup behavior depends on system settings. Open-source licensing does not replace Apple signing or App Store review. Before release, complete the [device and deployment checklist](DEPLOYMENT.md).
