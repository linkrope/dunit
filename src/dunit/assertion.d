//          Copyright Juan Manuel Cabo 2012.
//          Copyright Mario Kröplin 2017.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dunit.assertion;

import core.thread;
import core.time : MonoTime;
import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.string;
import std.traits;

/**
 * Thrown on an assertion failure.
 */
class AssertException : Exception
{
    @safe pure nothrow this(string msg,
            string file = __FILE__,
            size_t line = __LINE__,
            Throwable next = null)
    {
        super(msg.empty ? "Assertion failure" : msg, file, line, next);
    }
}

/**
 * Thrown on an assertion failure.
 */
class AssertAllException : AssertException
{
    private AssertException[] exceptions;

    @safe pure nothrow this(AssertException[] exceptions,
            string file = __FILE__,
            size_t line = __LINE__,
            Throwable next = null)
    {
        string msg = heading(exceptions.length);

        exceptions.each!(exception => msg ~= '\n' ~ exception.description);
        this.exceptions = exceptions;
        super(msg, file, line, next);
    }

    private @safe pure nothrow static string heading(size_t count)
    {
        if (count == 1)
            return "1 assertion failure:";
        else
            return text(count, " assertion failures:");
    }
}

/**
 * Returns a description of the throwable.
 */
@safe pure nothrow string description(Throwable throwable)
{
    import std.path : baseName, buildPath;

    with (throwable)
    {
        if (file.empty)
            return text(typeid(throwable).name, ": ", msg);
        else if (file.baseName == file)  // "foo.d:42" is not rendered as link
            return text(buildPath(".", file), ":", line, " ", typeid(throwable).name, ": ", msg);
        else
            return text(file, ":", line, " ", typeid(throwable).name, ": ", msg);
    }
}

/**
 * Writes the optional trace info of a throwable.
 */
void description(Output)(auto ref Output output, Throwable.TraceInfo traceInfo)
{
    if (traceInfo !is null)
    {
        output.put("----------------\n");
        foreach (line; traceInfo)
        {
            output.put(line);
            output.put("\n");
        }
        output.put("----------------\n");
    }
}

/**
 * Asserts that a condition is true.
 * Throws: AssertException otherwise
 */
void assertTrue(T)(T condition, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    if (cast(bool) condition)
        return;

    fail(msg, file, line);
}

///
@safe pure unittest
{
    assertTrue(true);
    assertTrue("foo" in ["foo": "bar"]);

    auto exception = expectThrows!AssertException(assertTrue(false));

    assertEquals("Assertion failure", exception.msg);
}

/**
 * Asserts that a condition is false.
 * Throws: AssertException otherwise
 */
void assertFalse(T)(T condition, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    if (!cast(bool) condition)
        return;

    fail(msg, file, line);
}

///
@safe pure unittest
{
    assertFalse(false);
    assertFalse("foo" in ["bar": "foo"]);

    auto exception = expectThrows!AssertException(assertFalse(true));

    assertEquals("Assertion failure", exception.msg);
}

/**
 * Asserts that the string values are equal.
 * Throws: AssertException otherwise
 */
