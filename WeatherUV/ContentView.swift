import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            DashboardView().tabItem { Label("Today", systemImage: "square.grid.2x2.fill") }.tag(0)
            SourcesView().tabItem { Label("Sources", systemImage: "link") }.tag(1)
            WidgetStudioView().tabItem { Label("Widgets", systemImage: "rectangle.3.group.fill") }.tag(2)
        }
        .tint(.indigo)
    }
}

private struct DashboardView: View {
    @State private var metrics = DashboardStore.metrics

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Good morning").font(.title.bold())
                            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 38)).foregroundStyle(.indigo)
                    }

                    hero
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                        ForEach(metrics.dropFirst()) { MetricCard(metric: $0) }
                    }
                    freshness
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(action: {}) { Image(systemName: "bell") } } }
            .refreshable { metrics = DashboardStore.metrics }
        }
    }

    private var hero: some View {
        let metric = metrics.first ?? DashboardMetric.defaults[0]
        return VStack(alignment: .leading, spacing: 16) {
            HStack { Label("DAILY OVERVIEW", systemImage: "sparkles").font(.caption.bold()); Spacer(); Text("OURA").font(.caption2.bold()) }
            HStack(alignment: .lastTextBaseline) {
                Text(metric.value).font(.system(size: 58, weight: .bold, design: .rounded))
                Text(metric.detail).font(.headline).opacity(0.85)
                Spacer()
            }
            ProgressView(value: 0.86).tint(.white)
            Text("Your recovery is looking strong. A good day to take on something ambitious.").font(.subheadline)
        }
        .foregroundStyle(.white).padding(20)
        .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
    }

    private var freshness: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("All data synced just now").font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }.padding(.top, 4)
    }
}

private struct MetricCard: View {
    let metric: DashboardMetric
    var color: Color {
        switch metric.tint { case "pink": return .pink; case "mint": return .mint; case "blue": return .blue; default: return .indigo }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: metric.symbol).foregroundStyle(color); Spacer(); Text(metric.source == .appleHealth ? "HEALTH" : metric.source == .oura ? "OURA" : "CAL").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
            Text(metric.title).font(.subheadline).foregroundStyle(.secondary)
            Text(metric.value).font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(metric.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct SourcesView: View {
    @State private var connected = DashboardStore.connectedSources
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Bring your health, recovery, and schedule into one private dashboard.").foregroundStyle(.secondary) }
                Section("Available integrations") {
                    ForEach(DataSource.allCases) { source in
                        HStack(spacing: 14) {
                            Image(systemName: source.symbol).frame(width: 42, height: 42).foregroundStyle(.white).background(source == .appleHealth ? .pink : source == .oura ? .purple : .blue, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading) { Text(source.rawValue).font(.headline); Text(description(source)).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button(connected.contains(source) ? "Connected" : "Connect") { toggle(source) }.buttonStyle(.bordered).tint(connected.contains(source) ? .green : .indigo)
                        }.padding(.vertical, 5)
                    }
                }
                Section("Privacy") { Label("Your widget data stays on this device and in the shared app container.", systemImage: "lock.shield.fill").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Data sources")
        }
    }
    private func description(_ source: DataSource) -> String { switch source { case .appleHealth: "Activity, heart & sleep"; case .oura: "Readiness & recovery"; case .googleCalendar: "Events & focus time" } }
    private func toggle(_ source: DataSource) { if connected.contains(source) { connected.remove(source) } else { connected.insert(source) }; DashboardStore.connectedSources = connected; WidgetCenter.shared.reloadAllTimelines() }
}

private struct WidgetStudioView: View {
    @State private var selected = 0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Preview").font(.headline)
                    WidgetPreview().padding(.horizontal, 26)
                    Picker("Layout", selection: $selected) { Text("Balance").tag(0); Text("Recovery").tag(1); Text("Schedule").tag(2) }.pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 4) { Label("Make it yours", systemImage: "slider.horizontal.3").font(.headline); Text("Choose a layout, then add the Pulseboard widget from your Home Screen. Your selection and data update automatically.").foregroundStyle(.secondary) }
                    Button { WidgetCenter.shared.reloadAllTimelines() } label: { Label("Refresh my widgets", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large).tint(.indigo)
                }.padding()
            }.background(Color(.systemGroupedBackground)).navigationTitle("Widget studio")
        }
    }
}

private struct WidgetPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("PULSEBOARD").font(.caption.bold()); Spacer(); Image(systemName: "sparkles") }
            HStack { VStack(alignment: .leading) { Text("86").font(.system(size: 42, weight: .bold, design: .rounded)); Text("Ready").font(.caption) }; Spacer(); VStack(alignment: .leading) { Label("8,420", systemImage: "figure.walk"); Label("Design sync", systemImage: "calendar") }.font(.subheadline.bold()) }
        }.foregroundStyle(.white).padding().aspectRatio(2, contentMode: .fit).background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24)).shadow(color: .indigo.opacity(0.25), radius: 18, y: 10)
    }
}

#Preview { ContentView() }
