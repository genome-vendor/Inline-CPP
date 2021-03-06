use ExtUtils::MakeMaker;
use Config;

my %PREREQ_PM = (
	Inline => '0.42',
	'Inline::C' => '0.42',
);
#============================================================================
# We'll do our own prerequisite checking, since MakeMaker does it
# in a way that always fails: 'use Inline::C 0.33' will never work.
#============================================================================
for (sort keys %PREREQ_PM) {
    eval "require $_";
    warn "Warning: prerequisite $_ version $PREREQ_PM{$_} not found"
      if $@ or ${"${_}::VERSION"} < $PREREQ_PM{$_};
}

#============================================================================
# Make an intelligent guess about what compiler to use
#============================================================================
my $cc_guess;
my $libs_guess;
if ($Config{gccversion} and $Config{cc} =~ m#\bgcc\b[^/]*$#) {
  ($cc_guess = $Config{cc}) =~ s[\bgcc\b([^/]*)$(?:)][g\+\+$1] ;
    $libs_guess = '-lstdc++';
}
elsif ($Config{osname} =~ /^MSWin/) {
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
elsif ($Config{osname} eq 'solaris' or $Config{osname} eq 'SunOS') {
    if ($Config{cc} eq 'gcc') {
        $cc_guess = 'g++';
	$libs_guess = '-lstdc++';
    }
    else {
	$cc_guess = 'CC';
	$libs_guess ='-lCrun';
    }
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

my $std_iostream = prompt("Which default you want to use for STD_IOSTREAM ?",
		  'true' );

# Apply the defaults:
open CPP, "CPP.pm";
my @lines = <CPP>;
close CPP;

for (@lines) {
    s|\@COMPILER|$cpp_compiler| if m|\# default compiler|;
    s|\@DEFAULTLIBS|$libs| if m|\# default libs|;
    s|\@STD_IOSTREAM|$std_iostream| if m|\# default iostream|;
}

open CPP, ">lib/Inline/CPP.pm"
  or die "Can't write to lib/Inline/CPP.pm!";
print CPP @lines;
close CPP;

WriteMakefile(
	      NAME => 'Inline::CPP',
	      VERSION_FROM => 'CPP.pm',
	      PREREQ_PM => {
		  'Inline::C' => '0.42',
	      },
	      clean => {FILES => '_Inline/ grammar/_Inline'},
	     );
