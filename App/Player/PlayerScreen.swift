import AVKit
import SwiftUI
import StreamCore

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var controller: PlayerController

    init(request: PlaybackRequest, model: AppModel) {
        _controller = State(initialValue: PlayerController(request: request, model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                PlayerViewRepresentable(controller: controller)
                if let message = controller.failureMessage {
                    failure(message)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let notice = controller.notice {
                Text(notice)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 60)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.notice)
        .environment(\.colorScheme, .dark)
        .persistentSystemOverlays(.hidden)
        .task { await controller.start() }
        .onDisappear { controller.stop() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Close player")

            VStack(alignment: .leading, spacing: 1) {
                Text(controller.request.meta.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = controller.request.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            audioMenu
            subtitleMenu
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black)
    }

    @ViewBuilder
    private var audioMenu: some View {
        if controller.audioOptions.count > 1 {
            Menu {
                Picker("Audio", selection: Binding(
                    get: { controller.selectedAudioID },
                    set: { controller.selectAudio($0) }
                )) {
                    ForEach(controller.audioOptions) { option in
                        Text(option.name).tag(Optional(option.id))
                    }
                }
            } label: {
                Image(systemName: "waveform.circle")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Audio track")
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Picker("Subtitles", selection: Binding(
                get: { controller.subtitleSelection },
                set: { controller.selectSubtitle($0) }
            )) {
                Text("Off").tag(SubtitleSelection.off)
                if !controller.embeddedSubtitles.isEmpty {
                    Section("In This Stream") {
                        ForEach(controller.embeddedSubtitles) { option in
                            Text(option.name).tag(SubtitleSelection.embedded(option.id))
                        }
                    }
                }
                if !controller.externalSubtitles.isEmpty {
                    Section("From Add-ons") {
                        ForEach(controller.externalSubtitles) { subtitle in
                            Text(subtitle.displayName).tag(SubtitleSelection.external(subtitle.id))
                        }
                    }
                }
            }

            if case .external = controller.subtitleSelection {
                Section("Timing") {
                    Button("Show Earlier (−0.25 s)", systemImage: "backward") { controller.shiftSubtitles(by: -0.25) }
                    Button("Show Later (+0.25 s)", systemImage: "forward") { controller.shiftSubtitles(by: 0.25) }
                    if controller.subtitleDelay != 0 {
                        Button("Reset Timing", systemImage: "arrow.counterclockwise") { controller.resetSubtitleDelay() }
                    }
                }
            }
        } label: {
            Image(systemName: controller.subtitleSelection == .off ? "captions.bubble" : "captions.bubble.fill")
                .font(.title3)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Subtitles")
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("Playback Failed").font(.headline)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding()
    }
}

/// Hosts AVPlayerViewController for the system controls, AirPlay,
/// Picture in Picture and playback speed, with add-on subtitles drawn
/// in its content overlay so they sit above the video but below the controls.
struct PlayerViewRepresentable: UIViewControllerRepresentable {
    let controller: PlayerController

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerController = AVPlayerViewController()
        playerController.player = controller.player
        playerController.allowsPictureInPicturePlayback = true
        playerController.canStartPictureInPictureAutomaticallyFromInline = true
        playerController.updatesNowPlayingInfoCenter = true
        playerController.entersFullScreenWhenPlaybackBegins = false

        if let overlay = playerController.contentOverlayView {
            let host = UIHostingController(rootView: SubtitleOverlay(controller: controller))
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.translatesAutoresizingMaskIntoConstraints = false
            playerController.addChild(host)
            overlay.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: overlay.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: overlay.bottomAnchor)
            ])
            host.didMove(toParent: playerController)
        }
        return playerController
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

private struct SubtitleOverlay: View {
    let controller: PlayerController
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 19

    var body: some View {
        VStack {
            Spacer()
            if let text = controller.subtitleText {
                Text(text)
                    .font(.system(size: fontSize, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
