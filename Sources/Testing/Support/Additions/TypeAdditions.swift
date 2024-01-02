//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// Get the fully-qualified components of a type's name.
///
/// - Parameters:
///   - type: The type whose name components should be returned.
///
/// - Returns: The components of `type`'s fully-qualified name. For example, if
///   `type` is named `Example.MyClass`, the result is `["Example", "MyClass"]`.
func nameComponents(of type: Any.Type) -> [String] {
  _typeName(type, qualified: true)
    .split(separator: ".")
    .map(String.init)
}

/// Check if a type is a Swift `enum` type.
///
/// - Parameters:
///   - type: The type to check.
///
/// - Returns: Whether or not the type is a Swift `enum` type.
///
/// Per the [Swift mangling ABI](https://github.com/apple/swift/blob/main/docs/ABI/Mangling.rst),
/// enumeration types are mangled as `"O"`.
///
/// - Bug: We use the internal Swift standard library function
///   `_mangledTypeName()` to derive this information. We should use supported
///   API instead. ([swift-#69147](https://github.com/apple/swift/issues/69147))
@available(_mangledTypeNameAPI, *)
func isSwiftEnumeration(_ type: Any.Type) -> Bool {
  guard let mangledTypeName = _mangledTypeName(type), let lastCharacter = mangledTypeName.last else {
    return false
  }
  return lastCharacter == "O"
}

/// Check if a type is imported from C, C++, or Objective-C.
///
/// - Parameters:
///   - type: The type to check.
///
/// - Returns: Whether or not the type was imported from C, C++, or Objective-C.
///
/// Per the [Swift mangling ABI](https://github.com/apple/swift/blob/main/docs/ABI/Mangling.rst),
/// types imported from C-family languages are placed in a single flat `__C`
/// module. That module has a standardized mangling of `"So"`. The presence of
/// those characters at the start of a type's mangled name indicates that it is
/// an imported type.
///
/// - Bug: We use the internal Swift standard library function
///   `_mangledTypeName()` to derive this information. We should use supported
///   API instead. ([swift-#69146](https://github.com/apple/swift/issues/69146))
@available(_mangledTypeNameAPI, *)
func isImportedFromC(_ type: Any.Type) -> Bool {
  guard let mangledTypeName = _mangledTypeName(type), mangledTypeName.count > 2 else {
    return false
  }

  let endIndex = mangledTypeName.index(mangledTypeName.startIndex, offsetBy: 2)
  return mangledTypeName[..<endIndex] == "So"
}

/// Check if a class is a subclass (or equal to) another class.
///
/// - Parameters:
///   - subclass: The (possible) subclass to check.
///   - superclass The (possible) superclass to check.
///
/// - Returns: Whether `subclass` is a subclass of, or is equal to,
///   `superclass`.
func isClass(_ subclass: AnyClass, subclassOf superclass: AnyClass) -> Bool {
  if subclass == superclass {
    true
  } else if let subclassImmediateSuperclass = _getSuperclass(subclass) {
    isClass(subclassImmediateSuperclass, subclassOf: superclass)
  } else {
    false
  }
}

