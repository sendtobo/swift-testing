//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(ExperimentalTestRunning) @_spi(ExperimentalParameterizedTesting) @_spi(ExperimentalEventHandling) import Testing

@Suite("Test.Case.Argument Tests")
struct Test_Case_ArgumentTests {
  @Test("One parameter")
  func oneParameter() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let testCase = try #require(context.testCase)
      try #require(testCase.arguments.count == 1)

      let argument = testCase.arguments[0]
      #expect(argument.value as? String == "value")
      #expect(argument.parameter.index == 0)
      #expect(argument.parameter.firstName == "x")
    }

    await runTestFunction(named: "oneParameter(x:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("Two parameters")
  func twoParameters() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let testCase = try #require(context.testCase)
      try #require(testCase.arguments.count == 2)

      do {
        let argument = testCase.arguments[0]
        #expect(argument.value as? String == "value")
        #expect(argument.parameter.index == 0)
        #expect(argument.parameter.firstName == "x")
      }
      do {
        let argument = testCase.arguments[1]
        #expect(argument.value as? Int == 123)
        #expect(argument.parameter.index == 1)
        #expect(argument.parameter.firstName == "y")
      }
    }

    await runTestFunction(named: "twoParameters(x:y:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("One 1-tuple parameter")
  func one1TupleParameter() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let testCase = try #require(context.testCase)
      try #require(testCase.arguments.count == 1)

      let argument = testCase.arguments[0]
      #expect(argument.value as? (String) == ("value"))
      #expect(argument.parameter.index == 0)
      #expect(argument.parameter.firstName == "x")
    }

    await runTestFunction(named: "one1TupleParameter(x:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("One 2-tuple parameter")
  func one2TupleParameter() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let testCase = try #require(context.testCase)
      try #require(testCase.arguments.count == 1)

      let argument = testCase.arguments[0]
      let value = try #require(argument.value as? (String, Int))
      #expect(value.0 == "value")
      #expect(value.1 == 123)
      #expect(argument.parameter.index == 0)
      #expect(argument.parameter.firstName == "x")
    }

    await runTestFunction(named: "one2TupleParameter(x:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("Two Dictionary element (key, value) parameters")
  func DictionaryElementParameters() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let testCase = try #require(context.testCase)
      try #require(testCase.arguments.count == 2)

      do {
        let argument = testCase.arguments[0]
        #expect(argument.value as? String == "value")
        #expect(argument.parameter.index == 0)
        #expect(argument.parameter.firstName == "x")
      }
      do {
        let argument = testCase.arguments[1]
        #expect(argument.value as? Int == 123)
        #expect(argument.parameter.index == 1)
        #expect(argument.parameter.firstName == "y")
      }
    }

    await runTestFunction(named: "twoDictionaryElementParameters(x:y:)", in: ParameterizedTests.self, configuration: configuration)
  }

  @Test("One Dictionary element tuple (key, value) parameter")
  func oneDictionaryElementTupleParameter() async {
    var configuration = Configuration()
    configuration.setEventHandler { event, context in
      guard case .testCaseStarted = event.kind else {
        return
      }
      let testCase = try #require(context.testCase)
      try #require(testCase.arguments.count == 1)

      let argument = testCase.arguments[0]
      let value = try #require(argument.value as? (String, Int))
      #expect(value.0 == "value")
      #expect(value.1 == 123)
      #expect(argument.parameter.index == 0)
      #expect(argument.parameter.firstName == "x")
    }

    await runTestFunction(named: "oneDictionaryElementTupleParameter(x:)", in: ParameterizedTests.self, configuration: configuration)
  }
}

// MARK: - Fixture tests

private struct ParameterizedTests {
  @Test(arguments: ["value"])
  func oneParameter(x: String) {}

  @Test(arguments: ["value"], [123])
  func twoParameters(x: String, y: Int) {}

  @Test(arguments: [("value")])
  func one1TupleParameter(x: (String)) {}

  @Test(arguments: [("value", 123)])
  func one2TupleParameter(x: (String, Int)) {}

  @Test(arguments: ["value": 123])
  func twoDictionaryElementParameters(x: String, y: Int) {}

  @Test(arguments: ["value": 123])
  func oneDictionaryElementTupleParameter(x: (key: String, value: Int)) {}
}
