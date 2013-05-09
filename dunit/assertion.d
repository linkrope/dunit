/**
 * xUnit Testing Framework for the D Programming Language - assertions
 */

//          Copyright Juan Manuel Cabo 2012.
//          Copyright Mario Kröplin 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dunit.assertion;

import core.thread;
import core.time;
import std.algorithm;
import std.array;
import std.conv;
import std.string;

version (unittest) import std.exception;

/**
 * Thrown on an assertion failure.
 */
class AssertException : Exception
{
    this(string msg = null,
            string file = __FILE__,
            size_t line = __LINE__)
    {
        super(msg.empty ? "Assertion failure" : msg, file, line);
    }
}

/**
 * Asserts that a condition is true.
 * Throws: AssertException otherwise
 */
void assertTrue(string file = __FILE__, size_t line = __LINE__)
        (const bool condition,  const string msg = null)
{
    assertTrueImpl!(file, line)(condition, msg);
}

void assertTrue(string file = __FILE__, size_t line = __LINE__, A...)
        (const bool condition,  const string msg, A a)
{
    assertTrueImpl!(file, line)(condition, xformat(msg, a));
}

void assertTrueImpl(string file, size_t line)
        (const bool condition,  const string msg)
{
    if (condition)
        return;

    fail(msg, file, line);
}

/**
 * Asserts that a condition is false.
 * Throws: AssertException otherwise
 */
void assertFalse(string file = __FILE__, size_t line = __LINE__)
        (const bool condition,  const string msg = null)
{
    assertFalseImpl!(file, line)(condition, msg);
}

void assertFalse(string file = __FILE__, size_t line = __LINE__, A...)
        (const bool condition,  const string msg, A a)
{
    assertFalseImpl!(file, line)(condition, xformat(msg, a));
}

void assertFalseImpl(string file, size_t line)
        (const bool condition,  const string msg)
{
    if (!condition)
        return;

    fail(msg, file, line);
}

unittest
{
    assertTrue(true);
    assertTrue(true, "print%c assert messages", 'f');

    assertEquals("Assertion failure",
            collectExceptionMsg!AssertException(assertTrue(false)));

    assertFalse(false);
    assertFalse(false, "print%c assert messages", 'f');
    assertEquals("Assertion failure",
            collectExceptionMsg!AssertException(assertFalse(true)));
}

/**
 * Asserts that the values are equal.
 * Throws: AssertException otherwise
 */
void assertEquals(T, U, string file = __FILE__, size_t line = __LINE__, A...)
    (T expected, U actual, string msg, A a)
{
    assertEqualsImpl!(T,U,file,line)(expected, actual, xformat(msg, a));
}

void assertEquals(T, U, string file = __FILE__, size_t line = __LINE__)
    (T expected, U actual,  string msg = null)
{
    assertEqualsImpl!(T,U,file,line)(expected, actual, msg);
}

void assertEqualsImpl(T, U, string file, size_t line)
    (T expected, U actual,  string msg)
{
    if (expected == actual)
        return;

    string header = (msg.empty) ? null : msg ~ "; ";

    fail(header ~ "expected: <" ~ to!string(expected) ~ "> but was: <" 
        ~ to!string(actual) ~ ">", file, line);
}

unittest
{
    assertEquals("foo", "foo");
    assertEquals("foo", "foo", "print%c style assert message", 'f');
    assertEquals("expected: <foo> but was: <bar>",
            collectExceptionMsg!AssertException(assertEquals("foo", "bar")));

    assertEquals(42, 42);
    assertEquals("expected: <42> but was: <23>",
            collectExceptionMsg!AssertException(assertEquals(42, 23)));

    assertEquals(42.0, 42.0);

    Object foo = new Object();
    Object bar = null;

    assertEquals(foo, foo);
    assertEquals(bar, bar);
    assertEquals("expected: <object.Object> but was: <null>",
            collectExceptionMsg!AssertException(assertEquals(foo, bar)));
}

/**
 * Asserts that the arrays are equal.
 * Throws: AssertException otherwise
 */
void assertArrayEquals(T, U, string file = __FILE__, size_t line = __LINE__)
        (const(T[]) expecteds, const(U[]) actuals, string msg = null)
{
    assertArrayEqualsImpl!(T,U,file,line)(expecteds, actuals, msg);
}

void assertArrayEquals(T, U, string file = __FILE__, size_t line =
        __LINE__, A...)
        (const(T[]) expecteds, const(U[]) actuals, string msg, A a)
{
    assertArrayEqualsImpl!(T,U,file,line)(expecteds, actuals, xformat(msg,a));
}

void assertArrayEqualsImpl(T, U, string file, size_t line)
        (const(T[]) expecteds, const(U[]) actuals, string msg)
{
    string header = (msg.empty) ? null : msg ~ "; ";

    const size_t len = min(expecteds.length, actuals.length);
    for (size_t index = 0; index < len; ++index)
    {
        assertEquals!(T,U,file,line)(expecteds[index], actuals[index],
                header ~ "array mismatch at index " ~ to!string(index));
    }
    assertEquals!(size_t,size_t,file,line)(expecteds.length, actuals.length,
            header ~ "array length mismatch");
}

