import CLibraryPlatform
import CryptoKit
import Darwin
import Foundation

/// Descriptor-relative access keeps managed descendants from escaping through symlinks.
package final class LibraryDirectory {
    package let fd: Int32
    package let device: dev_t
    package let inode: ino_t
    package let parent: LibraryDirectory?
    package let name: String?
    package let url: URL

    package init(url: URL) throws {
        try Self.validateURL(url)
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let descriptor = Darwin.open(canonical.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw NativeLibraryError.io(errno) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            let error = errno
            Darwin.close(descriptor)
            throw NativeLibraryError.io(error)
        }
        fd = descriptor
        device = info.st_dev
        inode = info.st_ino
        self.url = canonical
        parent = nil
        name = nil
    }

    private init(parent: LibraryDirectory, name: String) throws {
        try parent.check()
        let descriptor = openat(parent.fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw NativeLibraryError.unsafePath }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_dev == parent.device else {
            Darwin.close(descriptor)
            throw NativeLibraryError.unsafePath
        }
        fd = descriptor
        device = info.st_dev
        inode = info.st_ino
        self.parent = parent
        self.name = name
        url = parent.url.appendingPathComponent(name)
    }

    deinit { Darwin.close(fd) }

    package static func validateURL(_ url: URL) throws {
        guard url.isFileURL, !url.path(percentEncoded: false).contains("\0"),
            url.host == nil || url.host == "" || url.host == "localhost"
        else {
            throw NativeLibraryError.unsafePath
        }
    }

    package func check() throws {
        var info = stat()
        if let parent, let name {
            try parent.check()
            guard fstatat(parent.fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw NativeLibraryError.unsafePath
            }
        } else {
            guard lstat(url.path, &info) == 0 else { throw NativeLibraryError.unsafePath }
        }
        guard info.st_dev == device, info.st_ino == inode,
            info.st_mode & S_IFMT == S_IFDIR
        else { throw NativeLibraryError.unsafePath }
    }

    package func qualify() throws {
        var volume = statfs()
        guard fstatfs(fd, &volume) == 0 else { throw NativeLibraryError.io(errno) }
        let type = withUnsafeBytes(of: volume.f_fstypename) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        guard type == "apfs", volume.f_flags & UInt32(MNT_LOCAL) != 0 else {
            throw NativeLibraryError.unsupportedFilesystem
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for location in ["Library/CloudStorage", "Library/Mobile Documents"] {
            let cloud = home.appendingPathComponent(location).resolvingSymlinksInPath().path
            guard url.path != cloud, !url.path.hasPrefix(cloud + "/") else {
                throw NativeLibraryError.unsupportedFilesystem
            }
        }
        let resources = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard resources.isUbiquitousItem != true else { throw NativeLibraryError.unsupportedFilesystem }
    }

    package func child(_ name: String, create: Bool = false) throws -> LibraryDirectory {
        try component(name)
        if create, try info(name) == nil {
            guard mkdirat(fd, name, 0o700) == 0 || errno == EEXIST else { throw NativeLibraryError.io(errno) }
            try sync()
        }
        return try LibraryDirectory(parent: self, name: name)
    }

    package func info(_ name: String) throws -> stat? {
        try component(name)
        try check()
        var value = stat()
        if fstatat(fd, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return nil }
            throw NativeLibraryError.io(errno)
        }
        return value
    }

    package func entries(maximum: Int = 100_000) throws -> [String] {
        try check()
        let descriptor = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw NativeLibraryError.io(errno) }
        guard let directory = fdopendir(descriptor) else {
            let error = errno
            Darwin.close(descriptor)
            throw NativeLibraryError.io(error)
        }
        defer { closedir(directory) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw NativeLibraryError.io(errno) }
                break
            }
            let count = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(bytes: raw.prefix(count), encoding: .utf8)
            }
            guard let name else { throw NativeLibraryError.unsafePath }
            if name == "." || name == ".." { continue }
            guard names.count < maximum else { throw NativeLibraryError.limitExceeded }
            names.append(name)
        }
        return names.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    package func read(_ name: String, maximum: Int) throws -> Data {
        try component(name)
        try check()
        let descriptor = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw NativeLibraryError.io(errno) }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw NativeLibraryError.io(errno) }
        guard before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1 else { throw NativeLibraryError.unsafePath }
        guard before.st_size >= 0, before.st_size <= maximum else { throw NativeLibraryError.limitExceeded }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw NativeLibraryError.io(errno)
            }
            if count == 0 { break }
            guard count <= maximum - data.count else { throw NativeLibraryError.limitExceeded }
            data.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw NativeLibraryError.io(errno) }
        guard before.st_size == after.st_size, data.count == before.st_size,
            before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
            before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
            before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
            before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
        else {
            throw NativeLibraryError.integrity
        }
        return data
    }

    package func fingerprint(_ name: String, maximum: Int) throws -> (sha256: String, bytes: Int) {
        try component(name)
        try check()
        let descriptor = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw NativeLibraryError.io(errno) }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw NativeLibraryError.io(errno) }
        guard before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1 else { throw NativeLibraryError.unsafePath }
        guard before.st_size >= 0, before.st_size <= maximum else { throw NativeLibraryError.limitExceeded }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var total = 0
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw NativeLibraryError.io(errno)
            }
            if count == 0 { break }
            guard count <= maximum - total else { throw NativeLibraryError.limitExceeded }
            hasher.update(data: buffer.prefix(count))
            total += count
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, before.st_size == after.st_size, total == before.st_size,
            before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
            before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
            before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
            before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
        else { throw NativeLibraryError.integrity }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }

    package func writeNew(_ name: String, data: Data) throws {
        try component(name)
        try check()
        let descriptor = openat(fd, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw NativeLibraryError.io(errno) }
        defer { Darwin.close(descriptor) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw NativeLibraryError.io(errno)
                }
                guard written > 0 else { throw NativeLibraryError.io(EIO) }
                offset += written
            }
        }
        guard fsync(descriptor) == 0, fcntl(descriptor, F_FULLFSYNC) == 0 else {
            throw NativeLibraryError.io(errno)
        }
        try sync()
    }

    package func move(_ name: String, to directory: LibraryDirectory, as target: String, replacing: Bool = false) throws
    {
        try component(name)
        try component(target)
        try check()
        try directory.check()
        guard directory.device == device else { throw NativeLibraryError.unsafePath }
        let flags = replacing ? UInt32(0) : UInt32(RENAME_EXCL)
        guard renameatx_np(fd, name, directory.fd, target, flags) == 0 else { throw NativeLibraryError.io(errno) }
        try directory.sync()
        try sync()
    }

    package func remove(_ name: String, directory: Bool = false) throws {
        try component(name)
        try check()
        guard unlinkat(fd, name, directory ? AT_REMOVEDIR : 0) == 0 else { throw NativeLibraryError.io(errno) }
        try sync()
    }

    package func sync() throws {
        guard fsync(fd) == 0 else { throw NativeLibraryError.io(errno) }
    }

    private func component(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0"),
            name.utf8.count <= 255
        else { throw NativeLibraryError.unsafePath }
    }
}

