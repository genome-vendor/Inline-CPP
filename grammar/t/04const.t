BEGIN { print "1..1\n"; }
use Inline CPP => <<'END';
class Foo {
  public:
    Foo()  {}
    ~Foo() {}
    const char *data() { return "Hello dolly!\n"; }
};

END
print "not " unless Foo->new->data eq "Hello dolly!\n";
print "ok 1\n";