unittest
{
    int[] expecteds = [1, 2, 3];
    double[] actuals = [1, 2, 3];

    assertArrayEquals(expecteds, actuals);
    assertArrayEquals(expecteds, actuals, "print%c like message", 'f');
    assertEquals("array mismatch at index 1; expected: <2> but was: <2.3>",
            collectExceptionMsg!AssertException(assertArrayEquals(expecteds, 
            [1, 2.3])));
    assertEquals("array length mismatch; expected: <3> but was: <2>",
            collectExceptionMsg!AssertException(assertArrayEquals(expecteds, 
            [1, 2])));
    assertEquals("array mismatch at index 2; expected: <r> but was: <z>",
            collectExceptionMsg!AssertException(
            assertArrayEquals("bar", "baz")));
}

/**
 * Asserts that the value is null.
 * Throws: AssertException otherwise
 */
void assertNull(T, string file = __FILE__, size_t line = __LINE__, A...)
        (T actual,  string msg, A a)
{
    assertNullImpl!(T, true, file, line)(actual, xformat(msg, a));
}

void assertNull(T, string file = __FILE__, size_t line = __LINE__)
        (T actual,  string msg = null)
{
    assertNullImpl!(T, true, file, line)(actual, msg);
}

/**
 * Asserts that the value is not null.
 * Throws: AssertException otherwise
 */
void assertNotNull(T, string file = __FILE__, size_t line = __LINE__, A...)
        (T actual,  string msg, A a)
{
    assertNullImpl!(T, false, file, line)(actual, xformat(msg, a));
}

void assertNotNull(T, string file = __FILE__, size_t line = __LINE__)
        (T actual,  string msg = null)
{
    assertNullImpl!(T, false, file, line)(actual, msg);
}

void assertNullImpl(T, bool n, string file = __FILE__, size_t line = __LINE__)
        (T actual,  string msg = null)
{
    if ((actual is null) == n)
        return;

    fail(msg, file, line);
}

unittest
{
    Object foo = new Object();
    
    assertNull(null);
    assertNull(null, "print%c like message", 'f');
    assertEquals("Assertion failure",
            collectExceptionMsg!AssertException(assertNull(foo)));

    assertNotNull(foo);
    assertNotNull(foo, "print%c like message", 'f');
    assertEquals("Assertion failure",
            collectExceptionMsg!AssertException(assertNotNull(null)));
}

/**
 * Asserts that the values are the same.
 * Throws: AssertException otherwise
 */
void assertSame(T, U, string file = __FILE__, size_t line = __LINE__,A...)
        (T expected, U actual, string msg, A a)
{
    assertSameImpl!(T, U, true, file, line)(expected, actual, xformat(msg, a));
}

void assertSame(T, U, string file = __FILE__, size_t line = __LINE__)
        (T expected, U actual,  string msg = null)
{
    assertSameImpl!(T, U, true, file, line)(expected, actual, msg);
}

/**
 * Asserts that the values are not the same.
 * Throws: AssertException otherwise
 */
void assertNotSame(T, U, string file = __FILE__, size_t line = __LINE__,A...)
        (T expected, U actual, string msg, A a)
{
    assertSameImpl!(T, U, false, file, line)(expected, actual, xformat(msg, a));
}

void assertNotSame(T, U, string file = __FILE__, size_t line = __LINE__)
        (T expected, U actual,  string msg = null)
{
    assertSameImpl!(T, U, false, file, line)(expected, actual, msg);
}

void assertSameImpl(T, U, bool same, string file, size_t line)
        (T expected, U actual,  string msg)
{
    if ((expected is actual) == same)
        return;

    string header = (msg.empty) ? null : msg ~ "; ";

    static if(same) {
        fail(header ~ xformat("expected same: <%s> was not: <%s>",
            expected, actual), file, line);
    } else {
        fail(header ~ xformat("expected not same: <%s> was: <%s>",
            expected, actual), file, line);
    }
}

unittest
{
    Object foo = new Object();
    Object bar = new Object();

    assertSame(foo, foo);
    assertSame(foo, foo, "print%c like message", 'f');
    assertEquals("expected same: <object.Object> was not: <object.Object>",
            collectExceptionMsg!AssertException(assertSame(foo, bar)));

    assertNotSame(foo, bar);
    assertNotSame(foo, bar, "print%c like message", 'f');
    assertEquals("expected not same: <object.Object> was: <object.Object>",
            collectExceptionMsg!AssertException(assertNotSame(foo, foo)));
}

/**
 * Fails a test.
 * Throws: AssertException
 */
void fail(string msg = null,
        string file = __FILE__,
        size_t line = __LINE__)
{
    throw new AssertException(msg, file, line);
}

unittest
{
    assertEquals("Assertion failure",
            collectExceptionMsg!AssertException(fail()));
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
public static void assertEventually(string file = __FILE__, 
        size_t line = __LINE__)
        (bool delegate() probe, 
        Duration timeout = dur!"msecs"(500), Duration delay = dur!"msecs"(10), 
        string msg = null)
{
    TickDuration startTime = TickDuration.currSystemTick();
   
    while (!probe()) {
        Duration elapsedTime = cast(Duration)(TickDuration.currSystemTick() - 
            startTime);

        if (elapsedTime >= timeout) {
            if (msg.empty) {
                msg = "timed out";
            }
            fail(msg, file, line);
        }

        Thread.sleep(delay);
    }
}

unittest
{
    assertEventually({ static count = 0; return ++count > 42; });

    assertEquals("timed out",
        collectExceptionMsg!AssertException(
        assertEventually({ return false; })));
}
