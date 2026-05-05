//
//  RunLoopExtension.swift
//

import Foundation

public extension RunLoop {

    final class ResumeCondition {

        private let lock = NSLock()
        private var receivePorts = [Port]()

        private var _isResolved = false
        public var isResolved: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _isResolved
        }

        public init() {
        }

        func addPort(to runLoop: RunLoop, forMode mode: RunLoop.Mode) -> Port? {
            lock.lock()
            defer { lock.unlock() }
            guard !_isResolved else { return nil }

            let port = Port()
            receivePorts.append(port)
            runLoop.add(port, forMode: mode)

            return port
        }

        public func resolve(mode: RunLoop.Mode = .default) {
            lock.lock()

            assert(!_isResolved)
            _isResolved = true

            let ports = receivePorts

            lock.unlock()

            let sendPort = Port()
            RunLoop.current.add(sendPort, forMode: mode)

            for receivePort in ports.reversed() {
                receivePort.send(before: Date(), components: nil, from: sendPort, reserved: 0)
            }

            RunLoop.current.remove(sendPort, forMode: mode)
        }
    }

    func run(mode: RunLoop.Mode = .default, until condition: ResumeCondition) {
        guard let port = condition.addPort(to: self, forMode: mode) else {
            return
        }

        while !condition.isResolved {
            self.run(mode: mode, before: Date(timeIntervalSinceNow: 1.0))
        }
        self.remove(port, forMode: mode)
    }
}
