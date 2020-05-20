import XCTest

@testable import UniSocket
import DNS

class UniSocketTests: XCTestCase {

	static var allTests = [
		("testTCP", testTCP),
		("testTCP4", testTCP4),
		("testTCPTimeout", testTCPTimeout),
		("testTCPRefused", testTCPRefused),
		("testTCPNotFound", testTCPNotFound),
		("testUDP", testUDP),
		("testUDP4", testUDP4),
		("testUDPTimeout", testUDPTimeout),
		("testUnixRefused", testUnixRefused),
		("testUnixNotFound", testUnixNotFound),
	]

	func testTCP() {
		var response: String? = nil
		do {
			let socket = try UniSocket(type: .tcp, peer: "www.seznam.cz", port: 80)
			try socket.attach()
			let request = "HEAD / HTTP/1.0\r\n\r\n"
			let dataOut = request.data(using: .utf8)
			try socket.send(dataOut!)
			let dataIn = try socket.recv(min: 16)
			response = String(data: dataIn, encoding: .utf8)
			try socket.close()
		} catch UniSocketError.error(let detail) {
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && response!.hasPrefix("HTTP/1"))
	}

	func testTCP4() {
		var response: String? = nil
		do {
			let socket = try UniSocket(type: .tcp, peer: "77.75.76.46", port: 110)
			try socket.attach()
			let dataIn = try socket.recv(min: 4)
			response = String(data: dataIn, encoding: .utf8)
			let request = "QUIT\r\n"
			let dataOut = request.data(using: .utf8)
			try socket.send(dataOut!)
			try socket.close()
		} catch UniSocketError.error(let detail) {
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && response!.hasPrefix("+OK "))
	}

	func testTCPTimeout() {
		var response: String? = nil
		let t: UInt = 2
		let timeout: UniSocketTimeout = (connect: t, read: t, write: t)
		let from = Date().timeIntervalSince1970
		do {
			let socket = try UniSocket(type: .tcp, peer: "4.4.4.4", port: 23, timeout: timeout)
			try socket.attach()
			let dataIn = try socket.recv()
			response = String(data: dataIn, encoding: .utf8)
			try socket.close()
		} catch UniSocketError.error(let detail) {
			print(detail)
		} catch {
			print(error)
		}
		let to = Date().timeIntervalSince1970
		let duration = to - from
		XCTAssert(response == nil && duration >= Double(t) && duration < Double(t + 1))
	}

	func testTCPRefused() {
		var response: String? = nil
		do {
			let socket = try UniSocket(type: .tcp, peer: "localhost", port: 54321)
			try socket.attach()
			_ = try socket.recv()
			try socket.close()
		} catch UniSocketError.error(let detail) {
			response = detail
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && response!.contains("refused"))
	}

	func testTCPNotFound() {
		var response: String? = nil
		do {
			let socket = try UniSocket(type: .tcp, peer: "no.such.host.seznam.cz", port: 22)
			try socket.attach()
			try socket.close()
		} catch UniSocketError.error(let detail) {
			response = detail
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && response!.hasPrefix("failed to resolve"))
	}

	func testUDP() {
		var response: Message? = nil
		do {
			let socket = try UniSocket(type: .udp, peer: "ans.seznam.cz", port: 53)
			try socket.attach()
			let request = Message(type: .query, questions: [Question(name: "www.seznam.cz.", type: .host)])
			let requestData = try request.serialize()
			try socket.send(requestData)
			let responseData = try socket.recv(min: 25)
			response = try Message.init(deserialize: responseData)
			try socket.close()
		} catch UniSocketError.error(let detail) {
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && response!.answers.count > 0)
	}

	func testUDP4() {
		var response: Message? = nil
		do {
			let socket = try UniSocket(type: .udp, peer: "77.75.74.80", port: 53)
			try socket.attach()
			let request = Message(type: .query, questions: [Question(name: "seznam.cz.", type: .nameServer)])
			let requestData = try request.serialize()
			try socket.send(requestData)
			let responseData = try socket.recv(min: 25)
			response = try Message.init(deserialize: responseData)
			try socket.close()
		} catch UniSocketError.error(let detail) {
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && response!.answers.count > 0)
	}

	func testUDPTimeout() {
		let t: UInt = 2
		let timeout: UniSocketTimeout = (connect: t, read: t, write: t)
		var response: Data? = nil
		let from = Date().timeIntervalSince1970
		do {
			let socket = try UniSocket(type: .udp, peer: "localhost", port: 54321, timeout: timeout)
			try socket.attach()
			response = try socket.recv(min: 25)
			try socket.close()
		} catch UniSocketError.error(let detail) {
			print(detail)
		} catch {
			print(error)
		}
		let to = Date().timeIntervalSince1970
		let duration = to - from
		XCTAssert(response == nil && duration >= Double(t) && duration < Double(t + 1))
	}

	func testUnixRefused() {
		var response: String? = nil
		do {
			let socket = try UniSocket(type: .local, peer: "Package.swift")
			try socket.attach()
			try socket.close()
		} catch UniSocketError.error(let detail) {
			response = detail
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && (response!.contains("refused") || (response!.contains("non-socket"))))
	}

	func testUnixNotFound() {
		var response: String? = nil
		do {
			let socket = try UniSocket(type: .local, peer: "/tmp/no/such/socket")
			try socket.attach()
			try socket.close()
		} catch UniSocketError.error(let detail) {
			response = detail
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && response!.contains("No such file"))
	}

}

class UniSocketIPv6Tests: XCTestCase {

	static var allTests = [
		("testTCP6", testTCP6),
		("testUDP6", testUDP6),
	]

	func testTCP6() {
		var response: String? = nil
		do {
			let socket = try UniSocket(type: .tcp, peer: "2a02:598:2::1053", port: 80)
			try socket.attach()
			let request = "HEAD / HTTP/1.0\r\n\r\n"
			let dataOut = request.data(using: .utf8)
			try socket.send(dataOut!)
			let dataIn = try socket.recv(min: 16)
			response = String(data: dataIn, encoding: .utf8)
			try socket.close()
		} catch UniSocketError.error(let detail) {
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && response!.hasPrefix("HTTP/1"))
	}

	func testUDP6() {
		var response: Message? = nil
		do {
			let socket = try UniSocket(type: .udp, peer: "2a02:598:3333::3", port: 53)
			try socket.attach()
			let request = Message(type: .query, questions: [Question(name: "seznam.cz.", type: .mailExchange)])
			let requestData = try request.serialize()
			try socket.send(requestData)
			let responseData = try socket.recv(min: 25)
			response = try Message.init(deserialize: responseData)
			try socket.close()
		} catch UniSocketError.error(let detail) {
			print(detail)
		} catch {
			print(error)
		}
		XCTAssert(response != nil && response!.answers.count > 0)
	}

}
