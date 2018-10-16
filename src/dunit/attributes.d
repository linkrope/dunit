module dunit.attributes;

struct AfterEach { }
struct AfterAll { }
struct BeforeEach { }
struct BeforeAll { }
struct Test { }

struct Disabled
{
    string reason;
}

struct Tag
{
    string name;
}

deprecated("use AfterEach instead") alias After = AfterEach;
deprecated("use AfterAll instead") alias AfterClass = AfterAll;
deprecated("use BeforeEach instead") alias Before = BeforeEach;
deprecated("use BeforeAll instead") alias BeforeClass = BeforeAll;
deprecated("use Disabled instead") alias Ignore = Disabled;
