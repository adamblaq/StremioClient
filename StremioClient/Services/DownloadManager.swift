import Foundation
import Observation

@Observable
class DownloadManager: NSObject {
    var downloads: [Download] = []

    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    private var backgroundSession: URLSession!
    // For speed calculation: last measurement per download
    private var speedSamples: [UUID: [(bytes: Int64, time: Date)]] = [:]

    private let storageKey = "downloads"
    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.stremio.client.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        loadFromDisk()
    }

    // MARK: - Public API

    func startDownload(meta: MetaItem, stream: StreamItem, episode: MetaItem.Video? = nil) async {
        guard stream.isDirectPlay, let sourceURL = stream.streamURL else { return }

        let resolvedURL = await RedirectResolver.resolve(sourceURL)
        guard resolvedURL != sourceURL else {
            print("[Download] Could not resolve redirect — aborting")
            return
        }

        print("[Download] Starting: \(resolvedURL.absoluteString)")
        let download = Download(meta: meta, resolvedURL: resolvedURL, episode: episode)
        enqueue(download)
    }

    func retryDownload(_ failed: Download) {
        guard let url = URL(string: failed.sourceURL) else { return }
        cancelDownload(failed)
        let download = Download(retrying: failed)
        print("[Download] Retrying: \(url.absoluteString)")
        enqueue(download)
    }

    func cancelDownload(_ download: Download) {
        activeTasks[download.id]?.cancel()
        activeTasks.removeValue(forKey: download.id)
        speedSamples.removeValue(forKey: download.id)
        if let path = download.localPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        downloads.removeAll { $0.id == download.id }
        saveToDisk()
    }

    func deleteDownload(_ download: Download) { cancelDownload(download) }

    func existingDownload(metaId: String, season: Int? = nil, episode: Int? = nil) -> Download? {
        downloads.first { $0.metaId == metaId && $0.season == season && $0.episode == episode }
    }

    // MARK: - Private

    private func enqueue(_ download: Download) {
        downloads.append(download)
        saveToDisk()

        guard let url = URL(string: download.sourceURL) else { return }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        let task = backgroundSession.downloadTask(with: request)
        activeTasks[download.id] = task
        task.taskDescription = download.id.uuidString
        task.resume()
        updateStatus(id: download.id, status: .downloading)
    }

    private func updateStatus(id: UUID, status: Download.Status) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].status = status
        saveToDisk()
    }

    private func updateProgress(id: UUID, bytesWritten: Int64, totalBytes: Int64) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }

        // Speed: rolling average over the last 2 seconds of samples
        let now = Date()
        let windowSeconds: TimeInterval = 2.0
        var samples = speedSamples[id] ?? []
        samples.append((bytesWritten, now))
        // Drop samples older than the window
        samples = samples.filter { now.timeIntervalSince($0.time) <= windowSeconds }
        speedSamples[id] = samples

        var speed = downloads[i].speedBytesPerSecond
        if samples.count >= 2, let oldest = samples.first {
            let dt = now.timeIntervalSince(oldest.time)
            if dt > 0 {
                speed = Double(bytesWritten - oldest.bytes) / dt
            }
        }

        downloads[i].downloadedBytes = bytesWritten
        downloads[i].totalBytes = totalBytes
        downloads[i].speedBytesPerSecond = max(0, speed)
        downloads[i].progress = totalBytes > 0 ? Double(bytesWritten) / Double(totalBytes) : 0
    }

    private func finishDownload(id: UUID, tempURL: URL) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        let raw = URL(string: downloads[i].sourceURL)?.pathExtension ?? ""
        let ext = raw.isEmpty ? "mp4" : raw
        let dest = documentsDir.appendingPathComponent("\(id.uuidString).\(ext)")
        try? FileManager.default.moveItem(at: tempURL, to: dest)
        downloads[i].localPath = dest.path
        downloads[i].status = .completed
        downloads[i].progress = 1.0
        downloads[i].speedBytesPerSecond = 0
        activeTasks.removeValue(forKey: id)
        speedSamples.removeValue(forKey: id)
        saveToDisk()
        print("[Download] Completed: \(dest.lastPathComponent)")
    }

    // MARK: - Persistence

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(downloads) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Download].self, from: data)
        else { return }
        // Keep downloading/queued as-is — background URLSession reconnects and delivers callbacks.
        // If a task was truly lost the delegate will fire didCompleteWithError and mark it failed.
        downloads = saved
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let idString = downloadTask.taskDescription,
              let id = UUID(uuidString: idString) else { return }

        // iOS deletes `location` the moment this method returns.
        // Move the file to a temp path we own SYNCHRONOUSLY before returning,
        // then update the model on the main queue.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent(id.uuidString + "_staging")
        do {
            if FileManager.default.fileExists(atPath: staging.path) {
                try FileManager.default.removeItem(at: staging)
            }
            try FileManager.default.moveItem(at: location, to: staging)
        } catch {
            print("[Download] Failed to stage file: \(error)")
            DispatchQueue.main.async { self.updateStatus(id: id, status: .failed) }
            return
        }

        DispatchQueue.main.async { self.finishDownload(id: id, tempURL: staging) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let idString = downloadTask.taskDescription,
              let id = UUID(uuidString: idString) else { return }
        DispatchQueue.main.async {
            self.updateProgress(id: id, bytesWritten: totalBytesWritten,
                                totalBytes: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error,
              let idString = task.taskDescription,
              let id = UUID(uuidString: idString) else { return }
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async { self.updateStatus(id: id, status: .failed) }
    }
}
