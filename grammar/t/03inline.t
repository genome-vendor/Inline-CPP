BEGIN {
   print "1..2\n";
}

use Inline CPP; 
use strict;

my $obj = new Color;
print "not " unless ref $obj eq 'main::Color';
print "ok 1\n";

$obj->set_color(15);
print $obj->get_color, "\n";

print "not " unless $obj->get_color eq 15;
print "ok 2\n";

__END__
__CPP__
void prn() {
    cout << "prn() called!" << endl;
}

class Color {
 public:
  Color() 
  {
    cout << "new Color object created..." << endl;
  }

  ~Color()
  {
    cout << "Color object being destroyed..." << endl;
  }

  int get_color() 
  {
    cout << "Color::get_color called. Returning " << color << endl;
    return color;
  }

  void set_color(int a)
  {
    cout << "Color::set_color(" << a << ")" << endl;
    color = a;
  }

 private:
  int color;
};


