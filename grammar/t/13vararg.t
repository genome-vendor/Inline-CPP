BEGIN { print "1..1\n"; }
use Inline CPP;

print "not " unless sum(1, 2, 3, 4, 5) == 15;
print "ok 1\n";

__END__
__CPP__

int sum(...) {
    Inline_Stack_Vars;
    int s = 0;
    for (int i=0; i<items; i++) {
	int tmp = SvIV(Inline_Stack_Item(i));
	s += tmp;
    }
    return s;
}
