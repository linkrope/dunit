//          Copyright Juan Manuel Cabo 2012.
//          Copyright Mario Kröplin 2018.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dunit.framework;

import dunit.assertion;
import dunit.attributes;
import dunit.color;

import core.runtime;
import core.time;
import std.algorithm;
import std.array;
import std.conv;
import std.stdio;
import std.string;
import std.process : environment;
import std.regex : regex, matchFirst;
import std.system : os, OS;
public import std.typetuple;

struct TestClass
{
    string name;
    string[] tests;
    Disabled[string] disabled;
    EnabledIf[string] enabledIf;
    DisabledIf[string] disabledIf;
    EnabledIfEnvironmentVariable[string] enabledIfEnvVar;
    DisabledIfEnvironmentVariable[string] disabledIfEnvVar;
    EnabledOnOs[string] enabledOnOs;
    DisabledOnOs[string] disabledOnOs;
    Tag[][string] tags;

    Object function() create;
    void function() beforeAll;
    void function(Object o) beforeEach;
    void delegate(Object o, string test) test;
    void function(Object o) afterEach;
    void function() afterAll;
}

TestClass[] testClasses;

struct TestSelection
{
    TestClass testClass;
    string[] tests;
}

mixin template Main()
{
    int main (string[] args)
    {
        return dunit_main(args);
    }
}

/**
 * Runs the tests according to the command-line arguments.
 */
public int dunit_main(string[] args)
{
    import std.getopt : config, defaultGetoptPrinter, getopt, GetoptResult;
    import std.path : baseName;
    import std.regex : match;

    GetoptResult result;
    string[] filters = null;
    string[] includeTags = null;
    string[] excludeTags = null;
    bool list = false;
    string report = null;
    bool verbose = false;
    bool xml = false;
    string testSuiteName = "dunit";

    try
    {
        result = getopt(args,
            config.caseSensitive,
            "list|l", "Display the test functions, then exit", &list,
            "filter|f", "Select test functions matching the regular expression", &filters,
            "include|t", "Provide a tag to be included in the test run", &includeTags,
            "exclude|T", "Provide a tag to be excluded from the test run", &excludeTags,
            "verbose|v", "Display more information as the tests are run", &verbose,
            "xml", "Display progressive XML output", &xml,
            "report", "Write JUnit-style XML test report", &report,
            "testsuite", "Provide a test-suite name for the JUnit-style XML test report", &testSuiteName,
            );
    }
    catch (Exception exception)
    {
        stderr.writeln("error: ", exception.msg);
        return 1;
    }

    if (result.helpWanted)
    {
        writefln("Usage: %s [options]", args.empty ? "testrunner" : baseName(args[0]));
        writeln("Run the functions with @Test attribute of all classes that mix in UnitTest.");
        defaultGetoptPrinter("Options:", result.options);
        return 0;
    }

    testClasses = unitTestFunctions ~ testClasses;

    TestSelection[] testSelections = null;

    if (filters is null)
    {
        foreach (testClass; testClasses)
            testSelections ~= TestSelection(testClass, testClass.tests);
    }
    else
    {
        foreach (filter; filters)
        {
            foreach (testClass; testClasses)
            {
                foreach (test; testClass.tests)
                {
                    string fullyQualifiedName = testClass.name ~ '.' ~ test;

                    if (match(fullyQualifiedName, filter))
                    {
                        auto foundTestSelections = testSelections.find!"a.testClass.name == b"(testClass.name);

                        if (foundTestSelections.empty)
                            testSelections ~= TestSelection(testClass, [test]);
                        else
                            foundTestSelections.front.tests ~= test;
                    }
                }
            }
        }
    }
    if (!includeTags.empty)
    {
        testSelections = testSelections
            .select!"!a.findAmong(b).empty"(includeTags)
            .array;
    }
    if (!excludeTags.empty)
    {
        testSelections = testSelections
            .select!"a.findAmong(b).empty"(excludeTags)
            .array;
    }

    if (list)
    {
        foreach (testSelection; testSelections) with (testSelection)
        {
            foreach (test; tests)
            {
                string fullyQualifiedName = testClass.name ~ '.' ~ test;

                writeln(fullyQualifiedName);
            }
        }
        return 0;
    }

    if (xml)
    {
        testListeners ~= new XmlReporter();
    }
    else
    {
        if (verbose)
            testListeners ~= new DetailReporter();
        else
            testListeners ~= new IssueReporter();
    }

    if (!report.empty)
        testListeners ~= new ReportReporter(report, testSuiteName);

    auto reporter = new ResultReporter();

    testListeners ~= reporter;
    runTests(testSelections, testListeners);
    if (!xml)
        reporter.write();
    return (reporter.errors > 0) ? 1 : (reporter.failures > 0) ? 2 : 0;
}

