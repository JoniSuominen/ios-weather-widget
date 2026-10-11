import SwiftUI
import UIKit
import WidgetKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    @StateObject private var connectorManager = ConnectorManager.shared

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("Today", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            SourcesView()
                .tabItem { Label("Sources", systemImage: "link") }
                .tag(1)
            WidgetStudioView()
                .tabItem { Label("Widgets", systemImage: "rectangle.3.group.fill") }
                .tag(2)
        }
        .tint(.indigo)
        .environmentObject(connectorManager)
        .task { await connectorManager.refreshIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await connectorManager.refreshIfNeeded() }
            }
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var connectorManager: ConnectorManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var metrics: [DashboardMetric] { connectorManager.metrics }
    private var isRefreshing: Bool { connectorManager.activities.values.contains { $0.isBusy } }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting).font(.title.bold())
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .foregroundStyle(.secondary)
                    }

                    SourceRefreshWarnings()

                    if metrics.isEmpty {
                        if isRefreshing {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Refreshing your data…").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            ContentUnavailableView(
                                connectorManager.connectedSources.isEmpty ? "No connected data" : "No data available yet",
                                systemImage: "link.badge.plus",
                                description: Text("Connect or refresh Apple Health, Oura, or Calendar from the Sources tab. Read access is controlled by your permissions.")
                            )
                            .frame(minHeight: 240)
                        }
                    } else {
                        hero
                        LazyVGrid(
                            columns: dynamicTypeSize.isAccessibilitySize
                                ? [.init(.flexible())]
                                : [.init(.flexible()), .init(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(Array(metrics.dropFirst())) { MetricCard(metric: $0) }
                        }
                        DataFreshnessView(metrics: metrics)
                        sourceRefreshDates
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await connectorManager.refreshConnectedSources() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh data", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || connectorManager.connectedSources.isEmpty)
                    .accessibilityLabel("Refresh connected data sources")
                }
            }
            .refreshable { await connectorManager.refreshConnectedSources() }
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let metric = metrics.first {
            VStack(alignment: .leading, spacing: 12) {
                Label(metric.source.displayName, systemImage: metric.symbol)
                    .font(.caption.bold())
                Text(metric.displayValue).font(.largeTitle.bold().monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                Text(metric.title).font(.headline)
                Text(metric.detail).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .padding(20)
            .background(
                LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .accessibilityElement(children: .combine)
        }
    }

    private var sourceRefreshDates: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(DataSource.allCases.filter { connectorManager.connectedSources.contains($0) }) { source in
                if let date = DashboardStore.updatedAt(for: source) {
                    Text("\(source.displayName): last fetched \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(source.displayName): waiting for a successful refresh")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MetricCard: View {
    let metric: DashboardMetric

    private var color: Color {
        switch metric.tint {
        case "pink": return .pink
        case "mint": return .mint
        case "blue": return .blue
        case "violet": return .purple
        default: return .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(metric.source.displayName, systemImage: metric.symbol)
                .font(.caption).foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            Text(metric.title).font(.subheadline).foregroundStyle(.secondary)
            Text(metric.displayValue).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            Text(metric.detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct SourcesView: View {
    @EnvironmentObject private var connectorManager: ConnectorManager
    @State private var showingDeleteConfirmation = false
    @State private var showingPrivacy = false
    @State private var showingCalendarSettings = false
    @State private var pendingSource: DataSource?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Bring your health, recovery, and schedule into one dashboard. Choose what you share before connecting each source.")
                        .foregroundStyle(.secondary)
                }

                Section("Oura connection") {
                    Picker("Connect Oura through", selection: ouraMethodBinding) {
                        ForEach(OuraConnectionMethod.allCases) { method in
                            Text(method.displayName).tag(method)
                                .disabled(method == .direct && !connectorManager.directOuraAvailable)
                        }
                    }
                    .disabled(connectorManager.activity(for: .oura).isBusy || connectorManager.isDeletingLocalData)
                    if !connectorManager.directOuraAvailable {
                        Text("Oura account access is unavailable in this build. You can use sleep data that Oura shares with Apple Health.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Changing the connection method disconnects the current Oura source. Connect again to use the new method.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Available integrations") {
                    ForEach(DataSource.allCases) { source in
                        sourceRow(source)
                    }
                }

                Section("Privacy") {
                    Label("Cached metrics are shared locally with your widgets. Oura account access also contacts Oura and the secure sign-in service.", systemImage: "lock.shield.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Read privacy policy") { showingPrivacy = true }
                }

                Section {
                    Button("Delete local data", role: .destructive) { showingDeleteConfirmation = true }
                        .disabled(connectorManager.isDeletingLocalData)
                    if connectorManager.isDeletingLocalData {
                        ProgressView("Deleting local data and disconnecting…")
                    }
                    if let result = connectorManager.dataDeletionResult {
                        Text("Cached dashboard and widget data removed.")
                            .font(.footnote).foregroundStyle(.secondary)
                        DisconnectFeedbackView(source: .oura, result: result)
                    }
                }
            }
            .navigationTitle("Data sources")
            .sheet(item: $pendingSource) { source in
                PermissionPrimer(source: source, ouraMethod: connectorManager.ouraConnectionMethod) {
                    pendingSource = nil
                    Task { await connectorManager.connect(source) }
                }
            }
            .sheet(isPresented: $showingPrivacy) { PrivacyPolicyView() }
            .sheet(isPresented: $showingCalendarSettings) { CalendarSettingsView() }
            .confirmationDialog(
                "Delete Pulseboard data?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete local data", role: .destructive) {
                    Task { await connectorManager.deleteLocalData() }
                }
            } message: {
                Text("This removes cached metrics, app preferences, and connection state. Pulseboard also attempts to remove saved Oura credentials and revoke Oura access; the result is shown here. Provider records and iOS permissions remain unchanged.")
            }
        }
    }

    private var ouraMethodBinding: Binding<OuraConnectionMethod> {
        Binding(
            get: { connectorManager.ouraConnectionMethod },
            set: { method in
                guard method != .direct || connectorManager.directOuraAvailable else { return }
                Task { await connectorManager.setOuraConnectionMethod(method) }
            }
        )
    }

    private func sourceRow(_ source: DataSource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: source.symbol)
                    .frame(width: 38, height: 38)
                    .foregroundStyle(.white)
                    .background(sourceColor(source), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.displayName).font(.headline)
                    Text(description(source)).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if case .failed(let message) = connectorManager.activity(for: source) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sourceButton(source)
            if source == .googleCalendar && connectorManager.connectedSources.contains(source) {
                Button {
                    showingCalendarSettings = true
                } label: {
                    Label("Choose calendars and title privacy", systemImage: "slider.horizontal.3")
                }
                .disabled(connectorManager.isDeletingLocalData)
                Text(CalendarPreferences.selectedCalendarIDs.isEmpty
                    ? "No calendars selected. Choose at least one to show events."
                    : "Event titles are \(CalendarPreferences.showEventTitles ? "shown" : "hidden").")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let result = connectorManager.disconnectResults[source] {
                DisconnectFeedbackView(source: source, result: result)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func sourceButton(_ source: DataSource) -> some View {
        let activity = connectorManager.activity(for: source)
        if activity.isBusy {
            HStack {
                ProgressView()
                Text(activity == .connecting ? "Connecting…" : activity == .disconnecting ? "Disconnecting…" : "Refreshing…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if connectorManager.connectedSources.contains(source) {
            Menu {
                Button("Refresh") { Task { await connectorManager.refresh(source) } }
                Button("Disconnect", role: .destructive) { Task { await connectorManager.disconnect(source) } }
            } label: {
                Label("Connected", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .accessibilityLabel("Manage connected \(source.displayName)")
        } else {
            Button("Connect") { pendingSource = source }
                .buttonStyle(.bordered)
                .tint(.indigo)
                .disabled(connectorManager.isDeletingLocalData
                    || connectorManager.disconnectResults[source]?.localCredentialsCleared == false
                    || (source == .oura && connectorManager.ouraConnectionMethod == .direct && !connectorManager.directOuraAvailable))
                .accessibilityLabel("Connect \(source.displayName)")
        }
    }

    private func sourceColor(_ source: DataSource) -> Color {
        switch source {
        case .appleHealth: return .pink
        case .oura: return .purple
        case .googleCalendar: return .blue
        }
    }

    private func description(_ source: DataSource) -> String {
        switch source {
        case .appleHealth: return "Steps and resting heart rate"
        case .oura:
            return connectorManager.ouraConnectionMethod == .direct
                ? "Readiness and sleep from your Oura account"
                : "Oura sleep shared with Apple Health"
        case .googleCalendar: return "Calendars configured on this iPhone, including Google accounts"
        }
    }
}

private struct CalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var connectorManager: ConnectorManager
    @StateObject private var calendarStore = CalendarSelectionStore()
    @State private var selectedCalendarIDs = CalendarPreferences.selectedCalendarIDs
    @State private var showEventTitles = CalendarPreferences.showEventTitles
    @State private var isLoading = true

    private var controlsUnavailable: Bool {
        connectorManager.isDeletingLocalData ||
        !connectorManager.connectedSources.contains(.googleCalendar) ||
        connectorManager.activity(for: .googleCalendar) == .disconnecting
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Only calendars you select are used. Leaving every calendar unchecked shows no events.")
                        .foregroundStyle(.secondary)
                }
                Section("Calendars") {
                    if isLoading {
                        ProgressView("Loading calendars…")
                    }
                    if let message = calendarStore.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("Open Pulseboard settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    } else if !isLoading && calendarStore.calendars.isEmpty {
                        Text("No calendars found. Add a calendar account in iOS Settings, then refresh this list.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(calendarStore.calendars) { calendar in
                        Toggle(isOn: calendarBinding(calendar.id)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(calendar.title)
                                Text(calendar.accountName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(controlsUnavailable || isLoading || calendarStore.errorMessage != nil)
                    }
                    if selectedCalendarIDs.isEmpty {
                        Text("No calendars selected. Pulseboard will not show events until you select one.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !selectedCalendarIDs.isEmpty {
                        Button("Deselect all calendars") { saveCalendarSelection([]) }
                            .disabled(controlsUnavailable)
                    }
                    if !isLoading && calendarStore.errorMessage == nil &&
                        !selectedCalendarIDs.subtracting(Set(calendarStore.calendars.map(\.id))).isEmpty {
                        Text("Some selected calendars are no longer available. Only selected calendars in this list can contribute events.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Event title privacy") {
                    Toggle("Show event titles", isOn: eventTitleBinding)
                        .disabled(controlsUnavailable || (calendarStore.errorMessage != nil && !showEventTitles))
                    Text("Off shows only availability and timing. On allows event titles in the dashboard and widgets configured to show values. Discreet widgets always hide titles.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("System permission") {
                    Text("This list reads calendars only when Pulseboard already has full Calendar access. Disconnecting Calendar in Pulseboard does not revoke iOS permission. Manage permission in Settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Calendar privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadCalendars() }
            .refreshable { await loadCalendars() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await loadCalendars() } }
            }
        }
    }

    private var eventTitleBinding: Binding<Bool> {
        Binding(
            get: { showEventTitles },
            set: { newValue in
                guard !controlsUnavailable else { return }
                showEventTitles = newValue
                CalendarPreferences.showEventTitles = newValue
                refreshAfterPreferenceChange()
            }
        )
    }

    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedCalendarIDs.contains(id) },
            set: { isSelected in
                var selection = selectedCalendarIDs
                if isSelected { selection.insert(id) } else { selection.remove(id) }
                saveCalendarSelection(selection)
            }
        )
    }

    private func saveCalendarSelection(_ selection: Set<String>) {
        guard !controlsUnavailable else { return }
        selectedCalendarIDs = selection
        CalendarPreferences.selectedCalendarIDs = selection
        refreshAfterPreferenceChange()
    }

    private func refreshAfterPreferenceChange() {
        // The preference setter already removed the shared snapshot. Drop the
        // in-memory copy before the asynchronous fetch can suspend.
        connectorManager.calendarPreferencesDidChange()
        Task { await connectorManager.refresh(.googleCalendar) }
    }

    private func loadCalendars() async {
        isLoading = true
        selectedCalendarIDs = CalendarPreferences.selectedCalendarIDs
        showEventTitles = CalendarPreferences.showEventTitles
        await calendarStore.load()
        if calendarStore.errorMessage != nil {
            connectorManager.calendarPreferencesDidChange()
        }
        isLoading = false
    }
}

private struct DisconnectFeedbackView: View {
    @EnvironmentObject private var connectorManager: ConnectorManager
    let source: DataSource
    let result: DisconnectResult

    private var color: Color {
        if !result.localCredentialsCleared { return .red }
        return result.requiresAttention ? .orange : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                result.warningMessage ?? result.statusMessage,
                systemImage: result.requiresAttention ? "exclamationmark.triangle.fill" : "checkmark.shield"
            )
            .font(.footnote)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)

            if source == .oura {
                if !result.localCredentialsCleared {
                    Button("Retry removing Oura credentials") {
                        Task { await connectorManager.retryOuraDisconnection() }
                    }
                    .disabled(connectorManager.isDeletingLocalData || connectorManager.activity(for: .oura).isBusy)
                }
                if result.requiresAttention || result.remoteAuthorization == .noStoredCredentials {
                    Link("Review access in your Oura account", destination: URL(string: "https://cloud.ouraring.com/")!)
                        .font(.footnote)
                }
            }
        }
    }
}

private struct PermissionPrimer: View {
    @Environment(\.dismiss) private var dismiss
    let source: DataSource
    let ouraMethod: OuraConnectionMethod
    let connect: () -> Void

    private var explanation: String {
        switch source {
        case .appleHealth:
            return "Pulseboard asks to read your step count and resting heart rate from Apple Health. It never writes to your health records. Choose the categories you want to share in the next iOS permission screen."
        case .oura where ouraMethod == .direct:
            return "Sign in with Oura to let Pulseboard read your readiness and sleep. Oura and a secure sign-in service handle authorization and credential refresh. Access credentials are protected in the iOS Keychain. You can disconnect from Sources at any time."
        case .oura:
            return "Pulseboard asks to read sleep records from Apple Health and shows only records written by Oura. First enable Apple Health sharing in the Oura app. This connection does not include Oura Readiness or sleep scores."
        case .googleCalendar:
            return "Pulseboard asks to read calendars on this iPhone, including Google accounts already added to iOS. After connecting, choose which calendars to include. No calendars are selected automatically. Event titles are hidden unless you turn them on; by default only availability and timing appear. Pulseboard does not change your events."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Connect \(source.displayName)", systemImage: source.symbol)
                        .font(.title2.bold())
                    Text(explanation).fixedSize(horizontal: false, vertical: true)
                    Text("Your selection controls what appears in the dashboard and widgets. Disconnecting stops Pulseboard from using this source and clears its cached data. Oura credential removal and account revocation results are shown in Sources. System permissions are managed in iOS Settings.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(action: connect) {
                        Text(source == .oura && ouraMethod == .direct ? "Continue to Oura" : "Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
                .padding()
            }
            .navigationTitle("Your permission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Data you choose to connect") {
                    Text("Pulseboard reads the Apple Health categories, Oura account metrics, and calendars you authorize. Health and calendar connections read records on this device. Oura account access retrieves data from Oura over the network.")
                }
                Section("Storage and sharing") {
                    Text("A local cache stores the metrics needed by the dashboard and widgets in their shared app container. Oura credentials are protected in the iOS Keychain. Direct Oura sign-in and credential refresh contact Oura and a secure OAuth service. Pulseboard does not sell your health or calendar data, and does not use it for advertising.")
                }
                Section("Your controls") {
                    Text("Choose exactly which calendars Pulseboard reads, and whether event titles appear. Calendar titles are hidden by default. Configure each Home Screen and Lock Screen widget separately with its own metric and privacy mode. Discreet widgets hide health values and event titles, including from accessibility labels.")
                    Text("Disconnect stops use of a source and clears its cached metrics. Pulseboard attempts to remove saved Oura credentials and revoke Oura access, and reports whether those actions succeeded. Delete local data also clears cached metrics, connection state, and app preferences. These actions do not delete records from Apple Health, Oura, or your calendar accounts. Revoke device permissions in iOS Settings and review Oura authorization in your Oura account settings.")
                }
                Section("Widget freshness") {
                    Text("Widgets show the last successfully fetched data. Background refresh is managed by iOS and may be delayed. Open Pulseboard and refresh your sources when you need the latest available values.")
                }
            }
            .navigationTitle("Privacy policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct WidgetStudioView: View {
    @EnvironmentObject private var connectorManager: ConnectorManager
    @State private var surface = WidgetPreviewSurface.home
    @State private var homeLayout = WidgetPreferences.layout
    @State private var homeMetricID = WidgetPreferences.primaryMetricID
    @State private var homePrivacy = WidgetPrivacyMode.showValues
    @State private var lockLayout = WidgetLayout.balance
    @State private var lockMetricID = ""
    @State private var lockPrivacy = WidgetPrivacyMode.discreet
    @State private var previewSize = WidgetPreviewSize.medium
    @State private var isRefreshing = false

    private var selectedLayout: WidgetLayout { surface == .home ? homeLayout : lockLayout }
    private var selectedMetricID: String { surface == .home ? homeMetricID : lockMetricID }
    private var selectedPrivacy: WidgetPrivacyMode { surface == .home ? homePrivacy : lockPrivacy }

    // Only this projection reaches text or accessibility in either preview.
    private var previewMetrics: [DashboardMetric] {
        WidgetPreferences.orderedMetrics(
            WidgetPrivacy.render(connectorManager.metrics, mode: selectedPrivacy),
            layout: selectedLayout,
            primaryMetricID: selectedMetricID
        )
    }

    private var isBusy: Bool {
        isRefreshing || connectorManager.isDeletingLocalData ||
        connectorManager.activities.values.contains { $0.isBusy }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Preview with your data").font(.headline)
                    Picker("Preview screen", selection: $surface) {
                        ForEach(WidgetPreviewSurface.allCases) { screen in
                            Text(screen.rawValue).tag(screen)
                        }
                    }
                    .pickerStyle(.segmented)

                    if surface == .home {
                        Picker("Preview size", selection: $previewSize) {
                            ForEach(WidgetPreviewSize.allCases) { size in
                                Text(size.rawValue).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        WidgetPreview(
                            metrics: previewMetrics,
                            layout: selectedLayout,
                            size: previewSize,
                            privacyMode: selectedPrivacy,
                            isLoading: isBusy
                        )
                        .frame(maxWidth: previewSize == .small ? 280 : .infinity)
                        .frame(maxWidth: .infinity)
                    } else {
                        LockScreenPreview(
                            metrics: previewMetrics,
                            privacyMode: selectedPrivacy,
                            isLoading: isBusy
                        )
                    }

                    previewControls
                    SourceRefreshWarnings()
                    if !connectorManager.metrics.isEmpty {
                        DataFreshnessView(metrics: previewMetrics)
                    }
                    widgetInstructions
                    refreshButton
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Widget studio")
            .onChange(of: homeLayout) { _, layout in
                WidgetPreferences.layout = layout
            }
            .onChange(of: homeMetricID) { _, metricID in
                WidgetPreferences.primaryMetricID = metricID
            }
            .onAppear {
                homeLayout = WidgetPreferences.layout
                homeMetricID = WidgetPreferences.primaryMetricID
            }
        }
    }

    private var previewControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Preview layout", selection: layoutBinding) {
                ForEach(WidgetLayout.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }
            Picker("Preview primary metric", selection: metricBinding) {
                Text("Automatic").tag("")
                ForEach(connectorManager.metrics) { metric in
                    Text("\(metric.title) · \(metric.source.displayName)").tag(metric.id)
                }
                if !selectedMetricID.isEmpty && !connectorManager.metrics.contains(where: { $0.id == selectedMetricID }) {
                    Text("Unavailable metric").tag(selectedMetricID)
                }
            }
            Picker("Preview privacy", selection: privacyBinding) {
                ForEach(WidgetPrivacyMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            if !selectedMetricID.isEmpty && !connectorManager.metrics.contains(where: { $0.id == selectedMetricID }) {
                Text("Your chosen metric is unavailable. The preview uses available data until it returns.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Discreet hides health values and event titles. Show values reveals metrics; event titles also require permission in Calendar privacy. Lock Screen widgets default to Discreet.")
                .font(.footnote).foregroundStyle(.secondary)
            Label("Preview only. These controls do not change widgets you have already added.", systemImage: "info.circle")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var widgetInstructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Configure each widget", systemImage: "slider.horizontal.3")
                .font(.headline)
            Text("Home Screen: touch and hold your Pulseboard widget, choose Edit Widget, then set its layout, primary metric, and privacy. Each widget keeps its own choices.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Lock Screen: touch and hold the Lock Screen, choose Customize, tap the Pulseboard widget, and choose its metric and privacy.")
                .fixedSize(horizontal: false, vertical: true)
            Text("To add a widget, touch and hold your Home Screen, choose Edit, then Add Widget and search for Pulseboard. Add Lock Screen widgets from Customize.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
    }

    private var refreshButton: some View {
        Button {
            Task {
                isRefreshing = true
                await connectorManager.refreshConnectedSources()
                WidgetCenter.shared.reloadAllTimelines()
                isRefreshing = false
            }
        } label: {
            HStack {
                if isRefreshing { ProgressView().tint(.white) }
                Label(isRefreshing ? "Refreshing data…" : "Refresh widget data", systemImage: "arrow.clockwise")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(isBusy || connectorManager.connectedSources.isEmpty)
    }

    private var layoutBinding: Binding<WidgetLayout> {
        Binding(
            get: { selectedLayout },
            set: { if surface == .home { homeLayout = $0 } else { lockLayout = $0 } }
        )
    }

    private var metricBinding: Binding<String> {
        Binding(
            get: { selectedMetricID },
            set: { if surface == .home { homeMetricID = $0 } else { lockMetricID = $0 } }
        )
    }

    private var privacyBinding: Binding<WidgetPrivacyMode> {
        Binding(
            get: { selectedPrivacy },
            set: { if surface == .home { homePrivacy = $0 } else { lockPrivacy = $0 } }
        )
    }
}

private enum WidgetPreviewSurface: String, CaseIterable, Identifiable {
    case home = "Home Screen"
    case lock = "Lock Screen"
    var id: String { rawValue }
}

private struct LockScreenPreview: View {
    let metrics: [DashboardMetric]
    let privacyMode: WidgetPrivacyMode
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lock Screen preview").font(.caption.bold())
            if let metric = metrics.first {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: metric.symbol).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.title).font(.caption)
                        Text(metric.value).font(.headline)
                        Text(metric.detail).font(.caption)
                    }
                    .privacySensitive(privacyMode == .showValues)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else if isLoading {
                ProgressView("Refreshing data…")
            } else {
                Label("Connect a source to preview your widget.", systemImage: "link.badge.plus")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private enum WidgetPreviewSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    var id: String { rawValue }
}

private struct WidgetPreview: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let metrics: [DashboardMetric]
    let layout: WidgetLayout
    let size: WidgetPreviewSize
    let privacyMode: WidgetPrivacyMode
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PULSEBOARD").font(.caption.bold())
                Spacer()
                Text(layout.displayName).font(.caption)
                Image(systemName: layout == .schedule ? "calendar" : "sparkles")
                    .accessibilityHidden(true)
            }
            if metrics.isEmpty {
                if isLoading {
                    ProgressView("Refreshing data…").tint(.white)
                } else {
                    Label("Connect a source to preview your widget.", systemImage: "link.badge.plus")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if size == .small, let metric = metrics.first {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: metric.symbol).accessibilityHidden(true)
                    Text(metric.value).font(.largeTitle.bold().monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(metric.title).font(.headline)
                    Text(metric.detail).font(.caption).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .privacySensitive(privacyMode == .showValues)
                .accessibilityElement(children: .combine)
            } else {
                LazyVGrid(
                    columns: dynamicTypeSize.isAccessibilitySize
                        ? [.init(.flexible())]
                        : [.init(.flexible()), .init(.flexible())],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(Array(metrics.prefix(4))) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(metric.title, systemImage: metric.symbol)
                                .font(.caption).foregroundStyle(.white.opacity(0.8))
                            Text(metric.value).font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(metric.detail).font(.caption2).foregroundStyle(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .privacySensitive(privacyMode == .showValues)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !metrics.isEmpty {
                DataFreshnessView(metrics: size == .small ? Array(metrics.prefix(1)) : Array(metrics.prefix(4)), onDarkBackground: true)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }
}

private struct DataFreshnessView: View {
    let metrics: [DashboardMetric]
    var onDarkBackground = false

    private var freshness: DashboardFreshness { DashboardFreshness.stored(for: metrics) }
    private var text: String {
        if freshness.hasError { return "Refresh failed · Cached values" }
        if freshness.hasMissingFetch { return "Waiting for a successful data refresh" }
        guard let date = freshness.oldestFetchAt else { return "No successful refresh yet" }
        let prefix = freshness.isStale() ? "Stale · fetched" : "Fetched"
        return "\(prefix) \(date.formatted(.relative(presentation: .named)))"
    }

    var body: some View {
        Label(text, systemImage: freshness.isStale() ? "clock" : "checkmark.circle")
            .font(.footnote)
            .foregroundStyle(onDarkBackground ? Color.white.opacity(0.8) : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SourceRefreshWarnings: View {
    @EnvironmentObject private var connectorManager: ConnectorManager

    private var failedSources: [DataSource] {
        DataSource.allCases.filter {
            if case .failed = connectorManager.activity(for: $0) { return true }
            return false
        }
    }

    var body: some View {
        if !failedSources.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Some sources need attention", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                ForEach(failedSources) { source in
                    if case .failed(let message) = connectorManager.activity(for: source) {
                        Text("\(source.displayName): \(message)").font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Cached values may be older. Manage connections or try Refresh in Sources.")
                    .font(.footnote)
            }
            .foregroundStyle(.orange)
        }
    }
}

#Preview { ContentView() }
