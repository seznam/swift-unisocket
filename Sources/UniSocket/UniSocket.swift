import Foundation
import Glibc

public enum UniSocketError: Error {
	case error(detail: String)
}

public enum UniSocketType: String {
	case tcp
	case udp
	case local
}

public enum UniSocketStatus: String {
	case none
	case stateless
	case connected
	case listening
	case readable
	case writable
}

public typealias UniSocketTimeout = (connect: UInt, read: UInt, write: UInt)

public class UniSocket {

	public let type: UniSocketType
	public var timeout: UniSocketTimeout
	private(set) var status: UniSocketStatus = .none
	private var fd: Int32 = -1
	private let peer: String
	private var peer_addrinfo: UnsafeMutablePointer<addrinfo>? = UnsafeMutablePointer<addrinfo>.allocate(capacity: 1)
	private var buffer: UnsafeMutablePointer<UInt8>
	private let bufferSize = 32768

	public init(type: UniSocketType, peer: String, port: Int32? = nil, timeout: UniSocketTimeout = (connect: 5, read: 5, write: 5)) throws {
		guard peer.count > 0 else {
			throw UniSocketError.error(detail: "invalid peer name")
		}
		self.type = type
		self.timeout = timeout
		self.peer = peer
		buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
		if type == .local {
			var peer_local = sockaddr_un()
			peer_local.sun_family = sa_family_t(PF_UNIX)
			_ = withUnsafeMutablePointer(to: &peer_local.sun_path.0) { ptr in
				_ = peer.withCString {
					strcpy(ptr, $0)
				}
			}
			peer_addrinfo!.pointee.ai_family = PF_LOCAL
			peer_addrinfo!.pointee.ai_socktype = Int32(SOCK_STREAM.rawValue)
			peer_addrinfo!.pointee.ai_protocol = 0
			_ = withUnsafeMutablePointer(to: &peer_local) { src in
				_ = withUnsafeMutablePointer(to: &peer_addrinfo!.pointee.ai_addr) { dst in
					memcpy(dst, src, MemoryLayout<sockaddr_un>.size)
				}
			}
			peer_addrinfo!.pointee.ai_addrlen = socklen_t(MemoryLayout<sockaddr_un>.size)
		} else {
			guard let p = port else {
				throw UniSocketError.error(detail: "missing port")
			}
			var rc: Int32
			var errstr: String = ""
			var hints = addrinfo(ai_flags: AI_PASSIVE, ai_family: PF_UNSPEC, ai_socktype: 0, ai_protocol: 0, ai_addrlen: 0, ai_addr: nil, ai_canonname: nil, ai_next: nil)
			switch type {
			case .tcp:
				hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
			case .udp:
				hints.ai_socktype = Int32(SOCK_DGRAM.rawValue)
			default:
				throw UniSocketError.error(detail: "unsupported socket type \(type)")
			}
			rc = getaddrinfo(peer, String(p), &hints, &peer_addrinfo)
			if rc != 0 {
				if rc == EAI_SYSTEM {
					errstr = String(validatingUTF8: strerror(errno)) ?? "unknown error code"
				} else {
					errstr = String(validatingUTF8: gai_strerror(errno)) ?? "unknown error code"
				}
				throw UniSocketError.error(detail: "failed to resolve '\(peer)', \(errstr)")
			}
		}
	}

	deinit {
		try? close()
		buffer.deallocate()
		peer_addrinfo?.deallocate()
	}

	public func attach() throws -> Void {
		guard status == .none else {
			throw UniSocketError.error(detail: "socket is \(status)")
		}
		var rc: Int32
		var errstr: String? = ""
		var ai = peer_addrinfo
		while ai != nil {
			fd = Glibc.socket(ai!.pointee.ai_family, ai!.pointee.ai_socktype, ai!.pointee.ai_protocol)
			if fd == -1 {
				ai = ai?.pointee.ai_next
				continue
			}
			let flags = fcntl(fd, F_GETFL)
			if flags != -1, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 {
				if type == .udp {
					status = .stateless
					return
				}
				rc = Glibc.connect(fd, ai!.pointee.ai_addr, ai!.pointee.ai_addrlen)
				if rc == 0 {
					break
				}
				if errno != EINPROGRESS {
					errstr = String(validatingUTF8: strerror(errno)) ?? "unknown error code"
				} else if let e = waitFor(.connected) {
					errstr = e
				} else {
					break
				}
			} else {
				errstr = String(validatingUTF8: strerror(errno)) ?? "unknown error code"
			}
			_ = Glibc.close(fd)
			fd = -1
			ai = ai?.pointee.ai_next
		}
		if fd == -1 {
			throw UniSocketError.error(detail: "failed to attach socket to '\(peer)' (\(errstr ?? ""))")
		}
		status = .connected
	}

