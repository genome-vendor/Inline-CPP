BEGIN {
  print "1..5\n";
}

use Inline CPP => <<'END';

class Foo {
 public:
   Foo() { 
 	secret=0; 
   }

   ~Foo() { }

   int get_secret() { return secret; }
   int set_secret(int s) { secret = s; }

 protected:
   int secret;
};

class Bar : public Foo {
 public:
   Bar(int s) { secret = s; }
   ~Bar() {  }

   void set_secret(int s) { secret = s * 2; }
};

END

# If it works, it will print this. Otherwise it won't.
print "ok 1\n";

# Test Foo
my $o = new Foo;
print "not " unless $o->get_secret() == 0;
print "ok 2\n";
$o->set_secret(539);
print "not " unless $o->get_secret() == 539;
print "ok 3\n";

# Test Bar
my $p = new Bar(11);
print "not " unless $p->get_secret() == 11;
print "ok 4\n";
$p->set_secret(21);
print "not " unless $p->get_secret() == 42;
print "ok 5\n";

