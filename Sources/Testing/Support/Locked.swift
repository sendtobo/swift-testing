//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import TestingInternals

/// A property wrapper that wraps a value requiring access from a synchronous
/// caller during concurrent execution.
///
/// Instances of this type use a lock to synchronize access to their wrapped
/// values. The lock is not recursive.
///
/// Instances of this type can be used to synchronize access to shared data from
/// a synchronous caller. Wherever possible, use actor isolation or other Swift
/// concurrency tools.
///
/// This type is not part of the public interface of the testing library.
///
/// - Bug: The state protected by this type should instead be protected using
///     actor isolation, but actor-isolated functions cannot be called from
///     synchronous functions. ([83888717](rdar://83888717))
@propertyWrapper
struct Locked<T>: @unchecked Sendable where T: Sendable {
  /// The platform-specific type to use for locking.
  ///
  /// It would be preferable to implement this lock in Swift, however there is
  /// no standard lock or mutex type available across all platforms that is
  /// visible in Swift. C11 has a standard `mtx_t` type, but it is not widely
  /// supported and so cannot be relied upon.
  ///
  /// To keep the implementation of this type as simple as possible,
  /// `pthread_mutex_t` is used on Apple platforms instead of `os_unfair_lock`
  /// or `OSAllocatedUnfairLock`.
#if SWT_TARGET_OS_APPLE || os(Linux)
  private typealias _Lock = pthread_mutex_t
#elseif os(Windows)
  private typealias _Lock = SRWLOCK
#else
#warning("Platform-specific implementation missing: locking unavailable")
  private typealias _Lock = Void
#endif

  /// A type providing heap-allocated storage for an instance of ``Locked``.
  private final class _Storage: ManagedBuffer<T, _Lock> {
    deinit {
      withUnsafeMutablePointerToElements { lock in
#if SWT_TARGET_OS_APPLE || os(Linux)
        _ = pthread_mutex_destroy(lock)
#elseif os(Windows)
        // No deinitialization needed.
#else
#warning("Platform-specific implementation missing: locking unavailable")
#endif
      }
    }
  }

  /// Storage for the underlying lock and wrapped value.
  private var _storage: ManagedBuffer<T, _Lock>

  init(wrappedValue: T) {
    _storage = _Storage.create(minimumCapacity: 1, makingHeaderWith: { _ in wrappedValue })
    _storage.withUnsafeMutablePointerToElements { lock in
#if SWT_TARGET_OS_APPLE || os(Linux)
      _ = pthread_mutex_init(lock, nil)
#elseif os(Windows)
      InitializeSRWLock(lock)
#else
#warning("Platform-specific implementation missing: locking unavailable")
#endif
    }
  }

  var wrappedValue: T {
    withLock { $0 }
  }

  var projectedValue: Locked {
    self
  }

  /// Acquire the lock and invoke a function while it is held.
  ///
  /// - Parameters:
  ///   - body: A closure to invoke while the lock is held.
  ///
  /// - Returns: Whatever is returned by `body`.
  ///
  /// - Throws: Whatever is thrown by `body`.
  ///
  /// This function can be used to synchronize access to shared data from a
  /// synchronous caller. Wherever possible, use actor isolation or other Swift
  /// concurrency tools.
  nonmutating func withLock<R>(_ body: (inout T) throws -> R) rethrows -> R {
    try _storage.withUnsafeMutablePointers { wrappedValue, lock in
#if SWT_TARGET_OS_APPLE || os(Linux)
      _ = pthread_mutex_lock(lock)
      defer {
        _ = pthread_mutex_unlock(lock)
      }
#elseif os(Windows)
      AcquireSRWLockExclusive(lock)
      defer {
        ReleaseSRWLockExclusive(lock)
      }
#else
#warning("Platform-specific implementation missing: locking unavailable")
#endif

      return try body(&wrappedValue.pointee)
    }
  }
}

extension Locked where T: AdditiveArithmetic {
  /// Add something to the current wrapped value of this instance.
  ///
  /// - Parameters:
  ///   - addend: The value to add.
  ///
  /// - Returns: The sum of ``wrappedValue`` and `addend`.
  @discardableResult func add(_ addend: T) -> T {
    withLock { wrappedValue in
      let result = wrappedValue + addend
      wrappedValue = result
      return result
    }
  }
}

extension Locked where T: Numeric {
  /// Increment the current wrapped value of this instance.
  ///
  /// - Returns: The sum of ``wrappedValue`` and `1`.
  ///
  /// This function is exactly equivalent to `add(1)`.
  @discardableResult func increment() -> T {
    add(1)
  }
}
