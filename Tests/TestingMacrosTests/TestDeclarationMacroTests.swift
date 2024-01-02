//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import Testing
@testable import TestingMacros

import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@Suite("TestDeclarationMacro Tests")
struct TestDeclarationMacroTests {
  @Test("Error diagnostics emitted on API misuse",
    arguments: [
      // Generic declarations
      "@Suite struct S<T> {}":
        "The @Suite attribute cannot be applied to a generic structure.",
      "@Suite struct S where X == Y {}":
        "The @Suite attribute cannot be applied to a generic structure.",
      "@Test func f<T>() {}":
        "The @Test attribute cannot be applied to a generic function.",
      "@Test func f() where X == Y {}":
        "The @Test attribute cannot be applied to a generic function.",
      "@Test(arguments: []) func f(x: some T) {}":
        "The @Test attribute cannot be applied to a generic function.",
      "@Test(arguments: []) func f(x: (some T)?) {}":
        "The @Test attribute cannot be applied to a generic function.",

      // Multiple attributes on a declaration
      "@Suite @Suite struct S {}":
        "The @Suite attribute cannot be applied to a structure more than once.",
      "@Suite @Suite final class C {}":
        "The @Suite attribute cannot be applied to a class more than once.",
      "@Test @Test func f() {}":
        "The @Test attribute cannot be applied to a function more than once.",

      // Attributes on unsupported declarations
      "@Test var x = 0":
        "The @Test attribute cannot be applied to a property.",
      "@Test init() {}":
        "The @Test attribute cannot be applied to an initializer.",
      "@Test deinit {}":
        "The @Test attribute cannot be applied to a deinitializer.",
      "@Test subscript() -> Int {}":
        "The @Test attribute cannot be applied to a subscript.",
      "@Test typealias X = Y":
        "The @Test attribute cannot be applied to a typealias.",
      "enum E { @Test case c }":
        "The @Test attribute cannot be applied to an enumeration case.",
      "@Suite func f() {}":
        "The @Suite attribute cannot be applied to a function.",
      "@Suite extension X {}":
        "The @Suite attribute has no effect when applied to an extension and should be removed.",
      "@Test macro m()":
        "The @Test attribute cannot be applied to a macro.",
      "@Test struct S {}":
        "The @Test attribute cannot be applied to a structure.",
      "@Test enum E {}":
        "The @Test attribute cannot be applied to an enumeration.",


      // Availability
      "@available(*, unavailable) @Suite struct S {}":
        "The @Suite attribute cannot be applied to this structure because it has been marked @available(*, unavailable).",
      "@available(*, noasync) @Suite enum E {}":
        "The @Suite attribute cannot be applied to this enumeration because it has been marked @available(*, noasync).",
      "@available(macOS 999.0, *) @Suite final class C {}":
        "The @Suite attribute cannot be applied to this class because it has been marked @available(macOS 999.0, *).",
      "@_unavailableFromAsync @Suite actor A {}":
        "The @Suite attribute cannot be applied to this actor because it has been marked @_unavailableFromAsync.",

      // XCTestCase
      "@Suite final class C: XCTestCase {}":
        "The @Suite attribute cannot be applied to a subclass of XCTestCase.",
      "@Suite final class C: XCTest.XCTestCase {}":
        "The @Suite attribute cannot be applied to a subclass of XCTestCase.",

      // Unsupported inheritance
      "@Suite class C {}":
        "The @Suite attribute cannot be applied to non-final class C.",
      "@Suite protocol P {}":
        "The @Suite attribute cannot be applied to a protocol.",

      // Invalid specifiers on arguments
      "@Test(arguments: [0]) func f(i: inout Int) {}":
        "The @Test attribute cannot be applied to a function with a parameter marked 'inout'.",
      "@Test(arguments: [MyActor()]) func f(i: isolated MyActor) {}":
        "The @Test attribute cannot be applied to a function with a parameter marked 'isolated'.",
      "@Test(arguments: [0.0]) func f(i: _const Double) {}":
        "The @Test attribute cannot be applied to a function with a parameter marked '_const'.",

      // Argument count mismatches.
      "@Test func f(i: Int) {}":
        "The @Test attribute must specify an argument when used with f(i:).",
      "@Test func f(i: Int, j: Int) {}":
        "The @Test attribute must specify 2 arguments when used with f(i:j:).",
      "@Test(arguments: []) func f() {}":
        "The @Test attribute cannot specify arguments when used with f() because it does not take any.",
    ]
  )
  func apiMisuseErrors(input: String, expectedMessage: String) throws {
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.count > 0)
    for diagnostic in diagnostics {
      #expect(diagnostic.diagMessage.severity == .error)
      #expect(diagnostic.message == expectedMessage)
    }
  }

  @Test("Warning diagnostics emitted on API misuse",
    arguments: [
      // return types
      "@Test func f() -> Int {}":
        "The result of this function will be discarded during testing.",
      "@Test func f() -> Swift.String {}":
        "The result of this function will be discarded during testing.",
      "@Test func f() -> Int? {}":
        "The result of this function will be discarded during testing.",
      "@Test func f() -> (Int, Int) {}":
        "The result of this function will be discarded during testing.",
    ]
  )
  func apiMisuseWarnings(input: String, expectedMessage: String) throws {
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.count > 0)
    for diagnostic in diagnostics {
      #expect(diagnostic.diagMessage.severity == .warning)
      #expect(diagnostic.message == expectedMessage)
    }
  }

  @Test("Availability attributes are captured",
    arguments: [
      #"@available(moofOS 9, dogCow 30, *) @Test func f() {}"#:
        [
          #".__available("moofOS", introduced: (9, nil, nil), "#,
          #".__available("dogCow", introduced: (30, nil, nil), "#,
          #"guard #available (moofOS 9, *), #available (dogCow 30, *) else"#,
        ],
      #"@available(moofOS, introduced: 9) @available(dogCow, introduced: 30) @Test func f() {}"#:
        [
          #".__available("moofOS", introduced: (9, nil, nil), "#,
          #".__available("dogCow", introduced: (30, nil, nil), "#,
          #"guard #available (moofOS 9, *), #available (dogCow 30, *) else"#,
        ],
      #"@available(*, unavailable, message: "Clarus!") @Test func f() {}"#:
        [#".__unavailable(message: "Clarus!", "#],
      #"@available(moofOS, obsoleted: 9) @Test func f() {}"#:
        [#".__available("moofOS", obsoleted: (9, nil, nil), "#],
      #"@available(swift 1.0) @Test func f() {}"#:
        [
          #".__available("Swift", introduced: (1, 0, nil), "#,
          #"#if swift(>=1.0)"#,
        ],
      #"@available(swift, introduced: 1.0) @Test func f() {}"#:
        [
          #".__available("Swift", introduced: (1, 0, nil), "#,
          #"#if swift(>=1.0)"#,
        ],
      #"@available(swift, obsoleted: 2.0) @Test func f() {}"#:
        [
          #".__available("Swift", obsoleted: (2, 0, nil), "#,
          #"#if swift(<2.0)"#,
        ],
      #"@available(swift, introduced: 1.0, obsoleted: 2.0) @Test func f() {}"#:
        [
          #".__available("Swift", introduced: (1, 0, nil), "#,
          #".__available("Swift", obsoleted: (2, 0, nil), "#,
          #"#if swift(>=1.0) && swift(<2.0)"#,
        ],
    ]
  )
  func availabilityAttributeCapture(input: String, expectedOutputs: [String]) throws {
    let (actualOutput, _) = try parse(input)

    for expectedOutput in expectedOutputs {
      #expect(actualOutput.contains(expectedOutput))
    }
  }

  @Test("Different kinds of functions are handled correctly",
    arguments: [
      ("@Test func f() {}", nil, nil),
      ("struct S {\n\t@Test func f() {} }", "Self", "let"),
      ("struct S {\n\t@Test mutating func f() {} }", "Self", "var"),
      ("struct S {\n\t@Test static func f() {} }", "Self", nil),
      ("final class S {\n\t@Test class func f() {} }", "Self", nil),
      ("@Test @available(*, noasync) @MainActor func f() {}", nil, "MainActor.run"),
      ("@Test @_unavailableFromAsync @MainActor func f() {}", nil, "MainActor.run"),
      ("@Test @available(*, noasync) func f() {}", nil, "__requiringTry"),
      ("@Test @_unavailableFromAsync func f() {}", nil, "__requiringTry"),
      ("@Test(arguments: []) func f(i: borrowing Int) {}", nil, "copy"),
      ("@Test(arguments: []) func f(_ i: borrowing Int) {}", nil, "copy"),
      ("struct S {\n\t@Test func testF() {} }", nil, "__invokeXCTestCaseMethod"),
      ("struct S {\n\t@Test func testF() throws {} }", nil, "__invokeXCTestCaseMethod"),
      ("struct S {\n\t@Test func testF() async {} }", nil, "__invokeXCTestCaseMethod"),
      ("struct S {\n\t@Test func testF() async throws {} }", nil, "__invokeXCTestCaseMethod"),
      (
        """
        struct S {
          #if SOME_CONDITION
          @OtherAttribute
          #endif
          @Test func testF() async throws {}
        }
        """,
        nil,
        nil
      ),
    ]
  )
  func differentFunctionTypes(input: String, expectedTypeName: String?, otherCode: String?) throws {
    let (output, _) = try parse(input)

    #expect(output.contains("__TestContainer"))
    if let expectedTypeName {
      #expect(output.contains(expectedTypeName))
    }
    if let otherCode {
      #expect(output.contains(otherCode))
    }
  }

  @Test("Self. in @Test attribute is removed")
  func removeSelfKeyword() throws {
    let (output, _) = try parse("@Test(arguments: Self.nested.uniqueArgsName, NoTouching.thisOne) func f() {}")
    #expect(output.contains("nested.uniqueArgsName"))
    #expect(!output.contains("Self.nested.uniqueArgsName"))
    #expect(output.contains("NoTouching.thisOne"))
  }

  @Test("Display name is preserved",
    arguments: [
      #"@Test("Display Name") func f() {}"#,
      #"@Test("Display Name", .someTrait) func f() {}"#,
      #"@Test("Display Name", .someTrait, arguments: []) func f(i: Int) {}"#,
      #"@Test("Display Name", arguments: []) func f(i: Int) {}"#,
    ]
  )
  func preservesDisplayName(input: String) throws {
    let (output, _) = try parse(input)
    #expect(output.contains(": \"Display Name\""))
  }

  @Test("Nil display name")
  func nilDisplayName() throws {
    let input = #"@Test(nil, .someTrait) func f() {}"#
    let (output, _) = try parse(input)
    #expect(!output.contains("displayName:"))
  }

  @Test("Discovers and rewrites tag traits")
  func rewritesTagTraits() throws {
    let (output, _) = try parse("@Test(.tags(\"1\", .x), .tags([\"ABC\"]), .unrelated) func f() {}")
    #expect(output.contains("\"1\""))
    #expect(!output.contains("Testing.Tag.__tag(\"1\", sourceCode: "))
    #expect(output.contains("Testing.Tag.__tag(.x, sourceCode: .__fromSyntaxNode(\".x\"))"))
    #expect(output.contains("\"ABC\""))
    #expect(!output.contains("Testing.Tag.__tag(\"ABC\", sourceCode: "))
    #expect(output.contains(".unrelated"))
  }
}
