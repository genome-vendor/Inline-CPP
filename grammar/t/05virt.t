BEGIN { print "1..1\n"; }
use Inline CPP => <<'END';
class Foo {
  public: 
    Foo() { }
    ~Foo() { }

    virtual const char *get_data_ro() { return "Hello Sally!\n"; }
};
END
print "not " unless Foo->new->get_data_ro eq "Hello Sally!\n";
print "ok 1\n";
