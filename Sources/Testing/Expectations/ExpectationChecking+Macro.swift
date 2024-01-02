//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// - Parameters:
///   - condition: The condition to be evaluated.
///   - sourceCode: The source code of `condition`, if available at compile
///     time.
///   - expandedExpressionDescription: A description of the expression evaluated
///     by this expectation, expanded to include the values of any evaluated
///     sub-expressions, if the source code was available at compile time.
///   - difference: The difference between the operands in `condition`, if
///     available. Most callers should pass `nil`.
///   - comments: An array of comments describing the expectation. This array
///     may be empty.
///   - isRequired: Whether or not the expectation is required. The value of
///     this argument does not affect whether or not an error is thrown on
///     failure.
///   - sourceLocation: The source location of the expectation.
///
/// - Returns: A `Result<Void, any Error>`. If `condition` is `true`, the result
///   is `.success`. If `condition` is `false`, the result is an instance of
///   ``ExpectationFailedError`` describing the failure.
///
/// If the condition evaluates to `false`, an ``Issue`` is recorded for the test
/// that is running in the current task.
///
/// The odd error-handling convention in this function is necessary so that we
/// don't accidentally suppress errors thrown from subexpressions inside the
/// condition. For example, assuming there is a function
/// `func f() throws -> Bool`, the following calls should _not_ throw an
/// instance of ``ExpectationFailedError``, but should also not prevent an error
/// from being thrown by `f()`:
///
/// ```swift
/// try #expect(f))
/// #expect(try f())
/// ```
///
/// And the following call should generate a compile-time error:
///
/// ```swift
/// #expect(f()) // ERROR: Call can throw but is not marked with 'try'
/// ```
///
/// By _returning_ the error this function "throws", we can customize whether or
/// not we throw that error during macro resolution without affecting any errors
/// thrown by the condition expression passed to it.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkValue(
  _ condition: Bool,
  sourceCode: SourceCode,
  expandedExpressionDescription: @autoclosure () -> String? = nil,
  mismatchedErrorDescription: @autoclosure () -> String? = nil,
  difference: @autoclosure () -> String? = nil,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  // Post an event for the expectation regardless of whether or not it passed.
  // If the current event handler is not configured to handle events of this
  // kind, this event is discarded.
  var expectation = Expectation(sourceCode: sourceCode, isPassing: condition, isRequired: isRequired, sourceLocation: sourceLocation)
  Event.post(.expectationChecked(expectation))

  // Early exit if the expectation passed.
  if condition {
    return .success(())
  }

  // Since this expectation failed, populate its optional fields which are
  // only evaluated and included lazily upon failure.
  expectation.expandedExpressionDescription = expandedExpressionDescription()
  expectation.mismatchedErrorDescription = mismatchedErrorDescription()
  expectation.differenceDescription = difference()

  // Ensure the backtrace is captured here so it has fewer extraneous frames
  // from the testing framework which aren't relevant to the user.
  let backtrace = Backtrace.current()
  Issue.record(.expectationFailed(expectation), comments: comments(), backtrace: backtrace, sourceLocation: sourceLocation)
  return .failure(ExpectationFailedError(expectation: expectation))
}

// MARK: - Binary operators

