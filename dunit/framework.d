//          Copyright Juan Manuel Cabo 2012.
//          Copyright Mario Kröplin 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dunit.framework;

public import dunit.assertion;
public import dunit.attributes;

import core.time;
import std.algorithm;
import std.array;
import std.conv;
import std.getopt;
import std.path;
import std.regex;
import std.stdio;
public import std.typetuple;

struct TestClass
{
    string[] tests;
    string[] ignoredTests;

    Object function() create;
    void function(Object o) beforeClass;
    void function(Object o) before;
    void function(Object o, string testName) test;
    void function(Object o) after;
    void function(Object o) afterClass;
}

string[] testClassOrder;
TestClass[string] testClasses;

mixin template Main()
{
    int main (string[] args)
    {
        return dunit_main(args);
    }
}

public int dunit_main(string[] args)
{
    string[] filters = null;
    bool help = false;
    bool list = false;
    bool verbose = false;

    getopt(args,
            "filter|f", &filters,
            "help|h", &help,
            "list|l", &list,
            "verbose|v", &verbose);

    if (help)
    {
        writefln("Usage: %s [options]", args.empty ? "testrunner" : baseName(args[0]));
        writeln("Run the functions with @Test attribute of all classes that mix in UnitTest.");
        writeln();
        writeln("Options:");
        writeln("  -f, --filter REGEX    Select test functions matching the regular expression");
        writeln("                        Multiple selections are processed in sequence");
        writeln("  -h, --help            Display usage information, then exit");
        writeln("  -l, --list            Display the test functions, then exit");
        writeln("  -v, --verbose         Display more information as the tests are run");
        return 0;
    }

    string[][string] selectedTestNamesByClass = null;

    if (filters is null)
        filters = [null];

    foreach (filter; filters)
    {
        foreach (className; testClassOrder)
        {
            foreach (testName; testClasses[className].tests)
            {
                string fullyQualifiedName = className ~ '.' ~ testName;

                if (match(fullyQualifiedName, filter))
                    selectedTestNamesByClass[className] ~= testName;
            }
        }
    }

    if (list)
    {
        foreach (className; testClassOrder)
        {
            foreach (testName; selectedTestNamesByClass.get(className, null))
            {
                string fullyQualifiedName = className ~ '.' ~ testName;

                writeln(fullyQualifiedName);
            }
        }
        return 0;
    }

    if (verbose)
        return runTests_Tree(selectedTestNamesByClass);
    else
        return runTests_Progress(selectedTestNamesByClass);
}

/**
 * Runs all the unit tests, showing progress dots, and the results at the end.
 */