private auto select(alias pred)(TestSelection[] testSelections, string[] tags)
{
    import std.functional : binaryFun;

    bool matches(TestClass testClass, string test)
    {
        auto testTags = testClass.tags.get(test, null)
            .map!(tag => tag.name);

        return binaryFun!pred(testTags, tags);
    }

    TestSelection select(TestSelection testSelection)
    {
        string[] tests = testSelection.tests
            .filter!(test => matches(testSelection.testClass, test))
            .array;

        return TestSelection(testSelection.testClass, tests);
    }

    return testSelections
        .map!(testSelection => select(testSelection))
        .filter!(testSelection => !testSelection.tests.empty);
}

private TestSelection[] restrict(alias pred)(TestSelection[] testSelections, string[] tags)
{
    TestSelection restrict(TestSelection testSelection)
    {
        string[] tests = testSelection.tests
            .filter!(test => pred(testSelection.testClass.tags.get(test, null), tags))
            .array;

        return TestSelection(testSelection.testClass, tests);
    }

    return testSelections
        .map!(testSelection => restrict(testSelection))
        .filter!(testSelection => !testSelection.tests.empty)
        .array;
}

public bool matches(Tag[] tags, string[] choices)
{
    return tags.any!(tag => choices.canFind(tag.name));
}

public void runTests(TestSelection[] testSelections, TestListener[] testListeners)
in
{
    assert(all!"a !is null"(testListeners));
}
body
{
    bool tryRun(string phase, void delegate() action)
    {
        try
        {
            version(Have_dshould)
            {
                import dshould.ShouldType : FluentException;

                try
                {
                    action();
                }
                catch (FluentException exception)
                {
                    // convert exception to "fix" the message format
                    throw new AssertException('\n' ~ exception.msg,
                        exception.file, exception.line, exception);
                }
            }
            else
            {
                action();
            }
            return true;
        }
        catch (AssertException exception)
        {
            foreach (testListener; testListeners)
                testListener.addFailure(phase, exception);
            return false;
        }
        catch (Throwable throwable)
        {
            foreach (testListener; testListeners)
                testListener.addError(phase, throwable);
            return false;
        }
    }

    foreach (testSelection; testSelections) with (testSelection)
    {
        foreach (testListener; testListeners)
            testListener.enterClass(testClass.name);

        bool initialized = false;
        bool setUp = false;

        // run each @Test of the class
        foreach (test; tests)
        {
            bool success = false;

            foreach (testListener; testListeners)
                testListener.enterTest(test);
            scope (exit)
                foreach (testListener; testListeners)
                    testListener.exitTest(success);

            if (test in testClass.enabledIf && !testClass.enabledIf.get(test, EnabledIf.init).condition())
            {
                string reason = testClass.enabledIf.get(test, EnabledIf.init).reason;
                testClass.disabled[test] = Disabled(reason);
            }

            if (test in testClass.disabledIf && testClass.disabledIf.get(test, DisabledIf.init).condition())
            {
                string reason = testClass.disabledIf.get(test, DisabledIf.init).reason;
                testClass.disabled[test] = Disabled(reason);
            }

            if (test in testClass.enabledIfEnvVar)
            {
                string named = testClass.enabledIfEnvVar.get(test, EnabledIfEnvironmentVariable.init).named;
                string matches = testClass.enabledIfEnvVar.get(test, EnabledIfEnvironmentVariable.init).matches;
                
                if (environment.get(named) is null || matchFirst(environment.get(named), regex(matches)).empty)
                {
                    string reason = (environment.get(named) is null) ?
                        "Environment variable " ~ named ~ " not defined." :
                        "Environment variable " ~ named ~ " = '" ~ environment.get(named) ~ "' not matching pattern";
                    testClass.disabled[test] = Disabled(reason);
                }
            }

            if (test in testClass.disabledIfEnvVar)
            {
                string named = testClass.disabledIfEnvVar.get(test, DisabledIfEnvironmentVariable.init).named;
                string matches = testClass.disabledIfEnvVar.get(test, DisabledIfEnvironmentVariable.init).matches;
                
                if (environment.get(named) !is null && !matchFirst(environment.get(named), regex(matches)).empty)
                {
                    string reason = "Environment variable " ~ named ~ " = '" ~ environment.get(named) ~ "' matching pattern";
                    testClass.disabled[test] = Disabled(reason);
                }
            }

            if (test in testClass.enabledOnOs && !testClass.enabledOnOs.get(test, EnabledOnOs.init).os.canFind(os))
            {
                string operationSystemNames = testClass.enabledOnOs.get(test, EnabledOnOs.init).os.map!(osCode => OS(osCode).to!string).join(", ");
                string reason = "Operation system " ~ OS(os).to!string ~ " not matching " ~ operationSystemNames;
                testClass.disabled[test] = Disabled(reason);
            }

            if (test in testClass.disabledOnOs && testClass.disabledOnOs.get(test, DisabledOnOs.init).os.canFind(os))
            {
                string operationSystemNames = testClass.disabledOnOs.get(test, DisabledOnOs.init).os.map!(osCode => OS(osCode).to!string).join(", ");
                string reason = "Operation system " ~ OS(os).to!string ~ " matching " ~ operationSystemNames;
                testClass.disabled[test] = Disabled(reason);
            }

            if (test in testClass.disabled || (initialized && !setUp))
            {
                string reason = testClass.disabled.get(test, Disabled.init).reason;

                foreach (testListener; testListeners)
                    testListener.skip(reason);
                continue;
            }

            // use lazy initialization to run @BeforeAll
            // (failure or error can only be reported for a given test)
            if (!initialized)
            {
                setUp = tryRun("@BeforeAll",
                    { testClass.beforeAll(); });
                initialized = true;
            }

            Object testObject = null;

            if (setUp)
            {
                success = tryRun("this",
                    { testObject = testClass.create(); });
            }
            if (success)
            {
                success = tryRun("@BeforeEach",
                    { testClass.beforeEach(testObject); });
            }
            if (success)
            {
                success = tryRun("@Test",
                    { testClass.test(testObject, test); });
                // run @AfterEach even if @Test failed
                success = tryRun("@AfterEach",
                    { testClass.afterEach(testObject); })
                    && success;
            }
        }
        if (setUp)
        {
            tryRun("@AfterAll",
                { testClass.afterAll(); });
        }
    }

    foreach (testListener; testListeners)
        testListener.exit();
}