/// Call a binary operator, passing the left-hand and right-hand arguments.
///
/// - Parameters:
///   - lhs: The left-hand argument to `op`.
///   - op: The binary operator to call.
///   - rhs: The right-hand argument to `op`. This closure may be invoked zero
///     or one time, but not twice or more.
///
/// - Returns: A tuple containing the result of calling `op` and the value of
///   `rhs` (or `nil` if it was not evaluated.)
///
/// - Throws: Whatever is thrown by `op`.
private func _callBinaryOperator<T, U, R>(
  _ lhs: T,
  _ op: (T, () -> U) -> R,
  _ rhs: () -> U
) -> (result: R, rhs: U?) {
  // The compiler normally doesn't allow a nonescaping closure to call another
  // nonescaping closure, but our use cases are safe (e.g. `true && false`) and
  // we cannot force one function or the other to be escaping. Use
  // withoutActuallyEscaping() to tell the compiler that what we're doing is
  // okay. SEE: https://github.com/apple/swift-evolution/blob/main/proposals/0176-enforce-exclusive-access-to-memory.md#restrictions-on-recursive-uses-of-non-escaping-closures
  var rhsValue: U?
  let result: R = withoutActuallyEscaping(rhs) { rhs in
    op(lhs, {
      if rhsValue == nil {
        rhsValue = rhs()
      }
      return rhsValue!
    })
  }
  return (result, rhsValue)
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used by binary operators such as `>`:
///
/// ```swift
/// #expect(2 > 1)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkBinaryOperation<T, U>(
  _ lhs: T, _ op: (T, () -> U) -> Bool, _ rhs: @autoclosure () -> U,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  let (condition, rhs) = _callBinaryOperator(lhs, op, rhs)
  return __checkValue(
    condition,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, rhs),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Function calls

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used by function calls:
///
/// ```swift
/// #expect(x.update(i))
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, each U>(
  _ lhs: T, calling functionCall: (T, repeat each U) throws -> Bool, _ arguments: repeat each U,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<Void, any Error> {
  let condition = try functionCall(lhs, repeat each arguments)
  return __checkValue(
    condition,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, repeat each arguments),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used by function calls where the arguments are all `inout`:
///
/// ```swift
/// #expect(x.update(&i))
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkInoutFunctionCall<T, /*each*/ U>(
  _ lhs: T, calling functionCall: (T, inout /*repeat each*/ U) throws -> Bool, _ arguments: inout /*repeat each*/ U,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<Void, any Error> {
  let condition = try functionCall(lhs, /*repeat each*/ &arguments)
  return __checkValue(
    condition,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, /*repeat each*/ arguments),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values produced from
/// expanded function calls:
///
/// ```swift
/// let z = try #require(x.update(i))
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkFunctionCall<T, each U, R>(
  _ lhs: T, calling functionCall: (T, repeat each U) throws -> R?, _ arguments: repeat each U,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<R, any Error> {
  let optionalValue = try functionCall(lhs, repeat each arguments)
  return __checkValue(
    optionalValue,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, repeat each arguments),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values produced from
/// expanded function calls where the arguments are all `inout`:
///
/// ```swift
/// let z = try #require(x.update(&i))
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkInoutFunctionCall<T, /*each*/ U, R>(
  _ lhs: T, calling functionCall: (T, inout /*repeat each*/ U) throws -> R?, _ arguments: inout /*repeat each*/ U,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) rethrows -> Result<R, any Error> {
  let optionalValue = try functionCall(lhs, /*repeat each*/ &arguments)
  return __checkValue(
    optionalValue,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, /*repeat each*/ arguments),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Property access

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used by property accesses:
///
/// ```swift
/// #expect(x.isFoodTruck)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkPropertyAccess<T>(
  _ lhs: T, getting memberAccess: (T) -> Bool,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  let condition = memberAccess(lhs)
  return __checkValue(
    condition,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, condition),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values produced from
/// expanded property accesses:
///
/// ```swift
/// let z = try #require(x.nearestFoodTruck)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkPropertyAccess<T, U>(
  _ lhs: T, getting memberAccess: (T) -> U?,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<U, any Error> {
  let optionalValue = memberAccess(lhs)
  return __checkValue(
    optionalValue,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, optionalValue),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Collection diffing

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to implement difference-reporting support when
/// comparing collections.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkBinaryOperation<T>(
  _ lhs: T, _ op: (T, () -> T) -> Bool, _ rhs: @autoclosure () -> T,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> where T: BidirectionalCollection, T.Element: Equatable {
  let (condition, rhs) = _callBinaryOperator(lhs, op, rhs)
  func difference() -> String? {
    guard let rhs else {
      return nil
    }
    let difference = lhs.difference(from: rhs)
    let insertions = difference.insertions.map(\.element)
    let removals = difference.removals.map(\.element)
    switch (!insertions.isEmpty, !removals.isEmpty) {
    case (true, true):
      return "inserted \(insertions), removed \(removals)"
    case (true, false):
      return "inserted \(insertions)"
    case (false, true):
      return "removed \(removals)"
    case (false, false):
      return ""
    }
  }

  return __checkValue(
    condition,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, rhs),
    difference: difference(),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is necessary because `String` satisfies the requirements for
/// the difference-calculating overload above, but the output from that overload
/// may be unexpectedly complex.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkBinaryOperation(
  _ lhs: String, _ op: (String, () -> String) -> Bool, _ rhs: @autoclosure () -> String,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  let (condition, rhs) = _callBinaryOperator(lhs, op, rhs)
  return __checkValue(
    condition,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, rhs),
    difference: nil,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used for `v is T` expressions.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkCast<V, T>(
  _ value: V,
  is _: T.Type,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  return __checkValue(
    value is T,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(value, type(of: value as Any)),
    difference: nil,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Optional unwrapping

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values:
///
/// ```swift
/// let x: Int? = ...
/// let y = try #require(x)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkValue<T>(
  _ optionalValue: T?,
  sourceCode: SourceCode,
  expandedExpressionDescription: @autoclosure () -> String? = nil,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<T, any Error> {
  __checkValue(
    optionalValue != nil,
    sourceCode: sourceCode,
    expandedExpressionDescription: expandedExpressionDescription(),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map {
    optionalValue.unsafelyUnwrapped
  }
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used to conditionally unwrap optional values using the `??`
/// operator:
///
/// ```swift
/// let x: Int? = ...
/// let y: Int? = ...
/// let z = try #require(x ?? y)
/// ```
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkBinaryOperation<T>(
  _ lhs: T?, _ op: (T?, () -> T?) -> T?, _ rhs: @autoclosure () -> T?,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<T, any Error> {
  let (optionalValue, rhs) = _callBinaryOperator(lhs, op, rhs)
  return __checkValue(
    optionalValue != nil,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(lhs, rhs),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  ).map {
    optionalValue.unsafelyUnwrapped
  }
}

/// Check that an expectation has passed after a condition has been evaluated
/// and throw an error if it failed.
///
/// This overload is used for `v as? T` expressions.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkCast<V, T>(
  _ value: V,
  as _: T.Type,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<T, any Error> {
  let optionalValue = value as? T
  return __checkValue(
    optionalValue,
    sourceCode: sourceCode,
    expandedExpressionDescription: sourceCode.expandWithOperands(value, type(of: value as Any)),
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Matching errors by type

/// Check that an expression always throws an error.
///
/// This overload is used for `#expect(throws:) { }` invocations that take error
/// types.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<E>(
  throws errorType: E.Type,
  performing expression: () throws -> some Any,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> where E: Error {
  if errorType == Never.self {
    __checkClosureCall(
      throws: Never.self,
      performing: expression,
      sourceCode: sourceCode,
      comments: comments(),
      isRequired: isRequired,
      sourceLocation: sourceLocation
    )
  } else {
    __checkClosureCall(
      performing: expression,
      throws: { $0 is E },
      mismatchExplanation: { "expected error of type \(errorType), but \(_description(of: $0)) was thrown instead" },
      sourceCode: sourceCode,
      comments: comments(),
      isRequired: isRequired,
      sourceLocation: sourceLocation
    )
  }
}

/// Check that an expression always throws an error.
///
/// This overload is used for `await #expect(throws:) { }` invocations that take
/// error types.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<E>(
  throws errorType: E.Type,
  performing expression: () async throws -> some Any,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) async -> Result<Void, any Error> where E: Error {
  if errorType == Never.self {
    await __checkClosureCall(
      throws: Never.self,
      performing: expression,
      sourceCode: sourceCode,
      comments: comments(),
      isRequired: isRequired,
      sourceLocation: sourceLocation
    )
  } else {
    await __checkClosureCall(
      performing: expression,
      throws: { $0 is E },
      mismatchExplanation: { "expected error of type \(errorType), but \(_description(of: $0)) was thrown instead" },
      sourceCode: sourceCode,
      comments: comments(),
      isRequired: isRequired,
      sourceLocation: sourceLocation
    )
  }
}

// MARK: - Matching Never.self

/// Check that an expression never throws an error.
///
/// This overload is used for `#expect(throws: Never.self) { }`. It cannot be
/// implemented directly in terms of the other overloads because it checks for
/// the _absence_ of an error rather than an error that matches some predicate.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall(
  throws _: Never.Type,
  performing expression: () throws -> some Any,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  var success = true
  var mismatchExplanationValue: String? = nil
  do {
    _ = try expression()
  } catch {
    success = false
    mismatchExplanationValue = "an error was thrown when none was expected: \(_description(of: error))"
  }

  return __checkValue(
    success,
    sourceCode: sourceCode,
    mismatchedErrorDescription: mismatchExplanationValue,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expression never throws an error.
///
/// This overload is used for `await #expect(throws: Never.self) { }`. It cannot
/// be implemented directly in terms of the other overloads because it checks
/// for the _absence_ of an error rather than an error that matches some
/// predicate.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall(
  throws _: Never.Type,
  performing expression: () async throws -> some Any,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) async -> Result<Void, any Error> {
  var success = true
  var mismatchExplanationValue: String? = nil
  do {
    _ = try await expression()
  } catch {
    success = false
    mismatchExplanationValue = "an error was thrown when none was expected: \(_description(of: error))"
  }

  return __checkValue(
    success,
    sourceCode: sourceCode,
    mismatchedErrorDescription: mismatchExplanationValue,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Matching instances of equatable errors

/// Check that an expression always throws an error.
///
/// This overload is used for `#expect(throws:) { }` invocations that take error
/// instances.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<E>(
  throws error: E,
  performing expression: () throws -> some Any,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> where E: Error & Equatable {
  __checkClosureCall(
    performing: expression,
    throws: { true == (($0 as? E) == error) },
    mismatchExplanation: { "expected error \(_description(of: error)), but \(_description(of: $0)) was thrown instead" },
    sourceCode: sourceCode,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expression always throws an error.
///
/// This overload is used for `await #expect(throws:) { }` invocations that take
/// error instances.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<E>(
  throws error: E,
  performing expression: () async throws -> some Any,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) async -> Result<Void, any Error> where E: Error & Equatable {
  await __checkClosureCall(
    performing: expression,
    throws: { true == (($0 as? E) == error) },
    mismatchExplanation: { "expected error \(_description(of: error)), but \(_description(of: $0)) was thrown instead" },
    sourceCode: sourceCode,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: - Arbitrary error matching

/// Check that an expression always throws an error.
///
/// This overload is used for `#expect { } throws: { }` invocations.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<R>(
  performing expression: () throws -> R,
  throws errorMatcher: (any Error) throws -> Bool,
  mismatchExplanation: ((any Error) -> String)? = nil,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) -> Result<Void, any Error> {
  var errorMatches = false
  var mismatchExplanationValue: String? = nil
  do {
    let result = try expression()

    var explanation = "an error was expected but none was thrown"
    if R.self != Void.self {
      explanation += " and \"\(result)\" was returned"
    }
    mismatchExplanationValue = explanation
  } catch {
    do {
      errorMatches = try errorMatcher(error)
      if !errorMatches {
        mismatchExplanationValue = mismatchExplanation?(error) ?? "unexpected error \(_description(of: error)) was thrown"
      }
    } catch let secondError {
      Issue.record(.errorCaught(secondError), comments: comments(), backtrace: .current(), sourceLocation: sourceLocation)
      mismatchExplanationValue = "a second error \(_description(of: secondError)) was thrown when checking error \(_description(of: error))"
    }
  }

  return __checkValue(
    errorMatches,
    sourceCode: sourceCode,
    mismatchedErrorDescription: mismatchExplanationValue,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

/// Check that an expression always throws an error.
///
/// This overload is used for `await #expect { } throws: { }` invocations.
///
/// - Warning: This function is used to implement the `#expect()` and
///   `#require()` macros. Do not call it directly.
public func __checkClosureCall<R>(
  performing expression: () async throws -> R,
  throws errorMatcher: (any Error) async throws -> Bool,
  mismatchExplanation: ((any Error) -> String)? = nil,
  sourceCode: SourceCode,
  comments: @autoclosure () -> [Comment],
  isRequired: Bool,
  sourceLocation: SourceLocation
) async -> Result<Void, any Error> {
  var errorMatches = false
  var mismatchExplanationValue: String? = nil
  do {
    let result = try await expression()

    var explanation = "an error was expected but none was thrown"
    if R.self != Void.self {
      explanation += " and \"\(result)\" was returned"
    }
    mismatchExplanationValue = explanation
  } catch {
    do {
      errorMatches = try await errorMatcher(error)
      if !errorMatches {
        mismatchExplanationValue = mismatchExplanation?(error) ?? "unexpected error \(_description(of: error)) was thrown"
      }
    } catch let secondError {
      Issue.record(.errorCaught(secondError), comments: comments(), backtrace: .current(), sourceLocation: sourceLocation)
      mismatchExplanationValue = "a second error \(_description(of: secondError)) was thrown when checking error \(_description(of: error))"
    }
  }

  return __checkValue(
    errorMatches,
    sourceCode: sourceCode,
    mismatchedErrorDescription: mismatchExplanationValue,
    comments: comments(),
    isRequired: isRequired,
    sourceLocation: sourceLocation
  )
}

// MARK: -

/// Generate a description of an error that includes its type name if not
/// already present.
///
/// - Parameters:
///   - error: The error to describe.
///
/// - Returns: A string equivalent to `String(describing: error)` with
///   information about its type added if not already present.
private func _description(of error: some Error) -> String {
  let errorDescription = "\"\(error)\""
  let errorType = type(of: error as Any)
  if #available(_regexAPI, *) {
    if errorDescription.contains(String(describing: errorType)) {
      return errorDescription
    }
  }
  return "\(errorDescription) of type \(errorType)"
}
