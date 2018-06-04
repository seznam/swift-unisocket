// swift-tools-version:4.0

import PackageDescription

let package = Package(
	name: "UniSocket",
	products: [
		.library(name: "UniSocket", targets: ["UniSocket"])
	],
	dependencies: [
		.package(url: "https://github.com/Bouke/DNS.git", from: "1.0.0")
	],
	targets: [
		.target(name: "UniSocket"),
		.testTarget(name: "UniSocketTests", dependencies: ["UniSocket", "DNS"])
	]
)
