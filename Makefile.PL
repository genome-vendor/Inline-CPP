use ExtUtils::MakeMaker;
use Config;

#============================================================================
# We'll do our own prerequisite checking, since MakeMaker does it
# in a way that always fails: 'use Inline::C 0.33' will never work.
#============================================================================
eval { require Inline::C };
warn "Warning: prerequisite Inline::C  version 0.33 not found"
  if $@ or $Inline::C::VERSION < 0.33;

#============================================================================
# Make an intelligent guess about what compiler to use
#============================================================================
my $cc_guess;
my $libs_guess;
if ($Config{osname} =~ /^MSWin/) {
    $cc_guess = 'cl -TP';
    $libs_guess = 'MSVCIRT.LIB';
}
elsif ($Config{osname} eq 'linux') {
    $cc_guess = 'g++';
    $libs_guess = '-lstdc++';
}
elsif ($Config{osname} eq 'cygwin') {
    $cc_guess = 'g++';
    $libs_guess = '-lstdc++';
}
# Sane defaults for other (probably unix-like) operating systems
else {
    $cc_guess = 'g++';
    $libs_guess = '-lstdc++';
}

print "This will configure and build Inline::C++.\n";

my $cpp_compiler = prompt("What default C++ compiler would you like to use?",
			  $cc_guess);
my $libs = prompt("What default libraries would you like to include?",
		  $libs_guess);

# Apply the defaults:
open CPP, "CPP.pm";
my @lines = <CPP>;
close CPP;

for (@lines) {
    s|\@COMPILER|$cpp_compiler| if m|\# default compiler|;
    s|\@DEFAULTLIBS|$libs| if m|\# default libs|;
}

open CPP, ">CPP.pm"
  or die "Can't write to CPP.pm!";
print CPP @lines;
close CPP;

WriteMakefile(
	      NAME => 'Inline::CPP',
	      VERSION_FROM => 'CPP.pm',
	      PREREQ_PM => { 
		Inline => 0.33,
	      },
	      clean => {FILES => '_Inline/ grammar/_Inline'},
	     );
