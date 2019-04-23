![](https://img.shields.io/badge/Swift-4.2-orange.svg?style=flat)
![macOS](https://img.shields.io/badge/os-macOS-green.svg?style=flat)
![Linux](https://img.shields.io/badge/os-linux-green.svg?style=flat)
![Apache 2](https://img.shields.io/badge/license-Apache2-blue.svg?style=flat)
![Build Status](https://travis-ci.com/seznam/swift-unisocket.svg?branch=master)

# UniSocket

Let your swift application talk to others via TCP, UDP or unix sockets.

## Usage

Check if there is sshd running on the system:

```swift
import UniSocket

do {
	let socket = try UniSocket(type: .tcp, peer: "localhost", port: 22)
	try socket.attach()
	let data = try socket.recv()
	let string = String(data: data, encoding: .utf8)
	print("server responded with:")
	print(string)
	try socket.close()
} catch UniSocketError.error(let detail) {
	print(detail)
}
```

Send HTTP request and wait for response of a minimal required size:

```swift
import UniSocket

do {
	let socket = try UniSocket(type: .tcp, peer: "2a02:598:2::1053", port: 80)
	try socket.attach()
	let request = "HEAD / HTTP/1.0\r\n\r\n"
	let dataOut = request.data(using: .utf8)
	try socket.send(dataOut!)
	let dataIn = try socket.recv(min: 16)
	let string = String(data: dataIn, encoding: .utf8)
	print("server responded with:")
	print(string)
	try socket.close()
} catch UniSocketError.error(let detail) {
	print(detail)
}
```

Query DNS server over UDP using custom timeout values:

```swift
import UniSocket
import DNS // https://github.com/Bouke/DNS

do {
	let timeout: UniSocketTimeout = (connect: 2, read: 2, write: 1)
	let socket = try UniSocket(type: .udp, peer: "8.8.8.8", port: 53, timeout: timeout)
	try socket.attach() // NOTE: due to .udp, the call doesn't make a connection, just prepares socket and resolves hostname
	let request = Message(type: .query, recursionDesired: true, questions: [Question(name: "www.apple.com.", type: .host)])
	let requestData = try request.serialize()
	try socket.send(requestData)
	let responseData = try socket.recv()
	let response = try Message.init(deserialize: responseData)
	print("server responded with:")
	print(response)
	try socket.close()
} catch UniSocketError.error(let detail) {
	print(detail)
}
```

Check if local MySQL server is running:

```swift
import UniSocket

do {
	let socket = try UniSocket(type: .local, peer: "/tmp/mysql.sock")
	try socket.attach()
	let data = try socket.recv()
	print("server responded with:")
	print("\(data.map { String(format: "%c", $0) }.joined())")
	try socket.close()
} catch UniSocketError.error(let detail) {
	print(detail)
}
```

## Credits

Written by [Daniel Bilik](https://github.com/ddbilik/), copyright [Seznam.cz](https://onas.seznam.cz/en/), licensed under the terms of the Apache License 2.0.
