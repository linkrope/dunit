# xUnit Testing Framework for D

[![Build Status](https://travis-ci.org/linkrope/dunit.svg?branch=master)](https://travis-ci.org/linkrope/dunit)

This is a simple implementation of the xUnit Testing Framework
for the [D Programming Language].
Being based on [JUnit] it allows to organize tests
according to the [xUnit Test Patterns].

Looking for a replacement of [DUnit] for D1, I found [jmcabo/dunit] promising.
First, I had to fix some issues, but by now the original implementation
has been largely revised.

## Testing Functions vs. Interactions

D's built-in support for unittests is best suited for testing functions,
when the test cases can be expressed as one-liners.
(Have a look at the documented unittests for the [`dunit.assertion`] functions.)

But you're on your own, when you have to write a lot more code per test case,
for example for testing interactions of objects.

So, here is what the xUnit Testing Framework has to offer:

- tests are organized in classes
- tests are always named
- tests can reuse a shared fixture
- you see the progress as the tests are run
- you see all failed tests at once
- you get more information about failures

## Failures vs. Errors

Specialized assertion functions provide more information about failures than
the built-in `assert` expression.

For example,

    assertEquals("bar", "baz");

will not only report the faulty value but will also highlight the difference:

    expected: <ba<r>> but was: <ba<z>>

The more general

    assertOp!">="(a, b);  // alias assertGreaterThanOrEqual

(borrowed from [Issue 4653])
will at least report the concrete values in case of a failure:

    condition (2 >= 3) not satisfied

Together with the expressive name of the test (that's your responsibility)
this should be enough information for failures. On the other hand, for
violated contracts and other exceptions from deep down the unit under test
you may wish for the stack trace.

That's why the xUnit Testing Framework distinguishes failures from errors,
and why [`dunit.assertion`] doesn't use `AssertError`
but introduces its own `AssertException`.

## User Defined Attributes

Thanks to D's User Defined Attributes, test names no longer have to start with
"test".

Put `mixin UnitTest;` in your test class and attach `@Test`,
`@BeforeEach`, `@AfterEach`, `@BeforeAll`, `@AfterAll`,
`@Tag("...")`, `@Disabled("...")`,
`@DisabledIf(() => ..., "...")`, `@EnabledIf(() => ..., "...")`,
`@DisabledIfEnvironmentVariable("VARIABLE", "pattern")`,
`@EnabledIfEnvironmentVariable("VARIABLE", "pattern")`,
`@DisabledOnOs(OS.win32, OS.win64)`, `@EnabledOnOs(OS.linux)`
(borrowed from [JUnit 5]) to the member functions to state their purpose.

## Test Results

Test results are reported while the tests are run. A "progress bar" is written
with a `.` for each passed test, an `F` for each failure, an `E` for each error,
and an `S` for each skipped test.

In addition, an XML test report is available that uses the _JUnitReport_ format.
The continuous integration tool [Jenkins], for example,
understands this _JUnitReport_ format. Thus, Jenkins can be used to browse
test reports, track failures and errors, and even provide trends over time.

## Examples

Run the included [example] to see the xUnit Testing Framework in action:

    ./example.d

(When you get four failures, one error, and six skips, everything works fine.)

Have a look at the debug output of the example in "verbose" style:

    rdmd -debug -Isrc example.d --verbose

Or just focus on the issues:

    ./example.d --filter Test.assert --filter error

## "Next Generation"

JUnit's `assertEquals(expected, actual)` got changed into
TestNG's `assertEquals(actual, expected)`, which feels more natural.
Moreover, the reversed order of arguments is more convenient for
D's Uniform Function Call Syntax: `answer.assertEquals(42)`.
The only effect, however, is on the failure messages,
which will be confusing if the order is mixed up.

So, if you prefer TestNG's order of arguments,
import `dunit.ng` or `dunit.ng.assertion`
instead of the conventional `dunit` and `dunit.assertion`.

## Fluent Assertions

The xUnit Testing Framework also supports the "fluent assertions" from [dshould].

For an example, have a look at [fluent-assertions].
Build and run the example using

    ./fluent_assertions.d

(When you get three failures, everything works fine.)

## Related Projects

- [DMocks-revived]:
  a mock-object framework that allows to mock interfaces or classes
- [specd]:
  a unit testing framework inspired by [specs2] and [ScalaTest]
- [DUnit]:
  a toolkit of test assertions and a template mixin to enable mocking
- [unit-threaded]:
  a multi-threaded unit testing framework

[d programming language]: http://dlang.org
[dunit]: http://www.dsource.org/projects/dmocks/wiki/DUnit
[issue 4653]: http://d.puremagic.com/issues/show_bug.cgi?id=4653
[jenkins]: http://jenkins-ci.org
[junit]: http://junit.org
[junit 5]: http://junit.org/junit5/docs/current/user-guide/
[scalatest]: http://www.scalatest.org
[specs2]: http://etorreborre.github.io/specs2/
[xunit test patterns]: http://xunitpatterns.com

[dmocks-revived]: https://github.com/QAston/DMocks-revived
[dshould]: https://github.com/funkwerk/dshould
[jmcabo/dunit]: https://github.com/jmcabo/dunit
[dunit]: https://github.com/kalekold/dunit
[specd]: https://github.com/jostly/specd
[unit-threaded]: https://github.com/atilaneves/unit-threaded

[`dunit.assertion`]: src/dunit/assertion.d
[example]: example.d
[fluent-assertions]: fluent_assertions.d
