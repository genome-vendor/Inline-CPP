BEGIN { print "1..2\n" }
use Inline CPP => <<'END';

class Abstract {
  public:
    virtual char *text() = 0;
    virtual int greet(char *name) { 
	cout << "Hello, " << name << endl; 
	return 17; 
    }
};

class Impl : public Abstract {
  public:
    Impl() {}
    ~Impl() {}
    virtual char *text() { return "Hello from Impl!"; }
};

END

my $o = new Impl;
print "not " unless $o->text eq 'Hello from Impl!';
print "ok 1\n";
print "not " unless $o->greet('Neil') == 17;
print "ok 2\n"; 