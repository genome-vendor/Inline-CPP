BEGIN {
   print "1..2\n";
}

use Inline Config => DIRECTORY => './blib_test';

use strict;
use Inline CPP => <<END; 

void prn() {
    cout << "prn() called!" << endl;
}

class Color {
 public:
  Color();
  ~Color();
  
  int get_color();
  void set_color(int c);
  
 private:
  int color;
};

Color::Color() {
   cout << "new Color object created..." << endl;
}

Color::~Color() {
   cout << "Color object being destroyed..." << endl;
}

void Color::set_color(int a) {
  cout << "Color::set_color(" << a << ")" << endl;
  color = a;
}

int Color::get_color() {
  cout << "Color::get_color called. Returning " << color << endl;
  return color;
}

END

my $obj = new Color;
print "not " unless ref $obj eq 'main::Color';
print "ok 1\n";

$obj->set_color(15);
print $obj->get_color, "\n";

print "not " unless $obj->get_color eq 15;
print "ok 2\n";
