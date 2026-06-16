import Foundation

/// Watches a directory for filesystem changes (writes/renames/deletes within it)
/// using a DispatchSource, and fires `onChange` on the main queue. One per root.
/// The raw FS callback is verified manually; consumers test their own refresh
/// logic.
public final class DirectoryWatcher {

    private let url: URL
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let onChange: () -> Void

    public init?(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main)
        src.setEventHandler { [weak self] in self?.onChange() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }
        source = src
        src.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
