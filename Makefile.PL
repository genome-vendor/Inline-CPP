use ExtUtils::MakeMaker;
use Config;

my $cc_guess;
my $ld_guess;
my $libs_guess;
if ($Config{osname} =~ /^MSWin/) {
    $cc_guess = 'cl -TP';
    $ld_guess = 'link';
    $libs_guess = 'MSVCIRT.LIB';
}
elsif ($Config{osname} eq 'linux') {
    $cc_guess = 'g++';
    $ld_guess = 'g++';
    $libs_guess = '';
}
# Sane defaults for other (probably unix-like) operating systems
else {
    $cc_guess = 'g++';
    $ld_guess = 'g++';
    $libs_guess = '';
}

print "This will configure and build Inline::C++.\n";

my $cpp_compiler = prompt("What default C++ compiler would you like to use?",
			  $cc_guess);
my $cpp_linker = prompt("What default C++ linker would you like to use?",
			$ld_guess);
my $libs = prompt("What default libraries would you like to include?",
		  $libs_guess);

# Apply the defaults:
open CPP, "CPP_pm";
my @lines = <CPP>;
close CPP;

for (@lines) {
    s|\@COMPILER|$cpp_compiler| if m|\# default compiler|;
    s|\@LINKER|$cpp_linker| if m|\# default linker|;
    s|\@DEFAULTLIBS|$libs| if m|\# default libs|;
}

open CPP, ">CPP.pm"
  or die "Can't write to CPP.pm!";
print CPP @lines;
close CPP;

WriteMakefile(
	      NAME => 'Inline::CPP',
	      VERSION_FROM => 'CPP.pm',
	      PREREQ_PM => { Inline => 0.31 },
	      clean => {FILES => 'CPP.pm blib_test/'},
	     );
