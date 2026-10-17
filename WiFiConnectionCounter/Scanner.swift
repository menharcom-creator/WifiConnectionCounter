import Foundation
import Darwin

// MARK: - ICMP ping sweep

enum ICMPScanner {
    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(sum & 0xFFFF)
    }

    /// Sends echo requests to every target and reports each address that answers.
    /// Blocking: call from a background thread.
    static func sweep(targets: [UInt32],
                      rounds: Int,
                      onFound: (UInt32) -> Void,
                      onProgress: (Double) -> Void) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        func drain(waitMs: Int32) {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            while poll(&pfd, 1, waitMs) > 0 {
                while true {
                    var buf = [UInt8](repeating: 0, count: 1500)
                    var from = sockaddr_in()
                    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let n = withUnsafeMutablePointer(to: &from) { fp in
                        fp.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                            recvfrom(fd, &buf, buf.count, 0, sp, &len)
                        }
                    }
                    if n <= 0 { break }
                    var off = 0
                    if (buf[0] >> 4) == 4 { off = Int(buf[0] & 0x0F) * 4 }   // skip IP header
                    if n > off && buf[off] == 0 {                              // 0 = echo reply
                        onFound(UInt32(bigEndian: from.sin_addr.s_addr))
                    }
                }
                pfd.revents = 0
            }
        }

        let total = Double(max(1, targets.count * rounds))
        var sent = 0.0

        for round in 0..<rounds {
            for (index, ip) in targets.enumerated() {
                var packet = [UInt8](repeating: 0, count: 16)
                packet[0] = 8                                   // echo request
                packet[4] = 0xBE; packet[5] = 0xEF              // identifier
                let seq = UInt16(truncatingIfNeeded: index + round * 1000)
                packet[6] = UInt8(seq >> 8); packet[7] = UInt8(seq & 0xFF)
                let ck = checksum(packet)
                packet[2] = UInt8(ck >> 8); packet[3] = UInt8(ck & 0xFF)

                var addr = IPv4.makeAddr(ip)
                _ = withUnsafePointer(to: &addr) { ap in
                    ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                        sendto(fd, packet, packet.count, 0, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                sent += 1
                if index % 32 == 31 {
                    drain(waitMs: 0)
                    onProgress(sent / total)
                }
            }
            drain(waitMs: 1500)   // wait for stragglers (phones in power-save answer slowly)
            onProgress(sent / total)
        }
    }
}

// MARK: - TCP connect sweep (finds devices that ignore ping)

enum TCPScanner {
    static let ports: [UInt16] = [80, 443, 62078, 22, 445, 8080, 53, 5000]

    /// A host counts as alive if a port accepts the connection OR actively refuses it
    /// (a refusal means a real machine answered). Silence means nothing is known.
    static func sweep(targets: [UInt32],
                      onAlive: (UInt32) -> Void,
                      onProgress: (Double) -> Void) {
        var pairs: [(UInt32, UInt16)] = []
        for ip in targets { for p in ports { pairs.append((ip, p)) } }

        let batchSize = 100          // iOS allows ~256 open sockets per app
        var start = 0
        while start < pairs.count {
            let end = min(start + batchSize, pairs.count)
            let batch = pairs[start..<end]
            start = end

            var open: [(fd: Int32, ip: UInt32)] = []
            for (ip, port) in batch {
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                if fd < 0 { continue }
                let fl = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, fl | O_NONBLOCK)
                var addr = IPv4.makeAddr(ip, port: port)
                let r = withUnsafePointer(to: &addr) { ap in
                    ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                        connect(fd, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                let e = errno
                if r == 0 || e == ECONNREFUSED {
                    onAlive(ip); close(fd)
                } else if e == EINPROGRESS {
                    open.append((fd, ip))
                } else {
                    close(fd)
                }
            }

            var pfds = open.map { pollfd(fd: $0.fd, events: Int16(POLLOUT), revents: 0) }
            var remaining = pfds.count
            let deadline = Date().addingTimeInterval(0.9)
            while remaining > 0 && Date() < deadline {
                let ms = Int32(max(1, deadline.timeIntervalSinceNow * 1000))
                if poll(&pfds, nfds_t(pfds.count), ms) <= 0 { break }
                for k in pfds.indices where pfds[k].fd >= 0 && pfds[k].revents != 0 {
                    var err: Int32 = 0
                    var len = socklen_t(MemoryLayout<Int32>.size)
                    getsockopt(open[k].fd, SOL_SOCKET, SO_ERROR, &err, &len)
                    if err == 0 || err == ECONNREFUSED { onAlive(open[k].ip) }
                    close(open[k].fd)
                    pfds[k].fd = -1
                    remaining -= 1
                }
            }
            for k in pfds.indices where pfds[k].fd >= 0 { close(open[k].fd) }

            onProgress(Double(start) / Double(max(1, pairs.count)))
        }
    }
}
