module dunit.attributes;

import std.system : OS;

enum AfterEach;
enum AfterAll;
enum BeforeEach;
enum BeforeAll;
enum Test;

struct Disabled
{
    string reason;
}

struct Tag
{
    string name;
}

struct EnabledIf
{
    bool function() condition;
    string reason;
}

struct DisabledIf
{
    bool function() condition;
    string reason;
}

struct EnabledIfEnvironmentVariable
{
    string named;
    string matches = ".*";
}

struct DisabledIfEnvironmentVariable
{
    string named;
    string matches = ".*";
}

struct EnabledOnOs
{
    OS[] value;

    this(OS[] value...)
    {
        this.value = value;
    }
}

struct DisabledOnOs
{
    OS[] value;

    this(OS[] value...)
    {
        this.value = value;
    }
}

deprecated("use AfterEach instead") alias After = AfterEach;
deprecated("use AfterAll instead") alias AfterClass = AfterAll;
deprecated("use BeforeEach instead") alias Before = BeforeEach;
deprecated("use BeforeAll instead") alias BeforeClass = BeforeAll;
deprecated("use Disabled instead") alias Ignore = Disabled;