public static int runTests_Progress(string[][string] testNamesByClass)
{
    struct Entry
    {
        string testClass;
        string testName;
        Throwable throwable;
    }

    Entry[] failures = null;
    Entry[] errors = null;
    int count = 0;

    foreach (className; testClassOrder)
    {
        if (className !in testNamesByClass)
            continue;

        // create test object
        Object testObject = null;

        try
        {
            testObject = testClasses[className].create();
        }
        catch (AssertException exception)
        {
            failures ~= Entry(className, "this", exception);
            writef_failure("F");
            continue;
        }
        catch (Throwable throwable)
        {
            errors ~= Entry(className, "this", throwable);
            writef_failure("F");
            continue;
        }

        // set up class
        try
        {
            testClasses[className].beforeClass(testObject);
        }
        catch (AssertException exception)
        {
            failures ~= Entry(className, "BeforeClass", exception);
            writef_failure("F");
            continue;
        }
        catch (Throwable throwable)
        {
            errors ~= Entry(className, "BeforeClass", throwable);
            writef_failure("F");
            continue;
        }

        // run each test function of the class
        foreach (testName; testNamesByClass[className])
        {
            if (canFind(testClasses[className].ignoredTests, testName))
            {
                writef_ignored("I");
                continue;
            }

            ++count;

            // set up
            bool success = true;

            try
            {
                testClasses[className].before(testObject);
            }
            catch (AssertException exception)
            {
                failures ~= Entry(className, "Before", exception);
                writef_failure("F");
                continue;
            }
            catch (Throwable throwable)
            {
                errors ~= Entry(className, "Before", throwable);
                writef_failure("F");
                continue;
            }

            // test
            try
            {
                testClasses[className].test(testObject, testName);
            }
            catch (AssertException exception)
            {
                failures ~= Entry(className, testName, exception);
                writef_failure("F");
                success = false;
            }
            catch (Throwable throwable)
            {
                errors ~= Entry(className, testName, throwable);
                writef_failure("F");
                success = false;
            }

            // tear down (even if test failed)
            try
            {
                testClasses[className].after(testObject);
            }
            catch (AssertException exception)
            {
                failures ~= Entry(className, "After", exception);
                writef_failure("F");
                success = false;
            }
            catch (Throwable throwable)
            {
                errors ~= Entry(className, "After", throwable);
                writef_failure("F");
                success = false;
            }

            if (success)
                writef_success(".");
        }

        // tear down class
        try
        {
            testClasses[className].afterClass(testObject);
        }
        catch (AssertException exception)
        {
            failures ~= Entry(className, "AfterClass", exception);
        }
        catch (Throwable throwable)
        {
            errors ~= Entry(className, "AfterClass", throwable);
        }
    }

    // report results
    writeln();
    if (failures.empty && errors.empty)
    {
        writeln();
        writef_success("OK (%d %s)\n", count, (count == 1) ? "Test" : "Tests");
        return 0;
    }

    // report errors
    if (!errors.empty)
    {
        if (errors.length == 1)
            writeln("There was 1 error:");
        else
            writefln("There were %d errors:", errors.length);

        foreach (i, entry; errors)
        {
            Throwable throwable = entry.throwable;

            writefln("%d) %s(%s) %s", i + 1,
                    entry.testName, entry.testClass, throwable.toString);
        }
    }

    // report failures
    if (!failures.empty)
    {
        if (failures.length == 1)
            writeln("There was 1 failure:");
        else
            writefln("There were %d failures:", failures.length);

        foreach (i, entry; failures)
        {
            Throwable throwable = entry.throwable;

            writefln("%d) %s(%s) %s@%s(%d): %s", i + 1,
                    entry.testName, entry.testClass, typeid(throwable).name,
                    throwable.file, throwable.line, throwable.msg);
        }
    }

    writeln();
    writef_failure("NOT OK\n");
    writefln("Tests run: %d, Failures: %d, Errors: %d", count, failures.length, errors.length);
    return (errors.length > 0) ? 2 : (failures.length > 0) ? 1 : 0;
}

/**
 * Runs all the unit tests, showing the test tree as the tests run.
 */
