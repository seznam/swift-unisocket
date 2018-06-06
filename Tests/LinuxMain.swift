import XCTest

@testable import UniSocketTests

XCTMain([
	testCase(UniSocketTests.allTests),
	testCase(UniSocketIPv6Tests.allTests)
])
