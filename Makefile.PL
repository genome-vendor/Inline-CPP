use ExtUtils::MakeMaker;

my $cpp_compiler = prompt("What C++ compiler would you like to use?", "g++");
my $cpp_linker = prompt("What C++ linker would you like to use?",
			$cpp_compiler);

# Change the default C++ compiler grom g++ (if necessary);
open CRAZY, "CPP.pm";
my @lines = <CRAZY>;
close CRAZY;

for (@lines) {
    s|g\+\+|$cpp_compiler| if m|COMPILER|;
    s|g\+\+|$cpp_linker| if m|LINKER|;
}

open CRAZY, ">CPP.pm";
print CRAZY @lines;
close CRAZY;

WriteMakefile(
	      NAME => 'Inline::CPP',
	      VERSION_FROM => 'CPP.pm',
	      PREREQ_PM => { Inline => 0.30 },
	      clean => {FILES => 'blib_test/'},
	     );
