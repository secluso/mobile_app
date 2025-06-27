import Foundation

final class ByteQueueManager {
    private static var queues: [Int: Queue<Data>] = [:]
    private static var nextId: Int = 1
    private static let lock = NSLock()

    /// Allocate a new native byte queue and return its stream‑id
    static func createStream() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = nextId
        nextId += 1
        print("[SWIFT] createStream → \(id)")
        queues[id] = Queue<Data>()
        return id
    }

    static func push(id: Int, bytes: Data) {
        lock.lock()
        defer { lock.unlock() }
        print("[SWIFT] push(id:\(id), \(bytes.count) bytes)")
        queues[id]?.enqueue(bytes)
    }

    /// Enqueue EOF sentinel and remove queue
    static func finish(id: Int) {
        lock.lock()
        defer { lock.unlock() }
        queues[id]?.enqueue(Data())  // empty = EOF sentinel
    }

    static func pop(id: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return queues[id]?.dequeue()
    }

    static func queueLength(id: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return queues[id]?.count ?? 0
    }
}

/// Simple thread‑safe FIFO
final class Queue<T> {
    private var items = [T]()
    private let lock = NSLock()

    var count: Int { lock.withLock { items.count } }

    func enqueue(_ element: T) { lock.withLock { items.append(element) } }

    func dequeue() -> T? { lock.withLock { items.isEmpty ? nil : items.removeFirst() } }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
