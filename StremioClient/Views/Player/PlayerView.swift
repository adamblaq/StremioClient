import SwiftUI
import AVKit

struct PlayerView: View {
    let stream: StreamItem
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var setupTask: Task<Void, Never>?
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text("Playback Failed")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Close") {
                        setupTask?.cancel()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView("Loading stream…")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // X button fades out after 3 s of inactivity, like native video controls
            if errorMessage == nil {
                Button {
                    setupTask?.cancel()
                    player?.pause()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.8))
                        .shadow(radius: 4)
                        .padding()
                }
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
                .animation(.easeInOut(duration: 0.3), value: showControls)
            }
        }
        // simultaneousGesture on the ZStack parent fires via touch bubbling from the
        // AVKit UIKit view below, without blocking VideoPlayer's own controls.
        .simultaneousGesture(TapGesture().onEnded { bumpControls() })
        .onAppear {
            setupTask = Task { await setupPlayer() }
            scheduleHide()
        }
        .onDisappear {
            setupTask?.cancel()
            hideTask?.cancel()
            player?.pause()
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Control visibility

    private func bumpControls() {
        showControls = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showControls = false
        }
    }

    // MARK: - Playback setup

    private func setupPlayer() async {
        guard let url = stream.streamURL else {
            errorMessage = "Invalid stream URL"
            return
        }

        print("[Player] Original URL: \(url.absoluteString)")
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let playbackURL: URL
        if url.isFileURL {
            // Rebuild via fileURLWithPath so iOS resolves /var → /private/var symlinks.
            // URL(string: "file:///var/...") gives the literal path; AVFoundation then
            // can't open it because the real filesystem path is /private/var/...
            let resolvedURL = URL(fileURLWithPath: url.path)
            guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
                errorMessage = "Downloaded file not found. Please delete it and re-download."
                return
            }
            playbackURL = resolvedURL
        } else {
            // Torrentio resolve URLs cause an EXC_BAD_ACCESS crash in AVFoundation's
            // QUIC stack. We resolve the redirect using NWConnection (TCP-only, no QUIC)
            // to get the real-debrid.com CDN URL before touching AVPlayer.
            let resolved = await RedirectResolver.resolve(url)
            guard !Task.isCancelled else { return }
            guard resolved != url else {
                errorMessage = "Could not resolve stream URL (redirect timed out). Try a different stream."
                return
            }
            print("[Player] Resolved to: \(resolved.absoluteString)")
            playbackURL = resolved
        }

        // Real-Debrid CDN and some other hosts reject requests without a browser User-Agent.
        // HTTP headers are safely ignored for local file:// URLs.
        let asset = AVURLAsset(url: playbackURL, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
            ]
        ])
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer

        // AsyncStream + KVO: thread-safe, terminates after first definitive status.
        let statusStream = AsyncStream<(AVPlayerItem.Status, (any Error)?)> { cont in
            let obs = item.observe(\.status, options: [.initial, .new]) { observed, _ in
                switch observed.status {
                case .readyToPlay:
                    cont.yield((.readyToPlay, nil))
                    cont.finish()
                case .failed:
                    cont.yield((.failed, observed.error))
                    cont.finish()
                default:
                    break
                }
            }
            cont.onTermination = { _ in obs.invalidate() }
        }

        for await (status, error) in statusStream {
            switch status {
            case .readyToPlay:
                print("[Player] Ready — starting playback")
                avPlayer.play()
            case .failed:
                let msg = error?.localizedDescription ?? "Unknown error"
                print("[Player] Failed: \(msg)")
                if let nsErr = error as? NSError {
                    print("[Player] Domain: \(nsErr.domain) Code: \(nsErr.code)")
                    print("[Player] UserInfo: \(nsErr.userInfo)")
                    if let underlying = nsErr.userInfo[NSUnderlyingErrorKey] as? NSError {
                        print("[Player] Underlying: \(underlying.domain) \(underlying.code) \(underlying.userInfo)")
                    }
                }
                errorMessage = msg
            default:
                break
            }
        }
    }
}

