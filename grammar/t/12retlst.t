use Test;
BEGIN { plan tests => 3 }
use Inline CPP;
use Data::Dumper;

my @list = return_list();
print Dumper \@list;
ok($list[0], 1);
ok($list[1], 'Hello?');
ok($list[2], 15.6);

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
    printf("Hello!\n");
}