	public func close() throws -> Void {
		if status == .connected {
			shutdown(fd, Int32(SHUT_RDWR))
			usleep(10000)
		}
		if fd != -1 {
			_ = Glibc.close(fd)
			fd = -1
		}
		status = .none
	}

	private func waitFor(_ status: UniSocketStatus, timeout: UInt? = nil) -> String? {
		var fds = fd_set()
		FD.ZERO(set: &fds)
		FD.SET(fd: fd, set: &fds)
		var rc: Int32
		var timer = timeval()
		if let t = timeout {
			timer.tv_sec = __time_t(t)
		}
		switch status {
		case .connected:
			if timeout == nil {
				timer.tv_sec = __time_t(self.timeout.connect)
			}
			rc = select(fd + 1, nil, &fds, nil, &timer)
		case .readable:
			if timeout == nil {
				timer.tv_sec = __time_t(self.timeout.read)
			}
			rc = select(fd + 1, &fds, nil, nil, &timer)
		case .writable:
			if timeout == nil {
				timer.tv_sec = __time_t(self.timeout.write)
			}
			rc = select(fd + 1, nil, &fds, nil, &timer)
		default:
			return nil
		}
		if rc > 0 {
			return nil
		} else if rc == 0 {
			var len = socklen_t(MemoryLayout<Int32>.size)
			getsockopt(fd, SOL_SOCKET, SO_ERROR, &rc, &len)
			if rc == 0 {
				rc = ETIMEDOUT
			}
		} else {
			rc = errno
		}
		return String(validatingUTF8: strerror(rc)) ?? "unknown error code"
	}

	public func recv(min: Int = 1, max: Int? = nil) throws -> Data {
		guard status == .connected || status == .stateless else {
			throw UniSocketError.error(detail: "socket is \(status)")
		}
		if let errstr = waitFor(.readable) {
			throw UniSocketError.error(detail: errstr)
		}
		var rc: Int = 0
		var data = Data(bytes: buffer, count: 0)
		while rc == 0 {
			var limit = bufferSize
			if let m = max, (m - data.count) < bufferSize {
				limit = m - data.count
			}
			rc = Glibc.recv(fd, buffer, limit, 0)
			if rc == 0 {
				try? close()
				throw UniSocketError.error(detail: "connection closed by remote host")
			} else if rc == -1 {
				let errstr = String(validatingUTF8: strerror(errno)) ?? "unknown error code"
				throw UniSocketError.error(detail: "failed to read from socket, \(errstr)")
			}
			data.append(buffer, count: rc)
			if let m = max, data.count >= m {
				break
			} else if max == nil, rc == bufferSize, waitFor(.readable, timeout: 0) == nil {
				rc = 0
			} else if data.count >= min {
				break
			}
		}
		return data
	}

	public func send(_ buffer: Data) throws -> Void {
		guard status == .connected || status == .stateless else {
			throw UniSocketError.error(detail: "socket is \(status)")
		}
		var bytesLeft = buffer.count
		var rc: Int
		while bytesLeft > 0 {
			let rangeLeft = Range(uncheckedBounds: (lower: buffer.index(buffer.startIndex, offsetBy: (buffer.count - bytesLeft)), upper: buffer.endIndex))
			let bufferLeft = buffer.subdata(in: rangeLeft)
			if let errstr = waitFor(.writable) {
				throw UniSocketError.error(detail: errstr)
			}
			if status == .stateless, let ai = peer_addrinfo {
				rc = bufferLeft.withUnsafeBytes { return Glibc.sendto(fd, $0, bytesLeft, 0, ai.pointee.ai_addr, ai.pointee.ai_addrlen) }
			} else {
				rc = bufferLeft.withUnsafeBytes { return Glibc.send(fd, $0, bytesLeft, 0) }
			}
			if rc == -1 {
				let errstr = String(validatingUTF8: strerror(errno)) ?? "unknown error code"
				throw UniSocketError.error(detail: "failed to write to socket, \(errstr)")
			}
			bytesLeft = bytesLeft - rc
		}
	}

	public func recvfrom() throws -> Data {

		throw UniSocketError.error(detail: "not yet implemented")

	}

}

// NOTE: Borrowed from https://github.com/IBM-Swift/BlueSocket.git
// Thanks to Bill Abt
// Copyright 2016 IBM. All rights reserved.

public struct FD {

	public static let maskBits = Int32(MemoryLayout<__fd_mask>.size * 8)