private __gshared TestListener[] testListeners = null;

/**
 * Registered implementations of this interface will be notified
 * about events that occur during the test run.
 */
interface TestListener
{
    public void enterClass(string className);
    public void enterTest(string test);
    public void skip(string reason);
    public void addFailure(string phase, AssertException exception);
    public void addError(string phase, Throwable throwable);
    public void exitTest(bool success);
    public void exit();

    public static string prettyOrigin(string className, string test, string phase)
    {
        const origin = prettyOrigin(test, phase);

        if (origin.startsWith('@'))
            return className ~ origin;
        else
            return className ~ '.' ~ origin;
    }

    public static string prettyOrigin(string test, string phase)
    {
        switch (phase)
        {
            case "@Test":
                return test;
            case "this":
            case "@BeforeAll":
            case "@AfterAll":
                return phase;
            default:
                return test ~ phase;
        }
    }
}

/**
 * Writes a "progress bar", followed by the errors and the failures.
 */
class IssueReporter : TestListener
{
    private struct Issue
    {
        string testClass;
        string test;
        string phase;
        Throwable throwable;
    }

    private Issue[] failures = null;
    private Issue[] errors = null;
    private string className;
    private string test;

    public override void enterClass(string className)
    {
        this.className = className;
    }

    public override void enterTest(string test)
    {
        this.test = test;
    }

    public override void skip(string reason)
    {
        writec(Color.onYellow, "S");
    }

    public override void addFailure(string phase, AssertException exception)
    {
        this.failures ~= Issue(this.className, this.test, phase, exception);
        writec(Color.onRed, "F");
    }

    public override void addError(string phase, Throwable throwable)
    {
        this.errors ~= Issue(this.className, this.test, phase, throwable);
        writec(Color.onRed, "E");
    }

    public override void exitTest(bool success)
    {
        if (success)
            writec(Color.onGreen, ".");
    }

