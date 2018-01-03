// swift-tools-version:4.0

import PackageDescription

let package = Package(
		name: "UniSocket",
		products: [
			.library(name: "UniSocket", targets: ["UniSocket"])
		],
		targets: [
			.target(name: "UniSocket")
		]
)