	/// Replacement for FD_ZERO macro

	public static func ZERO(set: inout fd_set) {
		set.__fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	}

	/// Replacement for FD_SET macro

	public static func SET(fd: Int32, set: inout fd_set) {
		let intOffset = Int(fd / maskBits)
		let bitOffset = Int(fd % maskBits)
		let mask: Int = 1 << bitOffset
		switch intOffset {
		case 0: set.__fds_bits.0 = set.__fds_bits.0 | mask
		case 1: set.__fds_bits.1 = set.__fds_bits.1 | mask
		case 2: set.__fds_bits.2 = set.__fds_bits.2 | mask
		case 3: set.__fds_bits.3 = set.__fds_bits.3 | mask
		case 4: set.__fds_bits.4 = set.__fds_bits.4 | mask
		case 5: set.__fds_bits.5 = set.__fds_bits.5 | mask
		case 6: set.__fds_bits.6 = set.__fds_bits.6 | mask
		case 7: set.__fds_bits.7 = set.__fds_bits.7 | mask
		case 8: set.__fds_bits.8 = set.__fds_bits.8 | mask
		case 9: set.__fds_bits.9 = set.__fds_bits.9 | mask
		case 10: set.__fds_bits.10 = set.__fds_bits.10 | mask
		case 11: set.__fds_bits.11 = set.__fds_bits.11 | mask
		case 12: set.__fds_bits.12 = set.__fds_bits.12 | mask
		case 13: set.__fds_bits.13 = set.__fds_bits.13 | mask
		case 14: set.__fds_bits.14 = set.__fds_bits.14 | mask
		case 15: set.__fds_bits.15 = set.__fds_bits.15 | mask
		default: break
		}
	}

	/// Replacement for FD_CLR macro

	public static func CLR(fd: Int32, set: inout fd_set) {
		let intOffset = Int(fd / maskBits)
		let bitOffset = Int(fd % maskBits)
		let mask: Int = ~(1 << bitOffset)
		switch intOffset {
		case 0: set.__fds_bits.0 = set.__fds_bits.0 & mask
		case 1: set.__fds_bits.1 = set.__fds_bits.1 & mask
		case 2: set.__fds_bits.2 = set.__fds_bits.2 & mask
		case 3: set.__fds_bits.3 = set.__fds_bits.3 & mask
		case 4: set.__fds_bits.4 = set.__fds_bits.4 & mask
		case 5: set.__fds_bits.5 = set.__fds_bits.5 & mask
		case 6: set.__fds_bits.6 = set.__fds_bits.6 & mask
		case 7: set.__fds_bits.7 = set.__fds_bits.7 & mask
		case 8: set.__fds_bits.8 = set.__fds_bits.8 & mask
		case 9: set.__fds_bits.9 = set.__fds_bits.9 & mask
		case 10: set.__fds_bits.10 = set.__fds_bits.10 & mask
		case 11: set.__fds_bits.11 = set.__fds_bits.11 & mask
		case 12: set.__fds_bits.12 = set.__fds_bits.12 & mask
		case 13: set.__fds_bits.13 = set.__fds_bits.13 & mask
		case 14: set.__fds_bits.14 = set.__fds_bits.14 & mask
		case 15: set.__fds_bits.15 = set.__fds_bits.15 & mask
		default: break
		}
	}

	/// Replacement for FD_ISSET macro

	public static func ISSET(fd: Int32, set: inout fd_set) -> Bool {
		let intOffset = Int(fd / maskBits)
		let bitOffset = Int(fd % maskBits)
		let mask: Int = 1 << bitOffset
		switch intOffset {
		case 0: return set.__fds_bits.0 & mask != 0
		case 1: return set.__fds_bits.1 & mask != 0
		case 2: return set.__fds_bits.2 & mask != 0
		case 3: return set.__fds_bits.3 & mask != 0
		case 4: return set.__fds_bits.4 & mask != 0
		case 5: return set.__fds_bits.5 & mask != 0
		case 6: return set.__fds_bits.6 & mask != 0
		case 7: return set.__fds_bits.7 & mask != 0
		case 8: return set.__fds_bits.8 & mask != 0
		case 9: return set.__fds_bits.9 & mask != 0
		case 10: return set.__fds_bits.10 & mask != 0
		case 11: return set.__fds_bits.11 & mask != 0
		case 12: return set.__fds_bits.12 & mask != 0
		case 13: return set.__fds_bits.13 & mask != 0
		case 14: return set.__fds_bits.14 & mask != 0
		case 15: return set.__fds_bits.15 & mask != 0
		default: return false
		}
	}

}