public static int runTests_Tree(string[][string] testNamesByClass)
{
    int failureCount = 0;
    int errorCount = 0;

    writeln("Unit tests: ");
    foreach (className; testClassOrder)
    {
        if (className !in testNamesByClass)
            continue;

        writeln("    ", className);

        // create test object
        Object testObject = null;

        try
        {
            testObject = testClasses[className].create();
        }
        catch (AssertException exception)
        {
            writef_failure("        FAILURE: this(): %s@%s(%d): %s\n",
                    typeid(exception).name, exception.file, exception.line, exception.msg);
            ++failureCount;
        }
        catch (Throwable throwable)
        {
            writef_failure("        ERROR: this(): ", throwable.toString, "\n");
            ++errorCount;
        }
        if (testObject is null)
            continue;

        // set up class
        try
        {
            testClasses[className].beforeClass(testObject);
        }
        catch (AssertException exception)
        {
            writef_failure("        FAILURE: BeforeClass: %s@%s(%d): %s\n",
                    typeid(exception).name, exception.file, exception.line, exception.msg);
            ++failureCount;
            continue;
        }
        catch (Throwable throwable)
        {
            writef_failure("        ERROR: BeforeClass: ", throwable.toString, "\n");
            ++errorCount;
            continue;
        }

        // run each test of the class
        foreach (testName; testNamesByClass[className])
        {
            if (canFind(testClasses[className].ignoredTests, testName))
            {
                writef_ignored("        IGNORE: " ~ testName ~ "()\n");
                continue;
            }

            // set up
            try
            {
                testClasses[className].before(testObject);
            }
            catch (AssertException exception)
            {
                writef_failure("        FAILURE: Before: %s@%s(%d): %s\n",
                        typeid(exception).name, exception.file, exception.line, exception.msg);
                ++failureCount;
                continue;
            }
            catch (Throwable throwable)
            {
                writef_failure("        ERROR: Before: ", throwable.toString, "\n");
                ++errorCount;
                continue;
            }

            // test
            try
            {
                TickDuration startTime = TickDuration.currSystemTick();
                testClasses[className].test(testObject, testName);
                double elapsedMs = (TickDuration.currSystemTick() - startTime).usecs() / 1000.0;
                writef_success("        OK: %6.2f ms  %s()\n", elapsedMs, testName);
            }
            catch (AssertException exception)
            {
                writef_failure("        FAILURE: " ~ testName ~ "(): %s@%s(%d): %s\n",
                        typeid(exception).name, exception.file, exception.line, exception.msg);
                ++failureCount;
            }
            catch (Throwable throwable)
            {
                writef_failure("        ERROR: ", testName, "(): ", throwable.toString, "\n");
                ++errorCount;
            }

            // tear down (call anyways if test failed)
            try
            {
                testClasses[className].after(testObject);
            }
            catch (AssertException exception)
            {
                writef_failure("        FAILURE: After: %s@%s(%d): %s\n",
                        typeid(exception).name, exception.file, exception.line, exception.msg);
                ++failureCount;
            }
            catch (Throwable throwable)
            {
                writef_failure("        ERROR: After: ", throwable.toString,"\n");
                ++errorCount;
            }
        }

        // tear down class
        try
        {
            testClasses[className].afterClass(testObject);
        }
        catch (AssertException exception)
        {
            writef_failure("        FAILURE: AfterClass: %s@%s(%d): %s\n",
                    typeid(exception).name, exception.file, exception.line, exception.msg);
            ++failureCount;
        }
        catch (Throwable throwable)
        {
            writef_failure("        ERROR: AfterClass: ", throwable.toString,"\n");
            ++errorCount;
        }
    }
    return (errorCount > 0) ? 2 : (failureCount > 0) ? 1 : 0;
}

version(Posix)
{
    private static void writef_success(Char, A...)(in Char[] fmt, A args)
    {
        // Set the foreground green
        if (canUseColor())
        {
            write(CSI,"37;42;1m");
        }

        writef(fmt,args);

        // Restore original color
        if (canUseColor())
        {
            write(CSI,"0m");
        }

        stdout.flush();
    }
}
else
{
    private static void writef_success(Char, A...)(in Char[] fmt, A args)
    {
        import core.sys.windows.windows;

        HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_SCREEN_BUFFER_INFO info;

        // Set the foreground green
        if (canUseColor())
        {
            GetConsoleScreenBufferInfo(hConsole, &info);
            SetConsoleTextAttribute(hConsole,FOREGROUND_GREEN | FOREGROUND_INTENSITY);
        }

        writef(fmt,args);

        // Restore original color
        if (canUseColor())
        {
            stdout.flush();
            SetConsoleTextAttribute(hConsole,info.wAttributes);
        }
    }
}

version(Posix)
{
    private static void writef_failure(Char, A...)(in Char[] fmt, A args)
    {
        // Set the foreground green
        if (canUseColor())
        {
            write(CSI,"37;41;1m");
        }

        writef(fmt,args);

        // Restore original color
        if (canUseColor())
        {
            write(CSI,"0m");
            stdout.flush();
        }
    }
}
else
{
    private static void writef_failure(Char, A...)(in Char[] fmt, A args)
    {
        import core.sys.windows.windows;

        HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_SCREEN_BUFFER_INFO info;

        // Set the foreground red
        if (canUseColor())
        {
            GetConsoleScreenBufferInfo(hConsole, &info);
            SetConsoleTextAttribute(hConsole,FOREGROUND_RED | FOREGROUND_INTENSITY);
        }

        writef(fmt,args);

        // Restore original color
        if (canUseColor())
        {
            stdout.flush();
            SetConsoleTextAttribute(hConsole,info.wAttributes);
        }
    }
}

