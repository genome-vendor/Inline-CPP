BEGIN { print "1..1\n"; }
use Inline CPP => <<'END';

class Foo {
   void priv(int a) { q = a; }
   int q;
public:
   Foo() {} 
   ~Foo() {}
   int zippo(int quack) { printf("Hello, world!\n"); }
};

END

print "ok 1\n";
