BEGIN { print "1..3\n"; }
use Inline CPP;

print "not " unless Parent1->new->do_something == 51;
print "ok 1\n";
print "not " unless Parent2->new->do_another == 17;
print "ok 2\n";
print "not " unless Child->new->yet_another == 3;
print "ok 3\n";

__END__
__CPP__

class Parent1 {
  public:
    Parent1() { }
    ~Parent1() { }

    virtual int do_something() { return 51; }
};

class Parent2 {
  public:
    Parent2();
    ~Parent2();

    virtual int do_another();
};

Parent2::Parent2() { }
Parent2::~Parent2() { }
int Parent2::do_another() { return 17; }

class Child : public Parent1, public Parent2 {
  public:
    Child() { }
    ~Child() { }

    int yet_another() { return 3; }
};
