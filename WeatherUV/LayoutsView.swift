import SwiftUI
import WidgetKit

/// Lists tile layouts by widget size. Each Home Screen widget picks one in
/// Edit Widget.
struct LayoutsView: View {
    @EnvironmentObject private var connectorManager: ConnectorManager
    @State private var designs = WidgetDesignStore.designs
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(WidgetCanvas.allCases) { canvas in
                    Section(canvas.displayName) {
                        ForEach(designs.filter { $0.canvas == canvas }) { design in
                            NavigationLink(value: design.id) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(design.name.isEmpty ? "Untitled" : design.name).font(.headline)
                                    LayoutPreview(
                                        design: design,
                                        metrics: connectorManager.metrics,
                                        connectedSources: connectorManager.connectedSources,
                                        scale: canvas == .small ? 0.8 : 0.72
                                    )
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        Button {
                            let design = WidgetDesignStore.newDesign(for: canvas)
                            WidgetDesignStore.save(design)
                            reload()
                            path.append(design.id)
                        } label: {
                            Label("New \(canvas.displayName.lowercased()) layout", systemImage: "plus")
                        }
                    }
                }
                Section {
                    Text("Add a widget: touch and hold the Home Screen, tap Edit, then Add Widget, and choose this app. To pick a layout, touch and hold the widget and choose Edit Widget.")
                    Text("The refresh tile updates the widget. Its number is the minutes since the oldest value shown was fetched.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Widgets")
            .navigationDestination(for: String.self) { id in
                if let design = designs.first(where: { $0.id == id }) {
                    LayoutEditorView(design: design) { reload() }
                }
            }
            .onAppear { reload() }
        }
    }

    private func reload() {
        designs = WidgetDesignStore.designs
    }
}

/// A widget-sized, non-interactive rendering of a layout.
struct LayoutPreview: View {
    let design: WidgetDesign
    let metrics: [DashboardMetric]
    let connectedSources: Set<DataSource>
    var scale: CGFloat = 1

    /// Real values when anything is connected; sample values otherwise.
    private var shownMetrics: [DashboardMetric] {
        WidgetPrivacy.render(connectedSources.isEmpty ? DashboardMetric.defaults : metrics, mode: .showValues)
    }

    var body: some View {
        let size = design.canvas.previewSize
        let tileIDs = Set(design.tiles.map(\.metricID))
        TileGridView(
            design: design,
            canvas: design.canvas,
            metrics: shownMetrics,
            context: TileContext(
                now: .now,
                freshness: DashboardFreshness.stored(for: shownMetrics.filter { tileIDs.contains($0.id) }),
                privacyMode: .showValues,
                connectedSources: connectedSources.isEmpty ? Set(DataSource.allCases) : connectedSources,
                isInteractive: false,
                showsUnavailable: true,
                scale: scale
            )
        )
        .padding(WidgetCanvas.contentMargin * scale)
        .frame(width: size.width * scale, height: size.height * scale)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22 * scale, style: .continuous).stroke(Color.secondary.opacity(0.25)))
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }
}

/// Edits one layout on its widget grid: tap a tile to select it, drag it to
/// move, drag its corner to resize. Smaller tiles switch to a shorter format.
struct LayoutEditorView: View {
    @EnvironmentObject private var connectorManager: ConnectorManager
    @Environment(\.dismiss) private var dismiss
    @State private var design: WidgetDesign
    @State private var selectedID: UUID?
    @State private var drag: TileDrag?
    @State private var availableWidth: CGFloat = 343
    @State private var message: String?
    @State private var showingDeleteConfirmation = false
    private let onChange: () -> Void

    init(design: WidgetDesign, onChange: @escaping () -> Void) {
        _design = State(initialValue: design)
        self.onChange = onChange
    }

    private struct TileDrag {
        enum Kind { case move, resize }
        let kind: Kind
        let tileID: UUID
        var translation: CGSize
    }

    private static let syncDescriptor = MetricDescriptor(id: WidgetTile.syncID, name: "Refresh and age", source: .weather, symbol: "arrow.clockwise")

    private var scale: CGFloat {
        let size = design.canvas.previewSize
        let widthScale = (availableWidth - 32) / size.width
        let maxScale: CGFloat
        switch design.canvas {
        case .small: maxScale = 1.8
        case .medium: maxScale = 1.15
        case .large: maxScale = 1.0
        }
        return max(0.5, min(widthScale, maxScale))
    }

    private var selectedTile: WidgetTile? {
        design.tiles.first { $0.id == selectedID }
    }

    private var shownMetrics: [DashboardMetric] {
        WidgetPrivacy.render(connectorManager.connectedSources.isEmpty ? DashboardMetric.defaults : connectorManager.metrics, mode: .showValues)
    }

