# Pulseboard privacy policy

Updated October 10, 2026.

Pulseboard displays a personal dashboard and iOS widgets using sources you choose to connect. This policy describes the open-source app and the supplied Oura token broker. A distributor who changes the code or hosting must review and update this policy for their deployment.

## Data used by the app

With your permission, Pulseboard reads:

- **Apple Health:** today's steps, resting heart rate, and, in Apple Health mode, sleep samples written by Oura. Readiness scores are not available through this fallback.
- **Calendar:** the next event from calendars configured on your iPhone, including its title and time for display.
- **Oura account:** readiness and sleep data from Oura's API after you authorize account access.

The latest display values, source state, freshness times, and widget choices are stored in the app's local shared App Group so widgets can display them. Oura account tokens are stored in iOS Keychain, not in the shared widget snapshot. Detailed health and calendar histories are not copied into a Pulseboard user database. Data displayed on a Home or Lock Screen widget may be visible to people who can see your device.

Pulseboard does not include advertising, analytics, tracking, or a third-party crash-reporting SDK. It does not sell personal data.

## Network access and the Oura broker

Apple Health and Calendar access uses Apple's on-device frameworks. Those providers and their apps may perform their own synchronization; Pulseboard does not control it.

In Oura account mode, the app communicates with Oura for sign-in and metric reads. It also communicates over HTTPS with a separately deployed OAuth token broker for authorization-code exchange, token refresh, and best-effort token revocation. The broker processes authorization codes, PKCE verifiers, and account tokens as needed to complete these operations. It holds the Oura application's client secret on the server, has no user database, and does not intentionally persist account tokens or health metrics.

The supplied broker does not intentionally log OAuth request or response bodies. Hosting platforms may still process connection information such as IP addresses, request timestamps, and operational logs. The operator must minimize logs, disable body/token logging, and configure suitable retention. Deployment and hosting are owner setup steps; this repository does not establish that a broker is already live.

Oura and Apple have separate privacy policies governing their services: [Oura privacy policy](https://ouraring.com/privacy-policy) and [Apple privacy policy](https://www.apple.com/legal/privacy/). Consult your calendar provider's policy as well.

## Your choices and deletion

Connecting a source is optional. You can use Apple Health mode instead of direct Oura account access. You can disconnect individual sources or use **Delete local data** in Sources to clear Pulseboard's cached values, source state, widget choices, and account credentials. Deletion does not remove records from Apple Health, your calendars, or your Oura account.

Oura disconnect attempts to revoke remote access. A network or provider failure may prevent remote revocation even though local credentials are removed. Review authorized applications in your Oura account to revoke access there. Manage Apple Health and Calendar permissions in iOS Settings. iOS device backup behavior depends on system settings.

## Contact and changes

For privacy questions, use [the repository's GitHub Issues](https://github.com/JoniSuominen/ios-weather-widget/issues). Do not post health details, calendar contents, passwords, or tokens in a public issue.

This policy will be updated when Pulseboard's data handling changes. Its public URL is [this privacy policy on GitHub](https://github.com/JoniSuominen/ios-weather-widget/blob/main/PRIVACY.md).
