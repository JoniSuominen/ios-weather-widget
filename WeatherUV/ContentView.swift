import SwiftUI
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
                Text(metric.value).font(.largeTitle.bold().monospacedDigit())
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
            Text(metric.value).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
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
                    .disabled(connectorManager.activity(for: .oura).isBusy)
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
            .confirmationDialog(
                "Delete Pulseboard data?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete local data", role: .destructive) {
                    Task { await connectorManager.deleteLocalData() }
                }
            } message: {
                Text("This removes cached metrics, widget preferences, and connection state, and disconnects stored Oura credentials. Your provider data and iOS permissions remain unchanged. Manage system permissions in Settings.")
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
                .disabled(source == .oura && connectorManager.ouraConnectionMethod == .direct && !connectorManager.directOuraAvailable)
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
            return "Pulseboard asks to read calendars on this iPhone to show your next event title and time. This includes Google calendars you have already added to iOS. Pulseboard does not change your events."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Connect \(source.displayName)", systemImage: source.symbol)
                        .font(.title2.bold())
                    Text(explanation).fixedSize(horizontal: false, vertical: true)
                    Text("Your selection controls what appears in the dashboard and widgets. Disconnecting clears this source’s cached data; system permissions are managed in iOS Settings.")
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
                    Text("Disconnect a source to clear its cached metrics and stored connection credentials. Delete local data clears cached metrics, connection state, and widget preferences. These actions do not delete records from Apple Health, Oura, or your calendar accounts. Revoke device permissions in iOS Settings and Oura authorization in your Oura account settings.")
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
    @State private var selectedLayout = WidgetPreferences.layout
    @State private var selectedMetricID = WidgetPreferences.primaryMetricID
    @State private var previewSize = WidgetPreviewSize.medium
    @State private var isRefreshing = false

    private var previewMetrics: [DashboardMetric] {
        WidgetPreferences.orderedMetrics(
            connectorManager.metrics,
            layout: selectedLayout,
            primaryMetricID: selectedMetricID
        )
    }

    private var isBusy: Bool {
        isRefreshing || connectorManager.activities.values.contains { $0.isBusy }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Preview with your data").font(.headline)
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
                        isLoading: isBusy
                    )
                    .frame(maxWidth: previewSize == .small ? 280 : .infinity)
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Layout", selection: $selectedLayout) {
                            ForEach(WidgetLayout.allCases) { layout in
                                Text(layout.displayName).tag(layout)
                            }
                        }
                        Picker("Primary metric", selection: $selectedMetricID) {
                            Text("Automatic").tag("")
                            ForEach(connectorManager.metrics) { metric in
                                Text("\(metric.title) · \(metric.source.displayName)").tag(metric.id)
                            }
                            if !selectedMetricID.isEmpty && !connectorManager.metrics.contains(where: { $0.id == selectedMetricID }) {
                                Text("Unavailable metric").tag(selectedMetricID)
                            }
                        }
                        if !selectedMetricID.isEmpty && !connectorManager.metrics.contains(where: { $0.id == selectedMetricID }) {
                            Text("Your chosen metric is unavailable. The widget uses available data until it returns.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("The primary metric leads the Home Screen widget and appears in Lock Screen widgets. Automatic follows your selected layout. Calendar events stay visible in the medium widget when available.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    SourceRefreshWarnings()
                    if !connectorManager.metrics.isEmpty {
                        DataFreshnessView(metrics: previewMetrics)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Add your widget", systemImage: "plus.rectangle.on.rectangle")
                            .font(.headline)
                        Text("Touch and hold your Home Screen, choose Edit, then Add Widget and search for Pulseboard. For the Lock Screen, touch and hold it, choose Customize, and add Pulseboard.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your layout and primary metric are saved automatically. Widgets may take a moment to update.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

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
                            Label(isRefreshing ? "Refreshing widgets…" : "Refresh my widgets", systemImage: "arrow.clockwise")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(isBusy || connectorManager.connectedSources.isEmpty)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Widget studio")
            .onChange(of: selectedLayout) { _, layout in
                WidgetPreferences.layout = layout
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onChange(of: selectedMetricID) { _, metricID in
                WidgetPreferences.primaryMetricID = metricID
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onAppear {
                selectedLayout = WidgetPreferences.layout
                selectedMetricID = WidgetPreferences.primaryMetricID
            }
        }
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