void assertEquals(T, U)(T expected, U actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
    if (isSomeString!T)
{
    import dunit.diff : description;

    if (expected == actual)
        return;

    string header = (msg.empty) ? null : msg ~ "; ";

    fail(header ~ description(expected.to!string, actual.to!string),
            file, line);
}

///
@safe pure unittest
{
    assertEquals("foo", "foo");

    auto exception = expectThrows!AssertException(assertEquals("bar", "baz"));

    assertEquals("expected: <ba<r>> but was: <ba<z>>", exception.msg);
}

/**
 * Asserts that the floating-point values are approximately equal.
 * Throws: AssertException otherwise
 */
void assertEquals(T, U)(T expected, U actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
    if (isFloatingPoint!T || isFloatingPoint!U)
{
    import std.math : isClose;

    // keep defaults of deprecated approxEqual
    if (isClose(expected, actual, 1e-2, 1e-5))
        return;

    string header = (msg.empty) ? null : msg ~ "; ";

    fail(header ~ format("expected: <%s> but was: <%s>", expected, actual),
            file, line);
}

///
@safe /*pure*/ unittest  // format is impure for floating point values
{
    assertEquals(1, 1.01);

    auto exception = expectThrows!AssertException(assertEquals(1, 1.1));

    assertEquals("expected: <1> but was: <1.1>", exception.msg);
}

/**
 * Asserts that the values are equal.
 * Throws: AssertException otherwise
 */
void assertEquals(T, U)(T expected, U actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
    if (!isSomeString!T && !isFloatingPoint!T && !isFloatingPoint!U)
{
    if (expected == actual)
        return;

    string header = (msg.empty) ? null : msg ~ "; ";

    fail(header ~ format("expected: <%s> but was: <%s>", expected, actual),
            file, line);
}

///
@safe pure unittest
{
    assertEquals(42, 42);

    auto exception = expectThrows!AssertException(assertEquals(42, 24));

    assertEquals("expected: <42> but was: <24>", exception.msg);
}

///
unittest  // Object.opEquals is impure
{
    Object foo = new Object();
    Object bar = null;

    assertEquals(foo, foo);
    assertEquals(bar, bar);

    auto exception = expectThrows!AssertException(assertEquals(foo, bar));

    assertEquals("expected: <object.Object> but was: <null>", exception.msg);
}

/**
 * Asserts that the arrays are equal.
 * Throws: AssertException otherwise
 */
void assertArrayEquals(T, U)(in T[] expected, in U[] actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    assertRangeEquals(expected, actual,
            msg,
            file, line);
}

/**
 * Asserts that the associative arrays are equal.
 * Throws: AssertException otherwise
 */
void assertArrayEquals(T, U, V)(in T[V] expected, in U[V] actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    string header = (msg.empty) ? null : msg ~ "; ";

    foreach (key; expected.byKey)
        if (key in actual)
        {
            assertEquals(expected[key], actual[key],
                    format(header ~ "mismatch at key %s", key.repr),
                    file, line);
        }

    auto difference = setSymmetricDifference(expected.keys.sort(), actual.keys.sort());

    assertEmpty(difference,
            format("key mismatch; difference: %(%s, %)", difference),
            file, line);
}

///
pure unittest  // keys, values, byKey, byValue not usable in @safe context
{
    int[string] expected = ["foo": 1, "bar": 2];

    assertArrayEquals(expected, ["foo": 1, "bar": 2]);

    AssertException exception;

    exception = expectThrows!AssertException(assertArrayEquals(expected, ["foo": 2]));
    assertEquals(`mismatch at key "foo"; expected: <1> but was: <2>`, exception.msg);
    exception = expectThrows!AssertException(assertArrayEquals(expected, ["foo": 1]));
    assertEquals(`key mismatch; difference: "bar"`, exception.msg);
}

/**
 * Asserts that the ranges are equal.
 * Throws: AssertException otherwise
 */
void assertRangeEquals(R1, R2)(R1 expected, R2 actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
    if (isInputRange!R1 && isInputRange!R2 && is(typeof(expected.front == actual.front)))
{
    string header = (msg.empty) ? null : msg ~ "; ";
    size_t index = 0;

    for (; !expected.empty && ! actual.empty; ++index, expected.popFront, actual.popFront)
    {
        assertEquals(expected.front, actual.front,
                header ~ format("mismatch at index %s", index),
                file, line);
    }
    assertEmpty(expected,
            header ~ format("length mismatch at index %s; ", index) ~
            format("expected: <%s> but was: empty", expected.front),
            file, line);
    assertEmpty(actual,
            header ~ format("length mismatch at index %s; ", index) ~
            format("expected: empty but was: <%s>", actual.front),
            file, line);
}

///
@safe pure unittest
{
    int[] expected = [0, 1];

    assertRangeEquals(expected, [0, 1]);

    AssertException exception;

    exception = expectThrows!AssertException(assertRangeEquals(expected, [0]));
    assertEquals("length mismatch at index 1; expected: <1> but was: empty", exception.msg);
    exception = expectThrows!AssertException(assertRangeEquals(expected, [0, 1, 2]));
    assertEquals("length mismatch at index 2; expected: empty but was: <2>", exception.msg);
    exception = expectThrows!AssertException(assertArrayEquals("bar", "baz"));
    assertEquals("mismatch at index 2; expected: <r> but was: <z>", exception.msg);
}

/**
 * Asserts that the value is empty.
 * Throws: AssertException otherwise
 */
void assertEmpty(T)(T actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    if (actual.empty)
        return;

    fail(msg, file, line);
}

///
@safe pure unittest
{
    assertEmpty([]);

    auto exception = expectThrows!AssertException(assertEmpty([1, 2, 3]));

    assertEquals("Assertion failure", exception.msg);
}

/**
 * Asserts that the value is not empty.
 * Throws: AssertException otherwise
 */
void assertNotEmpty(T)(T actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    if (!actual.empty)
        return;

    fail(msg, file, line);
}

///
@safe pure unittest
{
    assertNotEmpty([1, 2, 3]);

    auto exception = expectThrows!AssertException(assertNotEmpty([]));

    assertEquals("Assertion failure", exception.msg);
}

/**
 * Asserts that the value is null.
 * Throws: AssertException otherwise
 */
void assertNull(T)(T actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    if (actual is null)
        return;

    fail(msg, file, line);
}

///
@safe pure unittest
{
    Object foo = new Object();

    assertNull(null);

    auto exception = expectThrows!AssertException(assertNull(foo));

    assertEquals("Assertion failure", exception.msg);
}

/**
 * Asserts that the value is not null.
 * Throws: AssertException otherwise
 */
void assertNotNull(T)(T actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    if (actual !is null)
        return;

    fail(msg, file, line);
}

///
@safe pure unittest
{
    Object foo = new Object();

    assertNotNull(foo);

    auto exception = expectThrows!AssertException(assertNotNull(null));

    assertEquals("Assertion failure", exception.msg);
}

/**
 * Asserts that the values are the same.
 * Throws: AssertException otherwise
 */
void assertSame(T, U)(T expected, U actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    if (expected is actual)
        return;

    string header = (msg.empty) ? null : msg ~ "; ";

    fail(header ~ format("expected same: <%s> was not: <%s>", expected, actual),
            file, line);
}

///
unittest  // format is impure and not safe for Object
{
    Object foo = new Object();
    Object bar = new Object();

    assertSame(foo, foo);

    auto exception = expectThrows!AssertException(assertSame(foo, bar));

    assertEquals("expected same: <object.Object> was not: <object.Object>", exception.msg);
}

/**
 * Asserts that the values are not the same.
 * Throws: AssertException otherwise
 */
void assertNotSame(T, U)(T expected, U actual, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    if (expected !is actual)
        return;

    string header = (msg.empty) ? null : msg ~ "; ";

    fail(header ~ "expected not same",
            file, line);
}

///
@safe pure unittest
{
    Object foo = new Object();
    Object bar = new Object();

    assertNotSame(foo, bar);

    auto exception = expectThrows!AssertException(assertNotSame(foo, foo));

    assertEquals("expected not same", exception.msg);
}

/**
 * Asserts that all assertions pass.
 * Throws: AssertAllException otherwise
 */
void assertAll(void delegate() @safe [] assertions ...) @safe
{
    AssertException[] exceptions = null;

    foreach (assertion; assertions)
        try
            assertion();
        catch (AssertException exception)
            exceptions ~= exception;
    if (!exceptions.empty)
    {
        // [Issue 16345] IFTI fails with lazy variadic function in some cases
        const file = null;
        const line = 0;

        throw new AssertAllException(exceptions, file, line);
    }
}

///
@safe unittest
{
    assertAll(
        assertTrue(true),
        assertFalse(false),
    );

    auto exception = expectThrows!AssertException(assertAll(
        assertTrue(false),
        assertFalse(true),
    ));

    assertTrue(exception.msg.canFind("2 assertion failures"), exception.msg);
}

/**
 * Asserts that the expression throws the specified throwable.
 * Throws: AssertException otherwise
 * Returns: the caught throwable
 */
T expectThrows(T : Throwable = Exception, E)(lazy E expression, lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    try
        expression();
    catch (T throwable)
        return throwable;

    string header = (msg.empty) ? null : msg ~ "; ";

    fail(header ~ format("expected <%s> was not thrown", T.stringof),
            file, line);
    assert(0);
}

///
@safe pure unittest
{
    import std.exception : enforce;

    auto exception = expectThrows(enforce(false));

    assertEquals("Enforcement failed", exception.msg);
}

///
@safe pure unittest
{
    auto exception = expectThrows!AssertException(expectThrows(42));

    assertEquals("expected <Exception> was not thrown", exception.msg);
}

/**
 * Fails a test.
 * Throws: AssertException
 */
void fail(string msg = null,
        string file = __FILE__,
        size_t line = __LINE__) @safe pure
{
    throw new AssertException(msg, file, line);
}

///
@safe pure unittest
{
    auto exception = expectThrows!AssertException(fail());

    assertEquals("Assertion failure", exception.msg);
}

alias assertGreaterThan = assertOp!">";
alias assertGreaterThanOrEqual = assertOp!">=";
alias assertLessThan = assertOp!"<";
alias assertLessThanOrEqual = assertOp!"<=";
alias assertIn = assertOp!"in";
alias assertNotIn = assertOp!"!in";

/**
 * Asserts that the condition (lhs op rhs) is satisfied.
 * Throws: AssertException otherwise
 * See_Also: http://d.puremagic.com/issues/show_bug.cgi?id=4653
 */
template assertOp(string op)
{
    void assertOp(T, U)(T lhs, U rhs, lazy string msg = null,
            string file = __FILE__,
            size_t line = __LINE__)
    {
        mixin("if (lhs " ~ op ~ " rhs) return;");

        string header = (msg.empty) ? null : msg ~ "; ";

        fail(format("%scondition (%s %s %s) not satisfied",
                header, lhs.repr, op, rhs.repr),
                file, line);
    }
}

///
@safe pure unittest
{
    assertLessThan(2, 3);

    auto exception = expectThrows!AssertException(assertGreaterThanOrEqual(2, 3));

    assertEquals("condition (2 >= 3) not satisfied", exception.msg);
}

///
@safe pure unittest
{
    assertIn("foo", ["foo": "bar"]);

    auto exception = expectThrows!AssertException(assertNotIn("foo", ["foo": "bar"]));

    assertEquals(`condition ("foo" !in ["foo":"bar"]) not satisfied`, exception.msg);
}

/**
 * Checks a probe until the timeout expires. The assert error is produced
 * if the probe fails to return 'true' before the timeout.
 *
 * The parameter timeout determines the maximum timeout to wait before
 * asserting a failure (default is 500ms).
 *
 * The parameter delay determines how often the predicate will be
 * checked (default is 10ms).
 *
 * This kind of assertion is very useful to check on code that runs in another
 * thread. For instance, the thread that listens to a socket.
 *
 * Throws: AssertException when the probe fails to become true before timeout
 */
public static void assertEventually(bool delegate() probe,
        Duration timeout = 500.msecs, Duration delay = 10.msecs,
        lazy string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    const startTime = MonoTime.currTime;

    while (!probe())
    {
        const elapsedTime = cast(Duration)(MonoTime.currTime - startTime);

        if (elapsedTime >= timeout)
            fail(msg.empty ? "timed out" : msg, file, line);

        Thread.sleep(delay);
    }
}

///
unittest
{
    assertEventually({ static count = 0; return ++count > 3; });

    auto exception = expectThrows!AssertException(assertEventually({ return false; }));

    assertEquals("timed out", exception.msg);
}

private string repr(T)(T value)
{
    // format string key with double quotes
    return format("%(%s%)", value.only);
}
