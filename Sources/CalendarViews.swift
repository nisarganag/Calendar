import SwiftUI

// MARK: - Liquid Glass helpers
//
// One rule governs every use of glass here: glass is a *surface*, not a
// decoration, and it comes in exactly three tiers. The panel is one sheet of
// full-strength glass. Each section is a clear-glass facet on that sheet. Today
// and the selection are tinted blobs inside the grid. Nothing else gets glass —
// stack it any deeper and each layer only ever samples the blur above it, which
// is how a Liquid Glass panel collapses into flat grey.

/// Two tiers of surface. The `sheet` is the panel itself — one full-strength
/// piece of glass floating over the desktop. A `facet` is a section inside it,
/// and uses clear glass, which is built for layering: it adds an edge and a
/// highlight without adding another blur, so the sheet stays luminous.
enum CalSurface {
    case sheet, facet
}

@available(macOS 26.0, *)
private struct GlassCard: ViewModifier {
    var radius: CGFloat
    var tint: Color?
    var surface: CalSurface

    func body(content: Content) -> some View {
        let base: Glass = surface == .sheet ? .regular : .clear
        return content.glassEffect(
            tint.map { base.tint($0) } ?? base,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}

extension View {
    /// A glass surface. Falls back to a material on pre-26 systems.
    @ViewBuilder
    func calGlass(radius: CGFloat, tint: Color? = nil, surface: CalSurface = .facet) -> some View {
        if #available(macOS 26.0, *) {
            modifier(GlassCard(radius: radius, tint: tint, surface: surface))
        } else {
            background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(surface == .sheet ? AnyShapeStyle(.regularMaterial)
                                            : AnyShapeStyle(.ultraThinMaterial))
            )
        }
    }

    /// Lets sibling glass shapes see one another so they can merge and flow.
    @ViewBuilder
    func calGlassContainer(spacing: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

// MARK: - Root panel

struct CalendarPanelView: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        VStack(spacing: 9) {
            headerCard
            calendarCard
            bottomCard
            footerCard
            versionLabel
        }
        .padding(.horizontal, 11)
        .padding(.top, 11)
        .padding(.bottom, 8)
        .frame(width: Cal.panelWidth)
        .calGlass(radius: 26, surface: .sheet)
        .calGlassContainer(spacing: 16)
        .animation(.smooth(duration: 0.24), value: viewModel.showGoToDate)
        .animation(.smooth(duration: 0.2), value: viewModel.displayedMonth)
    }

    private var versionLabel: some View {
        Text("CalBar \(AppInfo.shortDisplay)")
            .font(Cal.utility(8.5, .medium))
            .tracking(0.4)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .help(AppInfo.longDisplay)
    }

    // MARK: Header

    private var headerCard: some View {
        HStack(spacing: 4) {
            StepButton(symbol: "chevron.left") { viewModel.moveMonth(-1) }
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text(viewModel.monthTitle)
                    .font(Cal.display(15.5, .bold))
                    .tracking(-0.2)
                TodayStamp(text: shortToday) { viewModel.goToday() }
            }
            Spacer(minLength: 0)
            StepButton(symbol: "chevron.right") { viewModel.moveMonth(1) }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .calGlass(radius: 17)
    }

    /// The date the go-to fields currently compose, e.g. "27 Aug 2026".
    private var gotoSummary: String {
        let month = viewModel.gotoMonthSymbols.indices.contains(viewModel.gotoMonth)
            ? viewModel.gotoMonthSymbols[viewModel.gotoMonth].prefix(3)
            : ""
        return "\(viewModel.gotoDay) \(month) \(viewModel.gotoYear)"
    }