    private var context: TileContext {
        let tileIDs = Set(design.tiles.map(\.metricID))
        return TileContext(
            now: .now,
            freshness: DashboardFreshness.stored(for: shownMetrics.filter { tileIDs.contains($0.id) }),
            privacyMode: .showValues,
            connectedSources: connectorManager.connectedSources.isEmpty ? Set(DataSource.allCases) : connectorManager.connectedSources,
            isInteractive: false,
            showsUnavailable: true,
            scale: scale
        )
    }

    private var addableItems: [MetricDescriptor] {
        let used = Set(design.tiles.map(\.metricID))
        return (MetricCatalog.all + [Self.syncDescriptor]).filter { !used.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorCanvas
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: AvailableWidthKey.self, value: proxy.size.width)
                    }
                )
            List {
                if let tile = selectedTile {
                    selectedTileControls(tile)
                } else {
                    Section {
                        Text("Tap a tile to select it. Drag a selected tile to move it, or drag its corner to resize. Smaller tiles show less: a full card, an icon and value, or just the value.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Add") {
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.orange)
                    }
                    ForEach(addableItems) { item in
                        Button {
                            add(item.id)
                        } label: {
                            Label(item.name, systemImage: item.symbol)
                        }
                    }
                    if addableItems.isEmpty {
                        Text("Every item is already on this layout.").foregroundStyle(.secondary)
                    }
                }
                Section("Layout") {
                    TextField("Name", text: $design.name)
                    Button("Delete layout", role: .destructive) { showingDeleteConfirmation = true }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .onPreferenceChange(AvailableWidthKey.self) { availableWidth = $0 }
        .navigationTitle(design.name.isEmpty ? "Layout" : design.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: design) { _, newValue in
            WidgetDesignStore.save(newValue)
            onChange()
        }
        .onDisappear { WidgetCenter.shared.reloadAllTimelines() }
        .confirmationDialog("Delete this layout?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete layout", role: .destructive) {
                WidgetDesignStore.delete(id: design.id)
                onChange()
                dismiss()
            }
        } message: {
            Text("Widgets using it switch to another \(design.canvas.displayName.lowercased()) layout.")
        }
    }

    // MARK: Canvas

    private var editorCanvas: some View {
        let size = design.canvas.previewSize
        let margin = WidgetCanvas.contentMargin * scale
        let inner = CGSize(width: size.width * scale - 2 * margin, height: size.height * scale - 2 * margin)
        let grid = TileGridGeometry(size: inner, canvas: design.canvas, spacing: WidgetCanvas.tileSpacing * scale)
        let cells = Array(0..<(design.canvas.columns * design.canvas.rows))
        return ZStack(alignment: .topLeading) {
            ForEach(cells, id: \.self) { index in
                let frame = grid.frame(of: WidgetTile(metricID: "", column: index % design.canvas.columns, row: index / design.canvas.columns))
                RoundedRectangle(cornerRadius: 5 * scale)
                    .strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedID = nil }
            if let target = dropTarget {
                let frame = grid.frame(of: target)
                RoundedRectangle(cornerRadius: 6 * scale)
                    .fill((design.canPlace(target) ? Color.green : Color.red).opacity(0.18))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
            ForEach(design.tiles) { tile in
                editableTile(tile, grid: grid)
            }
        }
        .frame(width: inner.width, height: inner.height, alignment: .topLeading)
        .coordinateSpace(name: "canvas")
        .padding(margin)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22 * scale, style: .continuous).stroke(Color.secondary.opacity(0.25)))
    }

    /// Where a moved tile would land. Resizing previews in place instead.
    private var dropTarget: WidgetTile? {
        guard let drag, drag.kind == .move, let tile = design.tiles.first(where: { $0.id == drag.tileID }) else { return nil }
        return moved(tile, by: drag.translation)
    }

    private func editableTile(_ tile: WidgetTile, grid: TileGridGeometry) -> some View {
        let isSelected = tile.id == selectedID
        let isMoving = drag?.kind == .move && drag?.tileID == tile.id
        let isResizing = drag?.kind == .resize && drag?.tileID == tile.id
        let shown = isResizing ? resized(tile, by: drag?.translation ?? .zero) : tile
        let frame = grid.frame(of: shown)
        let moveOffset: CGSize = isMoving ? (drag?.translation ?? .zero) : .zero
        let blocked = isResizing && !design.canPlace(shown)
        return TileView(
            tile: shown,
            metric: shownMetrics.first { $0.id == tile.metricID },
            context: context,
            size: frame.size,
            isTrailing: shown.endColumn == design.canvas.columns
        )
        .padding(.horizontal, 3 * scale)
        .frame(width: frame.width, height: frame.height)
        .background(
            RoundedRectangle(cornerRadius: 6 * scale)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6 * scale)
                .stroke(blocked ? Color.red : isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        // Outside the content shape so the handle stays tappable past the tile's edge.
        .overlay(alignment: .bottomTrailing) {
            if isSelected { resizeHandle(tile, grid: grid) }
        }
        .offset(x: frame.minX + moveOffset.width, y: frame.minY + moveOffset.height)
        .zIndex(isSelected ? 1 : 0)
        .onTapGesture { selectedID = tile.id }
        .gesture(moveGesture(tile, grid: grid), including: isSelected ? .all : .subviews)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Select to move, resize, or remove")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func resizeHandle(_ tile: WidgetTile, grid: TileGridGeometry) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color.accentColor, in: Circle())
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .offset(x: 12, y: 12)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        drag = TileDrag(kind: .resize, tileID: tile.id, translation: value.translation)
                    }
                    .onEnded { value in
                        let target = resized(tile, by: value.translation)
                        if target.width != tile.width || target.height != tile.height {
                            let applied = design.resizeTile(id: tile.id, width: target.width, height: target.height)
                            showMessage(applied.map { $0.width == target.width && $0.height == target.height } ?? false
                                ? nil : "Resized as far as the free space allows.")
                        }
                        drag = nil
                    }
            )
            .accessibilityHidden(true)
    }

    private func moveGesture(_ tile: WidgetTile, grid: TileGridGeometry) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
            .onChanged { value in
                drag = TileDrag(kind: .move, tileID: tile.id, translation: value.translation)
            }
            .onEnded { value in
                let target = moved(tile, by: value.translation)
                if target != tile {
                    showMessage(design.update(target) ? nil : "That space is taken. Move or shrink the other tile first.")
                }
                drag = nil
            }
    }

    private func moved(_ tile: WidgetTile, by translation: CGSize) -> WidgetTile {
        let cells = TileGridGeometry(size: gridSize, canvas: design.canvas, spacing: WidgetCanvas.tileSpacing * scale).cells(for: translation)
        var target = tile
        target.column = min(max(0, tile.column + cells.columns), design.canvas.columns - tile.width)
        target.row = min(max(0, tile.row + cells.rows), design.canvas.rows - tile.height)
        return target
    }

    private func resized(_ tile: WidgetTile, by translation: CGSize) -> WidgetTile {
        let cells = TileGridGeometry(size: gridSize, canvas: design.canvas, spacing: WidgetCanvas.tileSpacing * scale).cells(for: translation)
        var target = tile
        target.width = min(max(1, tile.width + cells.columns), design.canvas.columns - tile.column)
        target.height = min(max(1, tile.height + cells.rows), design.canvas.rows - tile.row)
        return target
    }

    private var gridSize: CGSize {
        let size = design.canvas.previewSize
        let margin = WidgetCanvas.contentMargin * scale
        return CGSize(width: size.width * scale - 2 * margin, height: size.height * scale - 2 * margin)
    }

    // MARK: Controls

    @ViewBuilder
    private func selectedTileControls(_ tile: WidgetTile) -> some View {
        Section(name(of: tile)) {
            Stepper(
                "Width: \(tile.width)",
                onIncrement: { resize(tile, width: tile.width + 1, height: tile.height) },
                onDecrement: { resize(tile, width: tile.width - 1, height: tile.height) }
            )
            Stepper(
                "Height: \(tile.height)",
                onIncrement: { resize(tile, width: tile.width, height: tile.height + 1) },
                onDecrement: { resize(tile, width: tile.width, height: tile.height - 1) }
            )
            Picker("Show", selection: styleBinding(for: tile)) {
                Text(tile.isSync ? "Icon and minutes" : "Icon and value").tag(TileStyle.standard)
                Text(tile.isSync ? "Icon only" : "Value only").tag(TileStyle.valueOnly)
            }
            Button("Remove from layout", role: .destructive) {
                design.removeTile(id: tile.id)
                selectedID = nil
            }
        }
    }

    private func resize(_ tile: WidgetTile, width: Int, height: Int) {
        guard width >= 1, height >= 1 else { return }
        var target = tile
        target.width = width
        target.height = height
        showMessage(design.update(target) ? nil : "No free space in that direction.")
    }

    private func styleBinding(for tile: WidgetTile) -> Binding<TileStyle> {
        Binding(
            get: { design.tiles.first { $0.id == tile.id }?.style ?? .standard },
            set: { style in
                var updated = tile
                updated.style = style
                design.update(updated)
            }
        )
    }

    private func add(_ metricID: String) {
        if let tile = design.addTile(metricID: metricID) {
            selectedID = tile.id
            showMessage(nil)
        } else {
            showMessage("No free space. Shrink or remove a tile first.")
        }
    }

    private func name(of tile: WidgetTile) -> String {
        tile.isSync ? Self.syncDescriptor.name : MetricCatalog.descriptor(for: tile.metricID)?.name ?? tile.metricID
    }

    private func showMessage(_ text: String?) {
        message = text
    }
}

private struct AvailableWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 343
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