    public override void exit()
    {
        writeln();

        // report errors
        if (!this.errors.empty)
        {
            writeln();
            if (this.errors.length == 1)
                writeln("There was 1 error:");
            else
                writefln("There were %d errors:", this.errors.length);

            foreach (i, issue; this.errors)
            {
                writefln("%d) %s", i + 1,
                    prettyOrigin(issue.testClass, issue.test, issue.phase));
                writeln(issue.throwable.description);
                stdout.lockingTextWriter.description(issue.throwable.info);
            }
        }

        // report failures
        if (!this.failures.empty)
        {
            writeln();
            if (this.failures.length == 1)
                writeln("There was 1 failure:");
            else
                writefln("There were %d failures:", this.failures.length);

            foreach (i, issue; this.failures)
            {
                writefln("%d) %s", i + 1,
                    prettyOrigin(issue.testClass, issue.test, issue.phase));
                writeln(issue.throwable.description);
            }
        }
    }
}

/**
 * Writes a detailed test report.
 */
class DetailReporter : TestListener
{
    private string test;
    private TickDuration startTime;

    public override void enterClass(string className)
    {
        writeln(className);
    }

    public override void enterTest(string test)
    {
        this.test = test;
        this.startTime = TickDuration.currSystemTick();
    }

    public override void skip(string reason)
    {
        writec(Color.yellow, "    SKIP: ");
        writeln(this.test);
        if (!reason.empty)
            writeln(indent(format(`"%s"`, reason)));
    }

    public override void addFailure(string phase, AssertException exception)
    {
        writec(Color.red, "    FAILURE: ");
        writeln(prettyOrigin(this.test, phase));
        writeln(indent(exception.description));
    }

    public override void addError(string phase, Throwable throwable)
    {
        writec(Color.red, "    ERROR: ");
        writeln(prettyOrigin(this.test, phase));
        writeln(indent(throwable.description));
        stdout.lockingTextWriter.description(throwable.info);
    }

    public override void exitTest(bool success)
    {
        if (success)
        {
            const elapsed = (TickDuration.currSystemTick() - this.startTime).usecs() / 1_000.0;

            writec(Color.green, "    OK: ");
            writefln("%6.2f ms  %s", elapsed, this.test);
        }
    }

    public override void exit()
    {
        // do nothing
    }

    private static string indent(string s, string indent = "        ")
    {
        return s.splitLines(KeepTerminator.yes).map!(line => indent ~ line).join;
    }
 }

/**
 * Writes a summary about the tests run.
 */
class ResultReporter : TestListener
{
    private uint tests = 0;
    private uint failures = 0;
    private uint errors = 0;
    private uint skips = 0;

    public override void enterClass(string className)
    {
        // do nothing
    }

    public override void enterTest(string test)
    {
        ++this.tests;
    }

    public override void skip(string reason)
    {
        ++this.skips;
    }

    public override void addFailure(string phase, AssertException exception)
    {
        ++this.failures;
    }

    public override void addError(string phase, Throwable throwable)
    {
        ++this.errors;
    }

    public override void exitTest(bool success)
    {
        // do nothing
    }

    public override void exit()
    {
        // do nothing
    }

    public void write() const
    {
        writeln();
        writefln("Tests run: %d, Failures: %d, Errors: %d, Skips: %d",
            this.tests, this.failures, this.errors, this.skips);

        if (this.failures + this.errors == 0)
        {
            writec(Color.onGreen, "OK");
            writeln();
        }
        else
        {
            writec(Color.onRed, "NOT OK");
            writeln();
        }
    }
}

/**
 * Writes progressive XML output.
 */
class XmlReporter : TestListener
{
    import undead.xml : Document, Element, Tag;

    private Document testCase;
    private string className;
    private TickDuration startTime;

    public override void enterClass(string className)
    {
        this.className = className;
    }

    public override void enterTest(string test)
    {
        this.testCase = new Document(new Tag("testcase"));
        this.testCase.tag.attr["classname"] = this.className;
        this.testCase.tag.attr["name"] = test;
        this.startTime = TickDuration.currSystemTick();
    }

    public override void skip(string reason)
    {
        auto element = new Element("skipped");

        element.tag.attr["message"] = reason;
        this.testCase ~= element;
    }

    public override void addFailure(string phase, AssertException exception)
    {
        auto element = new Element("failure");
        const message = format("%s %s", phase, exception.description);

        element.tag.attr["message"] = message;
        this.testCase ~= element;
    }

    public override void addError(string phase, Throwable throwable)
    {
        auto element = new Element("error", throwable.info.toString);
        const message = format("%s %s", phase, throwable.description);

        element.tag.attr["message"] = message;
        this.testCase ~= element;
    }

