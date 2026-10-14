import SwiftUI
import CairnCore

/// Settings → Recovery → Review Immich trash. The reverse direction:
/// photos moved to Immich's trash (for example, deleted on the web) that
/// are still on this iPhone. The host runs `ServerTrashMatcher`; this
/// screen lists the matches and hands the reviewed set back for
/// deletion. iOS shows its own confirmation after "Delete".
///
/// States mirror `model.serverTrashReviewState`.
public struct ServerTrashReviewSheet: View {

    public let state: CairnAppModel.ServerTrashReviewState
    public let onClose: () -> Void
    public let onScan: (_ lookbackDays: Int) -> Void
    public let onDelete: (_ candidates: [LocalDeleteCandidate]) -> Void
    public let onKeep: (_ candidates: [LocalDeleteCandidate]) -> Void

    @Environment(\.cairnTokens) private var t
    @State private var lookbackDays: Int = 7
    @State private var skippedIds: Set<String> = []
    @State private var pendingDelete = false
    @State private var pendingKeep = false
    @State private var zoomed: LocalDeleteCandidate?

    public init(
        state: CairnAppModel.ServerTrashReviewState = .idle,
        onClose: @escaping () -> Void = {},
        onScan: @escaping (Int) -> Void = { _ in },
        onDelete: @escaping ([LocalDeleteCandidate]) -> Void = { _ in },
        onKeep: @escaping ([LocalDeleteCandidate]) -> Void = { _ in }
    ) {
        self.state = state
        self.onClose = onClose
        self.onScan = onScan
        self.onDelete = onDelete
        self.onKeep = onKeep
    }

    private static let lookbackOptions: [Int] = [1, 7, 30]

