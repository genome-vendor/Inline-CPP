BEGIN { print "1..1\n" }
use Inline CPP => <<'END';

struct Fizzle {
  int q;
  double foozle;
  int quack;
  Fizzle(int Q=0, double Foozle=0, int Quack=0) { 
    q = Q;
    foozle = Foozle;
    quack = Quack;
  }
  int get_q() { return q; }
  double get_foozle() { return foozle; }
  int get_quack() { return quack; }
};

END

my $o = new Fizzle;
print "not " unless $o->get_q == 0;
print "ok 1\n";
