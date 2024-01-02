//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Foundation)
private import Foundation
#endif

/// A protocol for customizing how arguments passed to parameterized tests are
/// encoded, which is used to match against when running specific arguments.
@_spi(ExperimentalParameterizedTesting)
public protocol CustomTestArgumentEncodable: Sendable {
  /// Encode this test argument.
  ///
  /// - Parameters:
  ///   - encoder: The encoder to write data to.
  ///
  /// - Throws: Any error encountered during encoding.
  ///
  /// The encoded form of a test argument should be stable and unique to allow
  /// re-running specific test cases of a parameterized test function. For
  /// optimal performance, large values which are not necessary to uniquely
  /// identify the test argument later should be omitted. Values encoded do not
  /// need to be human-readable.
  ///
  /// By default, the testing library checks whether a test argument conforms to
  /// `Encodable` and encodes it using `encodeTestArgument(to:)` if it does.
  /// This is sufficient for many types, but for some types the `Encodable`-
  /// provided representation may contain large data payloads that cause poor
  /// performance, are not stable and unique, or are otherwise deemed unsuitable
  /// for testing. If the type of the argument does not conform to `Encodable`
  /// but it does conform to `Identifiable` and its associated `ID` type
  /// conforms to `Encodable`, the value of calling its `id` property is used as
  /// the encoded representation.
  ///
  /// It is possible that neither of the approaches for encoded representation
  /// described above are sufficient. If the type of the argument is made to
  /// conform to ``CustomTestArgumentEncodable``, then the encoded
  /// representation formed by calling this method is used.
  func encodeTestArgument(to encoder: some Encoder) throws
}

extension Test.Case.Argument.ID {
  /// Initialize this instance with an ID for the specified test argument.
  ///
  /// - Parameters:
  ///   - value: The value of a test argument for which to get an ID.
  ///   - parameter: The parameter of the test function to which this argument
  ///     value was passed.
  ///
  /// - Returns: `nil` if an ID cannot be formed from the specified test
  ///   argument value.
  ///
  /// - Throws: Any error encountered while attempting to encode `value`.
  ///
  /// This function is not part of the public interface of the testing library.
  ///
  /// ## See Also
  ///
  /// - ``CustomTestArgumentEncodable``
  init?(identifying value: some Sendable, parameter: Test.ParameterInfo) throws {
#if canImport(Foundation)
    func customArgumentWrapper(for value: some CustomTestArgumentEncodable) -> some Encodable {
      _CustomArgumentWrapper(rawValue: value)
    }

    let encodableValue: (any Encodable)? = if let customEncodable = value as? any CustomTestArgumentEncodable {
      customArgumentWrapper(for: customEncodable)
    } else if let encodable = value as? any Encodable {
      encodable
    } else if let identifiable = value as? any Identifiable, let encodableID = identifiable.id as? any Encodable {
      encodableID
    } else {
      nil
    }

    guard let encodableValue else {
      return nil
    }

    self = .init(bytes: try Self._encode(encodableValue, parameter: parameter))
#else
    nil
#endif
  }

#if canImport(Foundation)
  /// Encode the specified test argument value and store its encoded
  /// representation as an array of bytes suitable for storing in an instance of
  /// ``Test/Case/Argument/ID-swift.struct``.
  ///
  /// - Parameters:
  ///   - value: The value to encode.
  ///   - parameter: The parameter of the test function to which this argument
  ///     value was passed.
  ///
  /// - Returns: An array of bytes containing the encoded representation.
  ///
  /// - Throws: Any error encountered during encoding.
  private static func _encode(_ value: some Encodable, parameter: Test.ParameterInfo) throws -> [UInt8] {
    let encoder = JSONEncoder()

    // Keys must be sorted to ensure deterministic matching of encoded data.
    encoder.outputFormatting.insert(.sortedKeys)

    // Set user info keys which clients may wish to use during encoding.
    encoder.userInfo[._testParameterUserInfoKey] = parameter

    return .init(try encoder.encode(value))
  }
#endif
}

/// A encodable type which wraps a ``CustomTestArgumentEncodable`` value.
private struct _CustomArgumentWrapper<T>: RawRepresentable, Encodable where T: CustomTestArgumentEncodable {
  /// The value this instance wraps, which implements custom test argument
  /// encoding logic.
  var rawValue: T

  init?(rawValue: T) {
    self.rawValue = rawValue
  }

  func encode(to encoder: any Encoder) throws {
    try rawValue.encodeTestArgument(to: encoder)
  }
}

// MARK: - Additional coding user info

extension CodingUserInfoKey {
  /// A coding user info key whose value is a ``Test/ParameterInfo``.
  fileprivate static var _testParameterUserInfoKey: Self {
    Self(rawValue: "org.swift.testing.coding-user-info-key.parameter")!
  }
}

extension Encoder {
  /// The test parameter which the test argument being encoded was passed to, if
  /// any.
  ///
  /// The value of this property is non-`nil` when this encoder is being used to
  /// encode an argument passed to a parameterized test function.
  @_spi(ExperimentalParameterizedTesting)
  public var testParameter: Test.ParameterInfo? {
    userInfo[._testParameterUserInfoKey] as? Test.ParameterInfo
  }
}
