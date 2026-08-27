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
    @FocusState private var eventFieldFocused: Bool

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
        .animation(.smooth(duration: 0.18), value: viewModel.draftMinutes == nil)
        .animation(.smooth(duration: 0.24), value: viewModel.showGoToDate)
        .animation(.smooth(duration: 0.2), value: viewModel.displayedMonth)
        .onReceive(viewModel.$focusEventField) { shouldFocus in
            guard shouldFocus else { return }
            eventFieldFocused = true
            DispatchQueue.main.async { viewModel.focusEventField = false }
        }
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

    /// Scrolls the agenda so the next upcoming event is visible.
    private func scrollToNext(_ proxy: ScrollViewProxy) {
        guard let index = viewModel.nextUpIndex,
              viewModel.selectedEvents.indices.contains(index) else { return }
        let id = viewModel.selectedEvents[index].id
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .center)
        }
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

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        if viewModel.selectedEvents.isEmpty {
                            Text("Nothing scheduled. Add the first one below.")
                                .font(Cal.utility(10.5, .regular))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 14)
                        } else {
                            ForEach(Array(viewModel.selectedEvents.enumerated()), id: \.element.id) { index, event in
                                EventRowView(
                                    event: event,
                                    isPast: viewModel.isPast(event),
                                    isNext: index == viewModel.nextUpIndex
                                ) {
                                    viewModel.removeEvent(id: event.id)
                                }
                                .id(event.id)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                // .never, not .hidden: .hidden still defers to the system
                // "Show scroll bars: Always" setting, so the bar comes back on
                // machines configured that way. Scrolling and swipe are
                // unaffected either way.
                .scrollIndicators(.never)
                // A long day scrolls, and what is next is the one row you
                // opened the panel to see — so bring it into view rather than
                // leaving it below the fold under a stack of finished events.
                .onReceive(viewModel.$nowMinutes) { _ in scrollToNext(proxy) }
                .onReceive(viewModel.$selectedDate) { _ in
                    DispatchQueue.main.async { scrollToNext(proxy) }
                }
                .onAppear { scrollToNext(proxy) }
            }
            .frame(minHeight: 62, maxHeight: 148)

            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(Cal.utility(10, .black))
                    .foregroundStyle(Cal.inkContrast)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Cal.ink.opacity(0.85)))

                TextField("Add event…", text: $viewModel.draftEvent)
                    .textFieldStyle(.plain)
                    .font(Cal.utility(11.5, .regular))
                    .focused($eventFieldFocused)
                    .onSubmit { viewModel.addDraftEvent() }

                // Untimed is the default, so a quick note stays a one-field
                // affair; the clock is one click away when a time matters.
                if viewModel.draftMinutes != nil {
                    TimeField(minutes: Binding(
                        get: { viewModel.draftMinutes ?? 0 },
                        set: { viewModel.draftMinutes = $0 }
                    ))
                }

                Button {
                    viewModel.toggleDraftTime()
                } label: {
                    Image(systemName: viewModel.draftMinutes == nil ? "clock" : "xmark")
                        .font(Cal.utility(10.5, .semibold))
                        .foregroundStyle(viewModel.draftMinutes == nil
                                         ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .frame(width: 17, height: 17)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(viewModel.draftMinutes == nil ? "Add a time" : "Remove the time")
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
// Rather than giving all 42 cells their own glass, the grid holds exactly two
// pieces of glass — today, and the selection — inside a shared container. Both
// carry a stable `glassEffectID`, so the selection travels from cell to cell
// rather than blinking between them.
//
// Two deliberate choices keep the highlight readable while arrowing:
//
// Container spacing is 0. Any larger and adjacent chips blend into a single
// shape, which looks like a rendering fault and hides which day is selected.
//
// The transition is `.identity`, and there is no animation on selectedDate. A
// matched-geometry morph makes the chip travel between cells, and at arrowing
// speed that reads as the old date hanging on rather than as motion. The
// selection answers "where am I?" — it has to be true the instant the key
// lands, not 0.3s later.

private struct DayGrid: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Namespace private var glassNamespace

    // 7pt/6pt gaps rather than 3pt. Liquid Glass samples what surrounds it, so
    // at 3pt the selection chip lensed the bright today chip beside it and lit
    // up along that edge. Widening the gap past the sampling radius is what
    // stops the bleed — dropping `.interactive()` made no difference.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 7)

    var body: some View {
        grid.calGlassContainer(spacing: 0)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(viewModel.days) { cell in
                DayCellView(
                    cell: cell,
                    isToday: viewModel.isToday(cell),
                    isSelected: viewModel.isSelected(cell),
                    namespace: glassNamespace
                ) {
                    guard let date = cell.date else { return }
                    viewModel.selectTracking(date)
                }
            }
        }
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
                .glassEffectTransition(.identity)
                .overlay(specularEdge(opacity: 0.6))
                .shadow(color: Cal.abyss.opacity(0.30), radius: 5, y: 2)
            case .selected:
                glassEffect(
                    .regular.tint(Color.primary.opacity(0.14)).interactive(),
                    in: RoundedRectangle(cornerRadius: Cal.cellRadius, style: .continuous)
                )
                .glassEffectID("selection", in: namespace)
                .glassEffectTransition(.identity)
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

/// Compact time control for the add row.
///
/// Replaces SwiftUI's DatePicker, which reserves a two-digit hour slot: with a
/// single-digit hour the field showed "6:30 PM" padded on the left but flush on
/// the right, and the format cannot be told to zero-pad. This renders the same
/// zero-padded form the event rows use, so the two always agree, and keeps both
/// typing and stepping.
private struct TimeField: View {
    @Binding var minutes: Int

    /// Non-nil only while the user is mid-edit, so stepper changes still show
    /// through and a half-typed value is never committed.
    @State private var draft: String?

    private var text: Binding<String> {
        Binding(
            get: { draft ?? EventTimeParser.display(minutes) },
            set: { draft = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 3) {
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(Cal.digits(10.5, .semibold))
                .multilineTextAlignment(.center)
                .frame(width: 54)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                )
                .onSubmit(commit)
                .help("Type a time, or use the arrows")

            Stepper("", value: $minutes, in: 0...(24 * 60 - 1), step: 5)
                .labelsHidden()
                .controlSize(.mini)
        }
    }

    /// Accepts anything the event parser accepts — "6:30 pm", "18:30", "6 pm".
    /// An unparseable entry is discarded and the field snaps back, rather than
    /// silently storing something the user did not mean.
    private func commit() {
        defer { draft = nil }
        guard let entry = draft?.trimmingCharacters(in: .whitespaces), !entry.isEmpty else { return }
        if let parsed = EventTimeParser.minutes(from: entry.replacingOccurrences(of: " ", with: "")) {
            minutes = parsed
        }
    }
}

// MARK: - Event row

private struct EventRowView: View {
    let event: CalEvent
    /// Both only ever true on today — any other day renders neutrally.
    let isPast: Bool
    let isNext: Bool
    let delete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            marker
            timeLabel
            Text(event.title)
                .font(Cal.utility(11, isNext ? .semibold : .regular))
                .lineLimit(2)
                .strikethrough(false)
            Spacer(minLength: 4)
            Button(action: delete) {
                Image(systemName: "xmark")
                    .font(Cal.utility(8.5, .bold))
                    .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.primary.opacity(0.12)))
                    // Visually 16pt, but a 24pt target: the glyph is small and
                    // deleting should not require precision aiming.
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Delete event")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minHeight: 26)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Past events recede rather than disappear — the day's shape stays
        // readable, but your eye skips what has already happened.
        .opacity(isPast ? 0.42 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.13), value: hovering)
        .help(accessibilityText)
    }

    /// A filled dot marks what is next; everything else gets a hollow one, so
    /// the rows still line up on a single axis.
    private var marker: some View {
        Circle()
            .strokeBorder(Color.primary.opacity(0.5), lineWidth: isNext ? 0 : 1)
            .background(Circle().fill(isNext ? AnyShapeStyle(Cal.ink) : AnyShapeStyle(Color.clear)))
            .frame(width: isNext ? 6 : 5, height: isNext ? 6 : 5)
            .frame(width: 7)
    }

    // Sized for the *bold* next-up variant, which is the widest thing that can
    // land here: bold "12:00" measures 31.49pt against 30.25pt at medium, and
    // bold "AM" 16.66pt. Sizing to the regular weight made the next-up row wrap
    // onto two lines.
    private static let numericWidth: CGFloat = 33
    private static let meridiemWidth: CGFloat = 18

    /// A 24-hour locale carries no AM/PM, so it should not carry the gutter either.
    private var timeColumnWidth: CGFloat {
        EventTimeParser.usesMeridiem()
            ? Self.numericWidth + 3 + Self.meridiemWidth
            : Self.numericWidth
    }

    @ViewBuilder
    private var timeLabel: some View {
        HStack(spacing: 3) {
            if let minutes = event.minutes {
                let parts = EventTimeParser.displayParts(minutes)
                // Every time is the same width now the hour is zero-padded, so
                // alignment is exact rather than merely close.
                Text(parts.numeric)
                    .frame(width: Self.numericWidth, alignment: .leading)
                if !parts.meridiem.isEmpty {
                    // Left-aligned in its own column, because AM and PM are not
                    // the same width and would otherwise drag the digits about.
                    Text(parts.meridiem)
                        .frame(width: Self.meridiemWidth, alignment: .leading)
                }
            } else {
                // Marked, not blank. An empty gutter left untimed notes looking
                // detached from the list they belong to.
                Text("\u{2013}")
                    .foregroundStyle(.quaternary)
                    .frame(width: Self.numericWidth, alignment: .center)
            }
        }
        .font(Cal.digits(10, isNext ? .bold : .medium))
        .foregroundStyle(isNext ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: timeColumnWidth, alignment: .leading)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let m = event.minutes { parts.append(EventTimeParser.format(m)) }
        parts.append(event.title)
        if isNext { parts.append("— next up") }
        else if isPast { parts.append("— earlier today") }
        return parts.joined(separator: " ")
    }
}
