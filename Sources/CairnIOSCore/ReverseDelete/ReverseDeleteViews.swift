import SwiftUI
import CairnCore

// Hook points for the reverse direction. Each is one line in a cairn
// screen; everything else lives in this folder.

/// Rows appended to Settings → Data & recovery → Recovery.
public struct ReverseDeleteSettingsRows: View {
    @Bindable private var controller: ReverseDeleteController
    @Environment(\.cairnTokens) private var t

    public init(controller: ReverseDeleteController = .shared) {
        self.controller = controller
    }

    public var body: some View {
        RowDivider()
        ToggleRow(
            "Delete on iPhone what's trashed on Immich",
            sub: "Off by default. Checks Immich's trash about once a day during sync and reminds you weekly if photos trashed there are still on this iPhone. Nothing is deleted until you confirm, and iOS asks once more. Deleted photos stay in Recently Deleted for 30 days.",
            value: $controller.isEnabled
        )
        if controller.isEnabled {
            RowDivider()
            reminderRow
            RowDivider()
            KeyValRow(
                "Review Immich trash",
                value: {
                    Text(controller.pendingCount > 0 ? "\(controller.pendingCount) waiting" : "Scan now")
                        .foregroundStyle(t.infoInk)
                },
                chevron: true,
                onTap: { controller.openReview() }
            )
        }
    }

    private var reminderRow: some View {
        HStack(spacing: 8) {
            Text("Weekly reminder")
                .font(.cairnScaled(size: 15))
                .foregroundStyle(t.textBody)
            Spacer(minLength: 0)
            Picker("Day", selection: $controller.reminderWeekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(Calendar.current.shortWeekdaySymbols[day - 1]).tag(day)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var reminderTime: Binding<Date> {
        Binding(
            // Wall-clock hour/minute, not startOfDay + offset, which is an
            // hour off on daylight-saving change days.
            get: {
                let m = controller.reminderMinuteOfDay
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                controller.reminderMinuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

/// One line under "Last checked" in the Status card. Hidden unless the
/// feature is on and something is waiting.
public struct ReverseDeleteStatusLine: View {
    private let controller: ReverseDeleteController
    @Environment(\.cairnTokens) private var t

    public init(controller: ReverseDeleteController = .shared) {
        self.controller = controller
    }

    public var body: some View {
        if controller.isEnabled, controller.pendingCount > 0 {
            Button(action: { controller.openReview() }) {
                Text("\(controller.pendingCount) to delete on iPhone ›")
                    .font(.cairnScaled(size: 11, weight: .semibold))
                    .foregroundStyle(t.infoInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(controller.pendingCount) trashed on Immich, still on this iPhone. Review.")
        }
    }
}

/// Presents the review sheet. Attached once at the app root.
private struct ReverseDeleteSheetModifier: ViewModifier {
    @Bindable var controller: ReverseDeleteController
    let palette: CairnPalette

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: $controller.isSheetPresented,
            onDismiss: { controller.reviewState = .idle }
        ) {
            ServerTrashReviewSheet(
                state: controller.reviewState,
                onClose: { controller.closeReview() },
                onScan: { controller.startScan(lookbackDays: $0) },
                onDelete: { controller.delete($0) },
                onKeep: { controller.keep($0) }
            )
            .cairnTheme(palette)
        }
    }
}

public extension View {
    func reverseDeleteSheet(palette: CairnPalette, controller: ReverseDeleteController = .shared) -> some View {
        modifier(ReverseDeleteSheetModifier(controller: controller, palette: palette))
    }
}
