import SwiftUI
import UIKit
import WebKit

/// Embeds a YouTube video using the iframe API so mute/unmute can be applied
/// via JavaScript without reloading the video.
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    let muted: Bool

    final class Coordinator: NSObject {
        var currentVideoId: String
        var currentMuted: Bool

        init(videoId: String, muted: Bool) {
            currentVideoId = videoId
            currentMuted   = muted
        }

        func applyMute(_ muted: Bool, to webView: WKWebView) {
            let js = muted
                ? "if(window.ytPlayer)window.ytPlayer.mute();"
                : "if(window.ytPlayer)window.ytPlayer.unMute();"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(videoId: videoId, muted: muted)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        load(into: webView, videoId: videoId, muted: muted)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        if coord.currentVideoId != videoId {
            // Different video — full reload
            coord.currentVideoId = videoId
            coord.currentMuted   = muted
            load(into: webView, videoId: videoId, muted: muted)
        } else if coord.currentMuted != muted {
            // Same video, only mute state changed — apply via JS (no reload)
            coord.currentMuted = muted
            coord.applyMute(muted, to: webView)
        }
    }

    // MARK: - Private

    private func load(into webView: WKWebView, videoId: String, muted: Bool) {
        let muteParam = muted ? 1 : 0
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>
        * { margin:0; padding:0; background:#000; }
        html, body { width:100%; height:100%; overflow:hidden; }
        #player { position:absolute; top:0; left:0; width:100%; height:100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
        var tag = document.createElement('script');
        tag.src = 'https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);
        function onYouTubeIframeAPIReady() {
            window.ytPlayer = new YT.Player('player', {
                videoId: '\(videoId)',
                playerVars: {
                    autoplay: 1,
                    mute: \(muteParam),
                    playsinline: 1,
                    controls: 0,
                    rel: 0,
                    modestbranding: 1,
                    loop: 1,
                    playlist: '\(videoId)'
                },
                events: {
                    onReady: function(e) { e.target.playVideo(); }
                }
            });
        }
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
}
