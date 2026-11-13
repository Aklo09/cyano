import CLibraryPlatform
import Darwin
import Foundation
import LibraryCore

final class PreviewChild {
    let pid: Int32
    private var exitCode: Int32?
    private var reaped = false

    init(url: URL, input: Int32, output: Int32, errors: Int32, ownership: LibraryOwnershipLoan?) throws {
        try LibraryDirectory.validateURL(url)
        var child: Int32 = 0
        let error = url.path.withCString {
            fb_spawn_preview($0, input, output, errors, ownership?.descriptor ?? -1, &child)
        }
        guard error == 0 else { throw NativeLibraryError.io(error) }
        pid = child
    }

    func running() throws -> Bool {
        if exitCode != nil { return false }
        var status: Int32 = -1
        let result = fb_wait_preview(pid, 1, &status)
        guard result >= 0 else {
            reaped = true
            throw PreviewError.workerFailed
        }
        if result == 1 {
            exitCode = status
            return false
        }
        return true
    }

    func killGroup() { _ = Darwin.kill(-pid, SIGKILL) }

    func wait() throws {
        if reaped { return }
        // The unreaped leader reserves its PID/PGID; no unrelated process group can reuse it.
        killGroup()
        var status: Int32 = -1
        let result = fb_wait_preview(pid, 0, &status)
        reaped = true
        guard result == 1 else { throw PreviewError.workerFailed }
        exitCode = status
    }

    func cleanup() { if !reaped { try? wait() } }

    var succeeded: Bool { exitCode == 0 }
}
