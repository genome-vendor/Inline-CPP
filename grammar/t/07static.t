BEGIN { print "1..1\n"; }
use Inline CPP => <<'END';
class Foo {
  public:
    Foo() {}
    ~Foo() {}
    static char *get_string() { return "Hello, world!\n"; }
};
END

print "not " unless Foo->get_string eq "Hello, world!\n";
print "ok 1\n";