version(Posix)
{
    private static void writef_ignored(Char, A...)(in Char[] fmt, A args)
    {
        // Set the foreground yellow
        if (canUseColor())
        {
            write(CSI,"37;42;1m");
        }

        writef(fmt,args);

        // Restore original color
        if (canUseColor())
        {
            write(CSI,"0m");
        }

        stdout.flush();
    }
}
else
{
    private static void writef_ignored(Char, A...)(in Char[] fmt, A args)
    {
        import core.sys.windows.windows;

        HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_SCREEN_BUFFER_INFO info;

        // Set the foreground yellow
        if (canUseColor())
        {
            GetConsoleScreenBufferInfo(hConsole, &info);
            SetConsoleTextAttribute(hConsole,FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_INTENSITY);
        }

        writef(fmt,args);

        // Restore original color
        if (canUseColor())
        {
            stdout.flush();
            SetConsoleTextAttribute(hConsole,info.wAttributes);
        }
    }
}

private static bool canUseColor()
{
    static bool useColor = false;
    static bool computed = false;

    if (!computed)
    {
        // disable colors if the results output is written to a file or pipe instead of a tty
        version(Posix)
        {
            import core.sys.posix.unistd;

            useColor = isatty(stdout.fileno()) != 0;
        }
        else
        {
            import core.sys.windows.windows;
            CONSOLE_SCREEN_BUFFER_INFO sbi;

            useColor = GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &sbi) > 0;
        }
        computed = true;
    }
    return useColor;
}

/**
 * Registers a class as a unit test.
 */
mixin template UnitTest()
{

    public static this()
    {
        TestClass testClass;

        testClass.tests = _memberFunctions!(typeof(this), Test,
                __traits(allMembers, typeof(this))).result.dup;
        testClass.ignoredTests = _memberFunctions!(typeof(this), Ignore,
                __traits(allMembers, typeof(this))).result.dup;

        static Object create()
        {
            mixin("return new " ~ typeof(this).stringof ~ "();");
        }

        static void beforeClass(Object o)
        {
            mixin(_sequence(_memberFunctions!(typeof(this), BeforeClass,
                    __traits(allMembers, typeof(this))).result));
        }

        static void before(Object o)
        {
            mixin(_sequence(_memberFunctions!(typeof(this), Before,
                    __traits(allMembers, typeof(this))).result));
        }

        static void test(Object o, string name)
        {
            mixin(_choice(_memberFunctions!(typeof(this), Test,
              __traits(allMembers, typeof(this))).result));
        }

        static void after(Object o)
        {
            mixin(_sequence(_memberFunctions!(typeof(this), After,
                    __traits(allMembers, typeof(this))).result));
        }

        static void afterClass(Object o)
        {
            mixin(_sequence(_memberFunctions!(typeof(this), AfterClass,
                    __traits(allMembers, typeof(this))).result));
        }

        testClass.create = &create;
        testClass.beforeClass = &beforeClass;
        testClass.before = &before;
        testClass.test = &test;
        testClass.after = &after;
        testClass.afterClass = &afterClass;

        testClassOrder ~= this.classinfo.name;
        testClasses[this.classinfo.name] = testClass;
    }

    private static string _choice(const string[] memberFunctions)
    {
        string block = "auto testObject = cast(" ~ typeof(this).stringof ~ ") o;\n";

        block ~= "switch (name)\n{\n";
        foreach (memberFunction; memberFunctions)
        {
            block ~= `case "` ~ memberFunction ~ `": testObject.` ~ memberFunction ~ "(); break;\n";
        }
        block ~= "default: break;\n}\n";
        return block;
    }

    private static string _sequence(const string[] memberFunctions)
    {
        string block = "auto testObject = cast(" ~ typeof(this).stringof ~ ") o;\n";

        foreach (memberFunction; memberFunctions)
        {
            block ~= "testObject." ~ memberFunction ~ "();\n";
        }
        return block;
    }

    private template _memberFunctions(alias T, alias U, names...)
    {
        static if (names.length == 0)
        {
            immutable(string[]) result = [];
        }
        else
        {
            static if (__traits(compiles, mixin("(new " ~ T.stringof ~ "())." ~ names[0] ~ "()"))
                    && _hasAttribute!(T, names[0], U))
            {
                immutable(string[]) result = [names[0]] ~ _memberFunctions!(T, U, names[1 .. $]).result;
            }
            else
            {
                immutable(string[]) result = _memberFunctions!(T, U, names[1 .. $]).result;
            }
        }
    }

    template _hasAttribute(alias T, string name, attribute)
    {
        enum _hasAttribute = staticIndexOf!(attribute,
                __traits(getAttributes, __traits(getMember, T, name))) != -1;
    }

}