    private var shortToday: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: viewModel.today)
    }

    // MARK: Calendar grid

    private var calendarCard: some View {
        VStack(spacing: 6) {
            weekdayRow
            monthGrid
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .calGlass(radius: Cal.cardRadius)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(viewModel.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(Cal.utility(9, .heavy))
                    .tracking(0.9)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 1)
    }

    private var monthGrid: some View {
        DayGrid(viewModel: viewModel)
    }

    // MARK: Bottom card (events or go-to-date)

    @ViewBuilder
    private var bottomCard: some View {
        if viewModel.showGoToDate {
            goToDatePicker
        } else {
            eventPanel
        }
    }

    // MARK: Events

    private var eventPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 3, height: 13)
                Text(viewModel.selectedDayTitle)
                    .font(Cal.display(11.5, .semibold))
                Spacer(minLength: 4)
                if !viewModel.selectedEvents.isEmpty {
                    Text("\(viewModel.selectedEvents.count)")
                        .font(Cal.digits(9.5, .bold))
                        .foregroundStyle(.tertiary)
                }
            }

            ScrollView {
                VStack(spacing: 2) {
                    if viewModel.selectedEvents.isEmpty {
                        Text("Nothing scheduled. Add the first one below.")
                            .font(Cal.utility(10.5, .regular))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 14)
                    } else {
                        ForEach(Array(viewModel.selectedEvents.enumerated()), id: \.offset) { index, event in
                            EventRowView(text: event) {
                                viewModel.removeEvents(at: IndexSet(integer: index))
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(minHeight: 62, maxHeight: 116)

            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(Cal.utility(10, .black))
                    .foregroundStyle(Cal.inkContrast)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Cal.ink.opacity(0.85)))
                TextField("Add event…", text: $viewModel.draftEvent)
                    .textFieldStyle(.plain)
                    .font(Cal.utility(11.5, .regular))
                    .onSubmit { viewModel.addDraftEvent() }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5))
            )
        }
        .padding(11)
        .calGlass(radius: Cal.cardRadius)
    }

    // MARK: Go to date

    private var goToDatePicker: some View {
        VStack(spacing: 11) {
            HStack(spacing: 7) {
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 3, height: 13)
                Text("Go to date")
                    .font(Cal.display(11.5, .semibold))
                Spacer()
                Button {
                    viewModel.showGoToDate = false
                } label: {
                    Image(systemName: "xmark")
                        .font(Cal.utility(9, .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 19, height: 19)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            HStack(spacing: 7) {
                FieldLabel("Month") {
                    Picker("", selection: $viewModel.gotoMonth) {
                        ForEach(Array(viewModel.gotoMonthSymbols.enumerated()), id: \.offset) { index, name in
                            Text(name.prefix(3)).tag(index)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                            .frame(maxWidth: .infinity)
                }

                FieldLabel("Day") {
                    Stepper(value: $viewModel.gotoDay, in: 1...max(1, viewModel.gotoDaysInMonth)) {
                        Text("\(viewModel.gotoDay)")
                            .font(Cal.digits(11.5, .semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .controlSize(.small)
                }

                FieldLabel("Year") {
                    TextField("Year", value: $viewModel.gotoYear, format: .number.grouping(.never))
                        .textFieldStyle(.plain)
                        .font(Cal.digits(11.5, .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.08)))
                        .onSubmit { viewModel.applyGoToDate() }
                }
                .frame(width: 62)
            }

            Button {
                viewModel.applyGoToDate()
            } label: {
                Text("Show \(gotoSummary)")
                    .font(Cal.display(11.5, .bold))
                    .foregroundStyle(Cal.inkContrast)
                    .frame(maxWidth: .infinity)
            }
            .calProminent()
        }
        .padding(11)
        .calGlass(radius: Cal.cardRadius)
    }

    // MARK: Footer

    private var footerCard: some View {
        HStack(spacing: 8) {
            Picker("", selection: $viewModel.weekStartsMonday) {
                Text("Sun").tag(false)
                Text("Mon").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 66)
            .tint(Cal.ink)
            .help("Start the week on Sunday or Monday")

            Toggle(isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.setLaunchAtLogin($0) }
            )) {
                Text("Login")
                    .font(Cal.utility(10, .medium))
                    .fixedSize()
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            .tint(Cal.ink)
            .help("Launch CalBar when you log in")

            Spacer(minLength: 2)

            Button {
                viewModel.goToday()
            } label: {
                Text("Today")
                    .font(Cal.display(10, .bold))
                    .foregroundStyle(Cal.inkContrast)
                    .tracking(0.1)
            }
            .calProminent()
            .help("Jump to today")

            IconButton(
                symbol: "calendar.badge.clock",
                active: viewModel.showGoToDate,
                help: "Go to date…"
            ) { viewModel.openGoToDate() }

            IconButton(symbol: "power", active: false, help: "Quit CalBar") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .calGlass(radius: 16)
    }
}

// MARK: - Button styling

private extension View {
    /// The system's prominent glass button, tinted with the accent. This is the
    /// replacement for the hand-painted gradient capsule: the ramp now comes
    /// from the material's own refraction and specular edge rather than a fill.
    @ViewBuilder
    func calProminent() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(Cal.ink)
                .controlSize(.small)
        } else {
            buttonStyle(.borderedProminent)
                .tint(Cal.ink)
                .controlSize(.small)
        }
    }
}

/// Caption above a control. Keeps the go-to-date row on one baseline and names
/// each input, so the row reads as a form rather than three loose widgets.
private struct FieldLabel<Content: View>: View {
    let caption: String
    @ViewBuilder var content: Content

    init(_ caption: String, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(caption.uppercased())
                .font(Cal.utility(8, .bold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
            content
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Header controls

private struct StepButton: View {
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Cal.utility(11, .bold))
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.12 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// The date stamp under the month title. It jumps to today, so it gets a hover
/// state — an affordance you cannot see is not an affordance.
private struct TodayStamp: View {
    let text: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Text(text.uppercased())
            .font(Cal.utility(8.5, .bold))
            .tracking(1.1)
            .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color.primary.opacity(hovering ? 0.10 : 0))
            )
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .help("Jump to today")
    }
}

private struct IconButton: View {
    let symbol: String
    let active: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Cal.utility(11.5, .semibold))
                .foregroundStyle(active ? AnyShapeStyle(.primary)
                                        : AnyShapeStyle(hovering ? .primary : .secondary))
                .frame(width: 23, height: 23)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(active ? 0.16 : (hovering ? 0.10 : 0)))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help(help)
    }
}

// MARK: - Day grid
//
// The signature element. Rather than giving all 42 cells their own glass, the
// grid holds exactly two pieces of glass — today, and the selection — inside a
// shared container. Because both carry a stable `glassEffectID`, the selection
// physically flows from cell to cell as you click, and fuses with today's blob
// when the two land next to each other. That liquid travel is the one thing a
// painted gradient chip can never imitate, so it is where the boldness is spent.

private struct DayGrid: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Namespace private var glassNamespace

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        grid.calGlassContainer(spacing: 20)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(viewModel.days) { cell in
                DayCellView(
                    cell: cell,
                    isToday: viewModel.isToday(cell),
                    isSelected: viewModel.isSelected(cell),
                    namespace: glassNamespace
                ) {
                    guard let date = cell.date else { return }
                    viewModel.select(date)
                    if !cell.isInCurrentMonth {
                        viewModel.moveMonth(date < viewModel.displayedMonth ? -1 : 1)
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.32), value: viewModel.selectedDate)
    }
}

