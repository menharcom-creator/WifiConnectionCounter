import Foundation
import Darwin

enum IPv4 {
    static func string(_ v: UInt32) -> String {
        "\((v >> 24) & 255).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)"
    }

    static func makeAddr(_ v: UInt32, port: UInt16 = 0) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr.s_addr = v.bigEndian
        return a
    }
}

struct LocalNetwork {
    let interface: String
    let ip: UInt32      // host byte order
    let mask: UInt32

    var network: UInt32 { ip & mask }
    var prefixLength: Int { mask.nonzeroBitCount }
    var ipString: String { IPv4.string(ip) }
    var cidr: String {
        let net = prefixLength < 22 ? (ip & 0xFFFF_FC00) : network
        let len = prefixLength < 22 ? 22 : prefixLength
        return "\(IPv4.string(net))/\(len)"
    }

    /// Every usable address we will probe. Capped at a /22 (1022 hosts)
    /// around the phone's own address so a huge network doesn't take forever.
    var targets: [UInt32] {
        var net = network
        var bcast = network | ~mask
        if prefixLength < 22 {
            let m: UInt32 = 0xFFFF_FC00
            net = ip & m
            bcast = net | ~m
        }
        guard bcast > net + 1 else { return [] }
        return Array((net + 1)..<bcast).filter { $0 != ip }
    }

    var isCapped: Bool { prefixLength < 22 }
}

enum NetworkInfo {
    /// Finds the Wi-Fi interface (en0) and reads its IPv4 address + netmask.
    static func current() -> LocalNetwork? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = cursor {
            let ifa = cur.pointee
            let name = String(cString: ifa.ifa_name)
            if name == "en0",
               (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
               let addr = ifa.ifa_addr,
               addr.pointee.sa_family == sa_family_t(AF_INET),
               let nm = ifa.ifa_netmask {
                let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                let mask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                }
                if ip != 0 && mask != 0 {
                    return LocalNetwork(interface: name, ip: ip, mask: mask)
                }
            }
            cursor = ifa.ifa_next
        }
        return nil
    }

    /// Reverse-DNS name for an address (works only if the router publishes names).
    static func hostname(for ip: UInt32) -> String? {
        var addr = IPv4.makeAddr(ip)
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let r = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                getnameinfo(sp, socklen_t(MemoryLayout<sockaddr_in>.size),
                            &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard r == 0 else { return nil }
        let s = String(cString: host)
        return s.isEmpty ? nil : s
    }
}
