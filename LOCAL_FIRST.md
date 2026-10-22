# Pulseboard data architecture

Pulseboard stores the current dashboard on the iPhone and shares a small snapshot with its widgets. It does not require a hosted user database or a Pulseboard account. Direct Oura access adds a network dependency and a separately operated OAuth token broker.

## Data flow

```text
Open-Meteo ─────────┐
HealthKit ──────────┼─> host app or widget ─> App Group snapshot ─> WidgetKit
EventKit ───────────┤
Oura API ───────────┘ (host app only)
       OAuth only: app <─> HTTPS token broker <─> Oura
```

Open-Meteo supplies current temperature, UV index, today's rain, and tomorrow's average temperature for a coordinate rounded to about 1 km. HealthKit supplies steps, resting heart rate, and Oura-origin sleep samples when Apple Health mode is selected. EventKit supplies the next event from calendars configured on the iPhone, including Google Calendar. Permissions are requested only by the host app. The widget extension can also refresh weather, HealthKit, and EventKit sources, using the same shared calendar selection and title settings. It never reads Oura credentials, so direct Oura data refreshes only in the app.

In Oura account mode, the app signs in through Oura using OAuth authorization code flow with PKCE and state validation. A separately deployed broker keeps the confidential Oura client secret outside the app binary. It exchanges and refreshes account tokens without a user database or intentional token persistence. The app stores tokens in Keychain and reads Oura metrics directly from Oura's API. See [Backend/README.md](Backend/README.md) for deployment requirements.

## On-device storage

The shared App Group holds the latest display metrics, source connection state, source freshness, calendar selection identifiers, widget tile layouts, and the rounded weather location. It does not hold OAuth tokens. EventKit queries only selected calendars, and titles are stored in a separate optional field only after explicit opt-in. Changing selections or disabling titles clears the calendar snapshot; a revision check rejects older in-flight fetches. An upgrade discards legacy calendar snapshots that could contain titles.

Each widget stores its own AppIntent configuration through iOS. The timeline provider projects metrics into display-safe data before rendering: Discreet removes health values, numeric gauges, private titles, and sensitive accessibility content. Lock Screen widgets default to Discreet. Show values opts into private values with iOS privacy redaction. Detailed health and calendar history stays in its originating system store or service.

The app fetches data on launch, foreground activation, manual refresh, and when iOS grants a background refresh opportunity. A background refresh is requested after about 30 minutes, but iOS may delay it or never run it. Widget timelines reload about every 30 minutes and then refresh sources older than 10 minutes; the refresh tile refreshes every eligible source at once and reports failures. Passive reloads stay silent on failure, since Health data is unreadable while the device is locked. Widgets render cached data with the age of the oldest shown value in whole minutes, stepped by one timeline entry per minute, and identify snapshots at least an hour old as stale. Only a successful source fetch updates that age.

Disconnect removes a source's local display data and stops using its credentials immediately. Oura account disconnect attempts Keychain removal and remote revocation, reporting both results. **Delete local data** clears Pulseboard's snapshots, widget layouts, weather location, calendar selections, and connection state, and attempts credential removal. Installed widget settings remain managed by iOS. A nonsecret cleanup result remains in app preferences so failed credential removal is visible after relaunch and can be retried. It does not delete records from Apple Health, Calendar, or Oura. Revoke provider permissions in iOS Settings or your Oura account when needed.

## Operating commitments

- Keep OAuth secrets, signing keys, and deployment credentials out of Git and the app binary.
- Request the HealthKit, EventKit, location, and Oura permissions needed by the displayed metrics.
- Do not add analytics, advertising, or a health-history upload by default.
- Keep broker request/response bodies, authorization codes, and tokens out of hosting logs. Review the hosting platform's access logs and retention separately.
- Treat freshness, denied permissions, empty results, and offline failure as user-visible states.
- Update the [privacy policy](PRIVACY.md) and App Store disclosures when deployed behavior changes.

An App Group is local storage, not a cloud database. Provider apps may synchronize data themselves, and iOS backup behavior depends on system settings. Open-source licensing does not replace Apple signing or App Store review. Before release, complete the [device and deployment checklist](DEPLOYMENT.md).
