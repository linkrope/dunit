#!/usr/bin/env dub
/+ dub.sdl:
name "example"
dependency "d-unit" version=">=0.8.0"
+/

//          Copyright Juan Manuel Cabo 2012.
//          Copyright Mario Kröplin 2017.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module example;

import dunit;
import core.thread;
import core.time;
import std.range;
import std.stdio;
import std.system : os;

/**
 * This example demonstrates the reporting of test failures.
 */
class Test
{
    mixin UnitTest;

    @Test
    public void assertEqualsFailure() @safe pure
    {
        string expected = "bar";
        string actual = "baz";

        assertEquals(expected, actual);
    }

    @Test
    public void assertAssocArrayEqualsFailure() pure
    {
        string[int] expected = [1: "foo", 2: "bar"];
        string[int] actual = [1: "foo", 2: "baz"];

        assertArrayEquals(expected, actual);
    }

    @Test
    public void assertRangeEqualsFailure() @safe pure
    {
        int[] expected = [0, 1, 1, 2];
        auto actual = iota(0, 3);

        assertRangeEquals(expected, actual);
    }

    @Test
    public void assertAllFailure() @safe
    {
        assertAll(
            assertLessThan(6 * 7, 42),
            assertGreaterThan(6 * 7, 42),
        );
    }
}

/**
 * This example demonstrates the order in which the fixture functions run.
 * The functions 'setUp' and 'tearDown' run before and after each test.
 * The functions 'setUpAll' and 'tearDownAll' run once before and after
 * all tests in the class.
 */
class TestFixture
{
    mixin UnitTest;

    public this()
    {
        debug writeln("@this()");
    }

    @BeforeAll
    public static void setUpAll()
    {
        debug writeln("@BeforeAll");
    }

    @AfterAll
    public static void tearDownAll()
    {
        debug writeln("@AfterAll");
    }

    @BeforeEach
    public void setUp()
    {
        debug writeln("@BeforeEach");
    }

    @AfterEach
    public void tearDown()
    {
        debug writeln("@AfterEach");
    }

    @Test
    public void test1() @safe pure
    {
        debug writeln("@test1()");
    }

    @Test
    public void test2() @safe pure
    {
        debug writeln("@test2()");
    }
}

/**
 * This example demonstrates how to reuse tests and a test fixture.
 */
class TestReuse : TestFixture
{
    mixin UnitTest;

    @BeforeEach
    public override void setUp()
    {
        debug writeln("@BeforeEach override");
    }
}

/**
 * This example demonstrates various things to know about the test framework.
 */
class TestingThisAndThat
{
    mixin UnitTest;

    // test function can have default arguments
    @Test
    public void testResult(bool actual = true) @safe pure
    {
        assertTrue(actual);
    }

    // test function can even be private
    // tagged test functions can be selected to be included or excluded
    @Test
    @Tag("fast")
    @Tag("smoke")
    private void success() @safe pure
    {
        testResult(true);
    }

    // disabled test function
    @Test
    @Disabled("not ready yet")
    public void failure() @safe pure
    {
        testResult(false);
    }

    // enabled by condition test function
    @Test
    @EnabledIf(true, "not ready yet")
    public void enabledByCondition() @safe pure
    {
        testResult(true);
    }

    // not enabled by condition test function
    @Test
    @EnabledIf(false, "not ready yet")
    public void notEnabledByCondition() @safe pure
    {
        testResult(false);
    }

    // disabled by condition test function
    @Test
    @DisabledIf(true, "not ready yet")
    public void disabledByCondition() @safe pure
    {
        testResult(false);
    }

    // not disabled by condition test function
    @Test
    @DisabledIf(false, "not ready yet")
    public void notDisabledByCondition() @safe pure
    {
        testResult(true);
    }

    // enabled by environment variable test function
    @Test
    @EnabledIfEnvironmentVariable("PATH", ".*")
    public void enabledByEnvironmentVariable() @safe pure
    {
        testResult(true);
    }

    // not enabled by environment variable test function
    @Test
    @EnabledIfEnvironmentVariable("PATH", "42")
    public void notEnabledByEnvironmentVariable() @safe pure
    {
        testResult(false);
    }

    // disabled by environment variable test function
    @Test
    @DisabledIfEnvironmentVariable("PATH", ".*")
    public void disabledByEnvironmentVariable() @safe pure
    {
        testResult(false);
    }

    // not disabled by environment variable test function
    @Test
    @DisabledIfEnvironmentVariable("PATH", "42")
    public void notDisabledByEnvironmentVariable() @safe pure
    {
        testResult(true);
    }

    // enabled on os test function
    @Test
    @EnabledOnOs([os])
    public void enabledByOs() @safe pure
    {
        testResult(true);
    }

    // disabled on os test function
    @Test
    @DisabledOnOs([os])
    public void disabledByOs() @safe pure
    {
        testResult(false);
    }

    // failed contracts are errors, not failures
    @Test
    public void error() @safe pure
    {
        assert(false);
    }

    // expected exception can be further verified
    @Test
    public void testException() @safe pure
    {
        import std.exception : enforce;

        auto exception = expectThrows(enforce(false));

        assertEquals("Enforcement failed", exception.msg);
    }
}

/**
 * This example demonstrates how to test asynchronous code.
 */
class TestingAsynchronousCode
{
    mixin UnitTest;

    private Thread thread;

    private bool done;

    @BeforeEach
    public void setUp()
    {
        done = false;
        thread = new Thread(&threadFunction);
    }

    @AfterEach
    public void tearDown()
    {
        thread.join();
    }

    private void threadFunction()
    {
        Thread.sleep(100.msecs);
        done = true;
    }

    @Test
    @Tag("slow")
    public void test()
    {
        assertFalse(done);

        thread.start();

        assertEventually({ return done; });
    }
}

// either use the 'Main' mixin or call 'dunit_main(args)'
mixin Main;