final class LibraryLease {
    private(set) var fd: Int32
    let directory: LibraryDirectory
    private let inode: ino_t

    init(directory: LibraryDirectory, create: Bool) throws {
        self.directory = directory
        let flags = O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (create ? O_CREAT : 0)
        let descriptor = openat(directory.fd, ".owner.lock", flags, 0o600)
        guard descriptor >= 0 else { throw NativeLibraryError.unsafePath }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_nlink == 1, info.st_size == 0, info.st_dev == directory.device
        else {
            Darwin.close(descriptor)
            throw NativeLibraryError.unsafePath
        }
        guard fb_library_flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            Darwin.close(descriptor)
            if error == EWOULDBLOCK || error == EAGAIN { throw NativeLibraryError.inUse }
            throw NativeLibraryError.io(error)
        }
        fd = descriptor
        inode = info.st_ino
        do {
            try check()
            if create {
                guard fsync(descriptor) == 0, fcntl(descriptor, F_FULLFSYNC) == 0 else {
                    throw NativeLibraryError.io(errno)
                }
                try directory.sync()
            }
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    func check() throws {
        guard fd >= 0 else { throw NativeLibraryError.closed }
        try directory.check()
        guard let info = try directory.info(".owner.lock"), info.st_ino == inode,
            info.st_dev == directory.device, info.st_nlink == 1,
            info.st_mode & S_IFMT == S_IFREG, info.st_size == 0
        else { throw NativeLibraryError.unsafePath }
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    func loan() throws -> LibraryOwnershipLoan {
        try check()
        let duplicate = fcntl(fd, F_DUPFD_CLOEXEC, 4)
        guard duplicate >= 0 else { throw NativeLibraryError.io(errno) }
        return LibraryOwnershipLoan(descriptor: duplicate)
    }
}

/// Shares the same flock open-file description; closing never explicitly unlocks it.
package final class LibraryOwnershipLoan {
    package private(set) var descriptor: Int32
    init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { close() }
    func close() {
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
    }
}