    public override void exitTest(bool success)
    {
        const elapsed = (TickDuration.currSystemTick() - this.startTime).msecs() / 1_000.0;

        this.testCase.tag.attr["time"] = format("%.3f", elapsed);

        const report = join(this.testCase.pretty(4), "\n");

        writeln(report);
    }

    public override void exit()
    {
        // do nothing
    }
}

/**
 * Writes a JUnit-style XML test report.
 */
class ReportReporter : TestListener
{
    import undead.xml : Document, Element, Tag;

    private const string fileName;
    private Document document;
    private Element testSuite;
    private Element testCase;
    private string className;
    private TickDuration startTime;

    public this(string fileName, string testSuiteName)
    {
        this.fileName = fileName;
        this.document = new Document(new Tag("testsuites"));
        this.testSuite = new Element("testsuite");
        this.testSuite.tag.attr["name"] = testSuiteName;
        this.document ~= this.testSuite;
    }

    public override void enterClass(string className)
    {
        this.className = className;
    }

    public override void enterTest(string test)
    {
        this.testCase = new Element("testcase");
        this.testCase.tag.attr["classname"] = this.className;
        this.testCase.tag.attr["name"] = test;
        this.testSuite ~= this.testCase;
        this.startTime = TickDuration.currSystemTick();
    }

    public override void skip(string reason)
    {
        // avoid wrong interpretation of more than one child
        if (this.testCase.elements.empty)
        {
            auto element = new Element("skipped");

            element.tag.attr["message"] = reason;
            this.testCase ~= element;
        }
    }

    public override void addFailure(string phase, AssertException exception)
    {
        // avoid wrong interpretation of more than one child
        if (this.testCase.elements.empty)
        {
            auto element = new Element("failure");
            const message = format("%s %s", phase, exception.description);

            element.tag.attr["message"] = message;
            this.testCase ~= element;
        }
    }

    public override void addError(string phase, Throwable throwable)
    {
        // avoid wrong interpretation of more than one child
        if (this.testCase.elements.empty)
        {
            auto element = new Element("error", throwable.info.toString);
            const message = format("%s %s", phase, throwable.description);

            element.tag.attr["message"] = message;
            this.testCase ~= element;
        }
    }

    public override void exitTest(bool success)
    {
        const elapsed = (TickDuration.currSystemTick() - this.startTime).msecs() / 1_000.0;

        this.testCase.tag.attr["time"] = format("%.3f", elapsed);
    }

    public override void exit()
    {
        import std.file : mkdirRecurse, write;
        import std.path: dirName;

        const report = join(this.document.pretty(4), "\n") ~ "\n";

        mkdirRecurse(this.fileName.dirName);
        write(this.fileName, report);
    }
}

shared static this()
{
    Runtime.moduleUnitTester = () => true;
}

private TestClass[] unitTestFunctions()
{
    TestClass[] testClasses = null;
    TestClass testClass;

    testClass.tests = ["unittest"];
    testClass.create = () => null;
    testClass.beforeAll = () {};
    testClass.beforeEach = (o) {};
    testClass.afterEach = (o) {};
    testClass.afterAll = () {};

    foreach (moduleInfo; ModuleInfo)
    {
        if (moduleInfo)
        {
            auto unitTest = moduleInfo.unitTest;

            if (unitTest)
            {
                testClass.name = moduleInfo.name;
                testClass.test = (o, test) { unitTest(); };
                testClasses ~= testClass;
            }
        }
    }
    return testClasses;
}

/**
 * Registers a class as a unit test.
 */
