BEGIN { print "1..1\n"; }
use Inline CPP => <<'END';

class Foo {
  public:
    Foo(int, int);
};

Foo::Foo(int a, int b) {

}

int add(int, int);
int add(int a, int b) { return a + b; }

END

print "not " unless Foo->new(10, 11);
print "ok 1\n";
