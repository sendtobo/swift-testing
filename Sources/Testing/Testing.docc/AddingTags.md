# Adding tags to tests

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Add tags to tests and customize their appearance.

## Overview

A complex package or project may contain hundreds or thousands of tests and
suites. Some subset of those tests may share some common facet, such as being
"critical" or "flaky". The testing library includes a type of trait called
"tags" that can be added to tests to group and categorize them.

Tags are different from test suites: test suites impose structure on test
functions at the source level, while tags provide semantic information for a
test that can be shared with any number of other tests across test suites,
source files, and even test targets.

## Adding tags

To add a tag to a test, use the ``Trait/tags(_:)-yg0i`` or
``Trait/tags(_:)-272p`` trait. These traits take sequences of tags as arguments,
and those tags are then applied to the corresponding test at runtime. If they
are applied to a test suite, then all tests in that suite inherit those tags.

Tags themselves are instances of ``Tag`` and can be expressed as string literals
or as named constants declared elsewhere:

```swift
extension Tag {
  static let legallyRequired = Tag(...)
}

@Test("Vendor's license is valid", .tags("critical", .legallyRequired))
func licenseValid() { ... }
```

The testing library does not assign any semantic meaning to any tags, nor does
the presence or absence of tags affect how the testing library runs tests.

## Customizing a tag's appearance

By default, a tag does not appear in a test's output when the test is run. It is
possible to assign colors to tags defined in a package so that when the test is
run, the tag is visible in its output.

To add colors to tags, create a directory in your home directory named
`".swift-testing"` and add a file named `"tag-colors.json"` to it. This file
should contain a JSON object (a dictionary) whose keys are strings representing
tags and whose values represent tag colors.

- Note: On Windows, create the `".swift-testing"` directory in the
  `"AppData\Local"` directory inside your home directory instead of directly
  inside it.

Tag colors can be represented using several formats:

- The strings `"red"`, `"orange"`, `"yellow"`, `"green"`, `"blue"`, or
  `"purple"`, representing corresponding predefined instances of ``Tag``, i.e.
  ``Tag/red``, ``Tag/orange``, ``Tag/yellow``, ``Tag/green``, ``Tag/blue``, and
  ``Tag/purple``;
- A string of the form `"#RRGGBB"`, containing a hexadecimal representation of
  the color in a device-independent RGB color space; or
- The `null` literal value, representing "no color."

For example, to set the color of the tag `"critical"` to orange and the color of
the tag `.legallyRequired` to teal, the contents of `"tag-colors.json"` can
be set to:

```json
{
  "critical": "red",
  ".legallyRequired": "#66FFCC"
}
```

- Note: Where possible, use the raw values of tags (from their ``Tag/rawValue``
  properties) as the keys in this object rather than using Swift source
  expressions like `".legallyRequired"` to ensure that tag colors are applied
  everywhere a tag is used.

## Topics

- ``Trait/tags(_:)-yg0i``
- ``Trait/tags(_:)-272p``
- ``Tag``
- ``Tag/List``
