BEGIN { print "1..3\n"; }
use Inline CPP;
use Data::Dumper;

my @list = return_list();
print Dumper \@list;
print "not " unless $list[0] == 1;
print "ok 1\n";
print "not " unless $list[1] eq 'Hello?';
print "ok 2\n";
print "not " unless $list[2] == 15.6;
print "ok 3\n";

print Dumper return_void();

__END__
__CPP__

void return_list() {
    Inline_Stack_Vars;
    Inline_Stack_Reset;
    Inline_Stack_Push(sv_2mortal(newSViv(1)));
    Inline_Stack_Push(sv_2mortal(newSVpv("Hello?",0)));
    Inline_Stack_Push(sv_2mortal(newSVnv(15.6)));
    Inline_Stack_Done;
}

void return_void() {
    cout << "Hello!\n";
}
