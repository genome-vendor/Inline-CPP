BEGIN { print "1..2\n"; }
use Inline CPP => DATA => PREFIX => 'Foo_';

print "not " unless identity("Neil") eq "Neil";
print "ok 1\n";
print "not " unless Foo->new->dummy eq "10";
print "ok 2\n";

__END__
__CPP__

struct Foo {
  int dummy() { return 10; }
};

char *Foo_identity(char *in) { return in; }