    public var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().background(t.divider)
                content
            }
        }
        .confirmationDialog(
            "Delete \(visible.count) from this iPhone?",
            isPresented: $pendingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(visible.count)", role: .destructive) { onDelete(visible) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("iOS will ask you to confirm. Photos go to Recently Deleted and can be recovered there for 30 days.")
        }
        .confirmationDialog(
            "Keep all \(visible.count) on this iPhone?",
            isPresented: $pendingKeep,
            titleVisibility: .visible
        ) {
            Button("Keep \(visible.count)") { onKeep(visible) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll be added to the exclusion list and won't be offered again.")
        }
        .overlay(zoomOverlay)
        .onChange(of: candidateIds) { _, _ in skippedIds.removeAll() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Immich trash")
                    .font(.cairnScaled(size: 17, weight: .semibold))
                    .foregroundStyle(t.text)
                if review != nil {
                    Text(visible.isEmpty ? "Nothing to delete" : "\(visible.count) on this iPhone")
                        .font(.cairnScaled(size: 12))
                        .foregroundStyle(t.textMuted)
                }
            }
            Spacer()
            Button("Done", action: onClose)
                .font(.cairnScaled(size: 15))
                .foregroundStyle(t.textBody)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            idleState
        case .scanning:
            progressState("Checking Immich's trash…")
        case .deleting:
            progressState("Waiting for iOS…")
        case .loaded:
            if visible.isEmpty { emptyState } else { loadedState }
        case .error(let message):
            errorState(message)
        }
    }

    private var idleState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "trash")
                    .font(.cairnScaled(size: 32))
                    .foregroundStyle(t.textMuted)
                    .padding(.top, 16)
                (Text("Finds photos moved to Immich's trash that are still on this iPhone. Matches are by file content, so only photos ") + .cairnWord + Text(" has indexed show up."))
                    .font(.cairnScaled(size: 13))
                    .foregroundStyle(t.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
                scanCard
            }
            .padding(.bottom, 24)
        }
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRASHED IN THE LAST")
                .font(.cairnScaled(size: 11, weight: .semibold))
                .tracking(0.99)
                .foregroundStyle(t.textMuted)
            Picker("Trashed in the last", selection: $lookbackDays) {
                ForEach(Self.lookbackOptions, id: \.self) { days in
                    Text(days == 1 ? "Day" : "\(days) days").tag(days)
                }
            }
            .pickerStyle(.segmented)
            CairnChip("Start scan", accessibilityLabel: "Start scan", action: { onScan(lookbackDays) })
        }
        .padding(14)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }

    private func progressState(_ label: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(label)
                .font(.cairnScaled(size: 13))
                .foregroundStyle(t.textMuted)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle().fill(t.infoSoft).frame(width: 56, height: 56)
                Image(systemName: "checkmark")
                    .font(.cairnScaled(size: 22, weight: .semibold))
                    .foregroundStyle(t.infoInk)
            }
            Text("Nothing to delete")
                .font(.cairnScaled(size: 17, weight: .semibold))
                .foregroundStyle(t.text)
            Text(emptyDetail)
                .font(.cairnScaled(size: 13))
                .foregroundStyle(t.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let skippedLine {
                Text(skippedLine)
                    .font(.cairnScaled(size: 12))
                    .foregroundStyle(t.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            CairnChip("Scan again", accessibilityLabel: "Scan again", action: { onScan(lookbackDays) })
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.cairnScaled(size: 28))
                .foregroundStyle(t.dangerInk)
            Text("Couldn't finish")
                .font(.cairnScaled(size: 17, weight: .semibold))
                .foregroundStyle(t.text)
            Text(message)
                .font(.cairnScaled(size: 13))
                .foregroundStyle(t.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            CairnChip("Retry", accessibilityLabel: "Retry", action: { onScan(lookbackDays) })
            Spacer()
        }
    }

    private var loadedState: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Callout(.info, icon: "info.circle") {
                    Text("These are in Immich's trash and still on this iPhone. Delete moves them to Recently Deleted; Keep adds them to the exclusion list.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let blocked = review?.blockedReason(forCount: visible.count) {
                    Callout(.danger, icon: "exclamationmark.triangle") {
                        Text(blocked).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let skippedLine {
                    Text(skippedLine)
                        .font(.cairnScaled(size: 12))
                        .foregroundStyle(t.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, candidate in
                        ServerTrashRow(
                            candidate: candidate,
                            onZoom: { zoomed = candidate },
                            onSkip: { skippedIds.insert(candidate.localIdentifier) }
                        )
                        if idx < visible.count - 1 { RowDivider() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 88)
            }

            actionBar
        }
    }

    private var actionBar: some View {
        let blocked = review?.blockedReason(forCount: visible.count) != nil
        return HStack(spacing: 10) {
            Button { pendingKeep = true } label: {
                Text("Keep all")
                    .font(.cairnScaled(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(t.surfaceAlt)
                    .foregroundStyle(t.textBody)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button { pendingDelete = true } label: {
                Text("Delete \(visible.count) from iPhone")
                    .font(.cairnScaled(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(t.danger)
                    .foregroundStyle(t.dangerInk)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(blocked ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(blocked)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(t.bg)
        .overlay(Rectangle().fill(t.divider).frame(height: 0.5), alignment: .top)
    }

    @ViewBuilder
    private var zoomOverlay: some View {
        if let candidate = zoomed {
            ZStack {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .onTapGesture { zoomed = nil }
                    .accessibilityLabel("Close zoomed thumbnail")
                    .accessibilityAddTraits(.isButton)
                ImmichAssetThumb(
                    assetId: candidate.serverAsset.id,
                    filename: candidate.serverAsset.originalFileName ?? "",
                    size: 320,
                    isLivePair: candidate.serverAsset.livePhotoVideoId != nil
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .transition(.opacity)
            .accessibilityAddTraits(.isModal)
        }
    }

    // MARK: - Helpers

    private var review: ServerTrashReview? {
        switch state {
        case .loaded(let r), .deleting(let r): return r
        default: return nil
        }
    }

    private var visible: [LocalDeleteCandidate] {
        (review?.candidates ?? []).filter { !skippedIds.contains($0.localIdentifier) }
    }

    private var candidateIds: [String] {
        (review?.candidates ?? []).map(\.localIdentifier)
    }

    private var emptyDetail: String {
        guard let review else { return "" }
        let window = review.lookbackDays == 1 ? "the last day" : "the last \(review.lookbackDays) days"
        if review.trashedOnServer == 0 {
            return "Nothing was moved to Immich's trash in \(window)."
        }
        return "\(review.trashedOnServer) item\(review.trashedOnServer == 1 ? "" : "s") trashed on Immich in \(window), none still on this iPhone."
    }

    private var skippedLine: String? {
        guard let review, !review.skipped.isEmpty else { return nil }
        let parts: [String] = ServerTrashSkipReason.allCases.compactMap { reason in
            guard let n = review.skipped[reason], n > 0 else { return nil }
            switch reason {
            case .trashedByCairn: return "\(n) recovered after cairn trashed them"
            case .excluded: return "\(n) on the exclusion list"
            case .outOfPurview: return "\(n) outside cairn's scope"
            case .notVerified: return "\(n) not yet verified on this iPhone"
            case .editedOriginalKept: return "\(n) edited, original still on Immich"
            }
        }
        return "Left alone: " + parts.joined(separator: ", ") + "."
    }
}

// MARK: - Row

private struct ServerTrashRow: View {
    let candidate: LocalDeleteCandidate
    let onZoom: () -> Void
    let onSkip: () -> Void

    @Environment(\.cairnTokens) private var t

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onZoom) {
                ImmichAssetThumb(
                    assetId: candidate.serverAsset.id,
                    filename: candidate.serverAsset.originalFileName ?? "",
                    size: 44,
                    isLivePair: candidate.serverAsset.livePhotoVideoId != nil
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.serverAsset.originalFileName ?? "—")
                    .font(.cairnScaled(size: 13, design: .monospaced))
                    .tracking(-0.065)
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let date = candidate.serverAsset.fileCreatedAt {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.cairnScaled(size: 11.5))
                        .foregroundStyle(t.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CairnChip("Skip", accessibilityLabel: "Skip \(candidate.serverAsset.originalFileName ?? "")", action: onSkip)
        }
        .padding(.vertical, 10)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

#if DEBUG
private let previewReview = ServerTrashReview(
    candidates: [
        LocalDeleteCandidate(
            localIdentifier: "L1",
            checksums: [Checksum(base64: "AAA")],
            serverAsset: ServerAsset(id: "1", checksum: Checksum(base64: "AAA"), isTrashed: true, originalFileName: "IMG_4391.HEIC", fileCreatedAt: Date().addingTimeInterval(-86_400))
        ),
        LocalDeleteCandidate(
            localIdentifier: "L2",
            checksums: [Checksum(base64: "BBB"), Checksum(base64: "CCC")],
            serverAsset: ServerAsset(id: "2", checksum: Checksum(base64: "BBB"), livePhotoVideoId: "m2", isTrashed: true, originalFileName: "IMG_4392.HEIC", fileCreatedAt: Date().addingTimeInterval(-86_400 * 2))
        ),
    ],
    skipped: [.editedOriginalKept: 1, .trashedByCairn: 2],
    trashedOnServer: 5,
    lookbackDays: 7,
    liveLibraryCount: 4_000
)

#Preview("server trash - loaded") {
    ServerTrashReviewSheet(state: .loaded(previewReview)).cairnTheme()
}

#Preview("server trash - blocked") {
    ServerTrashReviewSheet(state: .loaded(ServerTrashReview(
        candidates: previewReview.candidates,
        lookbackDays: 30,
        liveLibraryCount: 0
    ))).cairnTheme()
}

#Preview("server trash - empty") {
    ServerTrashReviewSheet(state: .loaded(ServerTrashReview(candidates: [], trashedOnServer: 3, lookbackDays: 7))).cairnTheme()
}

#Preview("server trash - idle") {
    ServerTrashReviewSheet().cairnTheme()
}
#endif