private struct DayCellView: View {
    let cell: DayCell
    let isToday: Bool
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        // The number is centred in the full cell and the event dot is an
        // overlay, so the dot never displaces the digit. That is the fix for
        // numbers sitting high in their boxes.
        Text("\(cell.dayNumber)")
            .font(Cal.digits(12, isToday ? .heavy : (isSelected ? .bold : .medium)))
            .foregroundStyle(numberStyle)
            .frame(maxWidth: .infinity)
            .frame(height: Cal.cellHeight)
            .background(plainBackground)
            .glassLayer(for: state, namespace: namespace)
            .overlay(alignment: .bottom) { eventDot }
            .contentShape(RoundedRectangle(cornerRadius: Cal.cellRadius, style: .continuous))
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .animation(.easeOut(duration: 0.13), value: hovering)
    }

    private var state: DayGlassState {
        if isToday { return .today }
        if isSelected { return .selected }
        return .none
    }

    @ViewBuilder
    private var eventDot: some View {
        Circle()
            .fill(isToday ? AnyShapeStyle(Cal.inkContrast) : AnyShapeStyle(Color.primary.opacity(0.5)))
            .frame(width: 4, height: 4)
            .padding(.bottom, 3)
            .shadow(color: Cal.abyss.opacity(0.5), radius: 1)
            .opacity(cell.hasEvents ? (cell.isInCurrentMonth || isToday ? 1 : 0.45) : 0)
    }

    private var numberStyle: AnyShapeStyle {
        if isToday { return AnyShapeStyle(Cal.inkContrast) }
        if isSelected { return AnyShapeStyle(.primary) }
        if !cell.isInCurrentMonth { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(.primary)
    }

    /// Hover only — today and selection are drawn in glass, not paint.
    @ViewBuilder
    private var plainBackground: some View {
        if state == .none && hovering && cell.isInCurrentMonth {
            RoundedRectangle(cornerRadius: Cal.cellRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        }
    }
}

private enum DayGlassState: Equatable {
    case none, selected, today
}

/// The bright top edge and dark underside a real glass lozenge picks up from
/// overhead light. Without it a tinted shape reads as flat paint.
private func specularEdge(opacity: Double) -> some View {
    RoundedRectangle(cornerRadius: Cal.cellRadius, style: .continuous)
        .strokeBorder(
            LinearGradient(
                colors: [Color.white.opacity(opacity),
                         Color.white.opacity(opacity * 0.15),
                         Cal.abyss.opacity(opacity * 0.35)],
                startPoint: .top, endPoint: .bottom
            ),
            lineWidth: 0.8
        )
}

private extension View {
    /// Applies the travelling glass blob for today / the selection.
    @ViewBuilder
    func glassLayer(for state: DayGlassState, namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            switch state {
            case .none:
                self
            case .today:
                glassEffect(
                    .regular.tint(Cal.ink.opacity(0.88)).interactive(),
                    in: RoundedRectangle(cornerRadius: Cal.cellRadius, style: .continuous)
                )
                .glassEffectID("today", in: namespace)
                .glassEffectTransition(.matchedGeometry)
                .overlay(specularEdge(opacity: 0.6))
                .shadow(color: Cal.abyss.opacity(0.30), radius: 5, y: 2)
            case .selected:
                glassEffect(
                    .regular.tint(Color.primary.opacity(0.14)).interactive(),
                    in: RoundedRectangle(cornerRadius: Cal.cellRadius, style: .continuous)
                )
                .glassEffectID("selection", in: namespace)
                .glassEffectTransition(.matchedGeometry)
                .overlay(specularEdge(opacity: 0.28))
            }
        } else {
            switch state {
            case .none:
                self
            case .today:
                background(
                    RoundedRectangle(cornerRadius: Cal.cellRadius, style: .continuous)
                        .fill(Cal.ink.opacity(0.9))
                )
            case .selected:
                background(
                    RoundedRectangle(cornerRadius: Cal.cellRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.14))
                )
            }
        }
    }
}

// MARK: - Event row

private struct EventRowView: View {
    let text: String
    let delete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.primary.opacity(0.55))
                .frame(width: 4, height: 4)
            Text(text)
                .font(Cal.utility(11, .regular))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(action: delete) {
                Image(systemName: "xmark")
                    .font(Cal.utility(8.5, .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.primary.opacity(0.10)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Delete event")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0))
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.13), value: hovering)
    }
}
