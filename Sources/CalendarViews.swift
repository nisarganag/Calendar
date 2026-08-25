import SwiftUI

private let accentTop = Color(red: 0.42, green: 0.40, blue: 0.98)
private let accentBottom = Color(red: 0.22, green: 0.62, blue: 1.00)
private let panelWidth: CGFloat = 320

// MARK: - Liquid Glass helpers

@available(macOS 26.0, *)
private struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(
            interactive ? Glass.regular.interactive() : Glass.regular,
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
    }
}

extension View {
    @ViewBuilder
    func calGlass(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.modifier(GlassModifier(cornerRadius: cornerRadius, interactive: interactive))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    @ViewBuilder
    func calGlassContainer() -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { self }
        } else {
            self
        }
    }
}

// MARK: - Root panel

struct CalendarPanelView: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        content.calGlassContainer()
    }

    private var content: some View {
        VStack(spacing: 10) {
            headerPill
            calendarTile
            bottomCard
            footerStrip
            versionLabel
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: panelWidth)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showGoToDate)
        .animation(.easeInOut(duration: 0.18), value: viewModel.displayedMonth)
    }

    private var versionLabel: some View {
        Text("CalBar \(AppInfo.shortDisplay)")
            .font(.system(size: 8.5, weight: .medium, design: .rounded))
            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            .frame(maxWidth: .infinity)
            .help(AppInfo.longDisplay)
    }

    // MARK: Header

    private var headerPill: some View {
        HStack(spacing: 6) {
            chevronButton("chevron.left") { viewModel.moveMonth(-1) }
            Spacer()
            VStack(spacing: 1) {
                Text(viewModel.monthTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Today · \(shortToday)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .onTapGesture { viewModel.goToday() }
            }
            Spacer()
            chevronButton("chevron.right") { viewModel.moveMonth(1) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .calGlass(cornerRadius: 16)
    }

    private func chevronButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        ChevronButton(symbol: symbol, action: action)
    }

    private var shortToday: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: viewModel.today)
    }

    // MARK: Calendar grid

    private var calendarTile: some View {
        VStack(spacing: 5) {
            weekdayRow
            monthGrid
        }
        .padding(8)
        .calGlass(cornerRadius: 18)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(viewModel.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 3) {
            ForEach(viewModel.days) { cell in
                DayCellView(
                    cell: cell,
                    isToday: viewModel.isToday(cell),
                    isSelected: viewModel.isSelected(cell)
                ) {
                    if let date = cell.date {
                        viewModel.select(date)
                        if !cell.isInCurrentMonth {
                            viewModel.moveMonth(date < viewModel.displayedMonth ? -1 : 1)
                        }
                    }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3.5, height: 13)
                Text(viewModel.selectedDayTitle)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Spacer()
                if !viewModel.selectedEvents.isEmpty {
                    Text("\(viewModel.selectedEvents.count) event\(viewModel.selectedEvents.count == 1 ? "" : "s")")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            ScrollView {
                VStack(spacing: 3) {
                    if viewModel.selectedEvents.isEmpty {
                        HStack {
                            Spacer()
                            Text("No events — add one below")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    } else {
                        ForEach(Array(viewModel.selectedEvents.enumerated()), id: \.offset) { index, event in
                            EventRowView(text: event) {
                                viewModel.removeEvents(at: IndexSet(integer: index))
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 74, maxHeight: 130)

            HStack(spacing: 7) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom))
                TextField("Add event…", text: $viewModel.draftEvent)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .onSubmit { viewModel.addDraftEvent() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .padding(10)
        .calGlass(cornerRadius: 18)
    }

    // MARK: Go to date

    private var goToDatePicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3.5, height: 13)
                Text("Go to date")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    viewModel.showGoToDate = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Picker("", selection: $viewModel.gotoMonth) {
                    ForEach(Array(viewModel.gotoMonthSymbols.enumerated()), id: \.offset) { index, name in
                        Text(name.prefix(3)).tag(index)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                TextField("Year", value: $viewModel.gotoYear, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
                    .frame(width: 68)
                    .onSubmit { viewModel.applyGoToDate() }

                Stepper(value: $viewModel.gotoDay, in: 1...max(1, viewModel.gotoDaysInMonth)) {
                    Text("\(viewModel.gotoDay)")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .frame(minWidth: 18)
                }
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.applyGoToDate()
                } label: {
                    Text("Go")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: [accentTop, accentBottom], startPoint: .leading, endPoint: .trailing))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .calGlass(cornerRadius: 18)
    }

    // MARK: Footer

    private var footerStrip: some View {
        HStack(spacing: 8) {
            Picker("", selection: $viewModel.weekStartsMonday) {
                Text("Sun").tag(false)
                Text("Mon").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 64)

            Toggle(isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.setLaunchAtLogin($0) }
            )) {
                Text("Login")
                    .font(.system(size: 10, weight: .medium))
                    .fixedSize()
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            .help("Launch CalBar when you log in")

            Spacer()

            Button {
                viewModel.goToday()
            } label: {
                Text("Today")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule().fill(LinearGradient(colors: [accentTop, accentBottom], startPoint: .leading, endPoint: .trailing))
                    )
            }
            .buttonStyle(.plain)
            .help("Jump to today")

            Button {
                viewModel.openGoToDate()
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(viewModel.showGoToDate ? .accentColor : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Go to date…")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Quit CalBar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .calGlass(cornerRadius: 14)
    }
}

// MARK: - Chevron button

private struct ChevronButton: View {
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(hovering ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.primary.opacity(hovering ? 0.09 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Day cell

private struct DayCellView: View {
    let cell: DayCell
    let isToday: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 2) {
            Text("\(cell.dayNumber)")
                .font(.system(size: 11.5, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundColor(numberColor)
            Circle()
                .fill(LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 3.5, height: 3.5)
                .opacity(cell.hasEvents && !isToday ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.25)
                .opacity(isSelected && !isToday ? 1 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .calGlass(cornerRadius: 8, interactive: false)
        .opacity(isToday || isSelected || hovering ? 1 : 0.85)
    }

    private var numberColor: Color? {
        if isToday { return .white }
        if isSelected { return .accentColor }
        if !cell.isInCurrentMonth { return Color(nsColor: .tertiaryLabelColor) }
        return .primary
    }

    @ViewBuilder
    private var background: some View {
        if isToday {
            LinearGradient(colors: [accentTop, accentBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: accentTop.opacity(0.45), radius: 3, y: 1.5)
        } else if isSelected {
            Color.accentColor.opacity(0.14)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if hovering && cell.isInCurrentMonth {
            Color.primary.opacity(0.07)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Color.clear
        }
    }
}

// MARK: - Event row

private struct EventRowView: View {
    let text: String
    let delete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer()
            Button(action: delete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(hovering ? .red : .clear)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0))
        )
        .onHover { hovering = $0 }
    }
}