mixin template UnitTest()
{
    private static this()
    {
        TestClass testClass;

        testClass.name = this.classinfo.name;
        testClass.tests = _members!(typeof(this), Test);
        testClass.disabled = _attributeByMember!(typeof(this), Disabled);
        testClass.enabledIf = _attributeByMember!(typeof(this), EnabledIf);
        testClass.disabledIf = _attributeByMember!(typeof(this), DisabledIf);
        testClass.enabledIfEnvVar = _attributeByMember!(typeof(this), EnabledIfEnvironmentVariable);
        testClass.disabledIfEnvVar = _attributeByMember!(typeof(this), DisabledIfEnvironmentVariable);
        testClass.enabledOnOs = _attributeByMember!(typeof(this), EnabledOnOs);
        testClass.disabledOnOs = _attributeByMember!(typeof(this), DisabledOnOs);
        testClass.tags = _attributesByMember!(typeof(this), Tag);

        testClass.create = ()
        {
            mixin("return new " ~ typeof(this).stringof ~ "();");
        };
        testClass.beforeAll = ()
        {
            mixin(_staticSequence(_members!(typeof(this), BeforeAll)));
        };
        testClass.beforeEach = (Object o)
        {
            mixin(_sequence(_members!(typeof(this), BeforeEach)));
        };
        testClass.test = (Object o, string name)
        {
            mixin(_choice(_members!(typeof(this), Test)));
        };
        testClass.afterEach = (Object o)
        {
            mixin(_sequence(_members!(typeof(this), AfterEach)));
        };
        testClass.afterAll = ()
        {
            mixin(_staticSequence(_members!(typeof(this), AfterAll)));
        };

        testClasses ~= testClass;
    }

    private static string _choice(in string[] memberFunctions)
    {
        string block = "auto testObject = cast(" ~ typeof(this).stringof ~ ") o;\n";

        block ~= "switch (name)\n{\n";
        foreach (memberFunction; memberFunctions)
            block ~= `case "` ~ memberFunction ~ `": testObject.` ~ memberFunction ~ "(); break;\n";
        block ~= "default: break;\n}\n";
        return block;
    }

    private static string _staticSequence(in string[] memberFunctions)
    {
        string block = null;

        foreach (memberFunction; memberFunctions)
            block ~= memberFunction ~ "();\n";
        return block;
    }

    private static string _sequence(in string[] memberFunctions)
    {
        string block = "auto testObject = cast(" ~ typeof(this).stringof ~ ") o;\n";

        foreach (memberFunction; memberFunctions)
            block ~= "testObject." ~ memberFunction ~ "();\n";
        return block;
    }

    template _members(T, alias attribute)
    {
        static string[] helper()
        {
            import std.meta : AliasSeq;
            import std.traits : hasUDA;

            string[] members;

            foreach (name; __traits(allMembers, T))
            {
                static if (__traits(compiles, __traits(getMember, T, name)))
                {
                    alias member = AliasSeq!(__traits(getMember, T, name));

                    static if (__traits(compiles, hasUDA!(member, attribute)))
                    {
                        static if (hasUDA!(member, attribute))
                            members ~= name;
                    }
                }
            }
            return members;
        }

        enum _members = helper;
    }

    template _attributeByMember(T, Attribute)
    {
        static Attribute[string] helper()
        {
            import std.format : format;
            import std.meta : AliasSeq;

            Attribute[string] attributeByMember;

            foreach (name; __traits(allMembers, T))
            {
                static if (__traits(compiles, __traits(getMember, T, name)))
                {
                    alias member = AliasSeq!(__traits(getMember, T, name));

                    static if (__traits(compiles, _getUDAs!(member, Attribute)))
                    {
                        alias attributes = _getUDAs!(member, Attribute);

                        static if (attributes.length > 0)
                        {
                            static assert(attributes.length == 1,
                                format("%s.%s should not have more than one attribute @%s",
                                    T.stringof, name, Attribute.stringof));

                            attributeByMember[name] = attributes[0];
                        }
                    }
                }
            }
            return attributeByMember;
        }

        enum _attributeByMember = helper;
    }

    template _attributesByMember(T, Attribute)
    {
        static Attribute[][string] helper()
        {
            import std.meta : AliasSeq;

            Attribute[][string] attributesByMember;

            foreach (name; __traits(allMembers, T))
            {
                static if (__traits(compiles, __traits(getMember, T, name)))
                {
                    alias member = AliasSeq!(__traits(getMember, T, name));

                    static if (__traits(compiles, _getUDAs!(member, Attribute)))
                    {
                        alias attributes = _getUDAs!(member, Attribute);

                        static if (attributes.length > 0)
                            attributesByMember[name] = attributes;
                    }
                }
            }
            return attributesByMember;
        }

        enum _attributesByMember = helper;
    }

    // Gets user-defined attributes, but also gets Attribute.init for @Attribute.
    template _getUDAs(alias member, Attribute)
    {
        static auto helper()
        {
            Attribute[] attributes;

            static if (__traits(compiles, __traits(getAttributes, member)))
            {
                foreach (attribute; __traits(getAttributes, member))
                {
                    static if (is(attribute == Attribute))
                        attributes ~= Attribute.init;
                    static if (is(typeof(attribute) == Attribute))
                        attributes ~= attribute;
                }
            }
            return attributes;
        }

        enum _getUDAs = helper;
    }
}
