package Inline::CPP;

use strict;
require Inline;
require Inline::CPP::Grammar;
use Carp;
use Data::Dumper;
use Parse::RecDescent;
use FindBin;
use Cwd qw(cwd);

use vars qw(@ISA $VERSION);

@ISA = qw(Inline);
$VERSION = "0.10";

#============================================================================
# Register Inline::CPP as an Inline language module
#============================================================================
sub register {
    return {
	    language => 'CPP',
	    aliases => ['cpp', 'C++', 'Cplusplus', 'c++'],
	    type => 'compiled',
	   };
}

#============================================================================
# Validate the C++ config options
#============================================================================
sub validate {
    my $o = shift;

    $o->{CPP} = {};
    $o->{CPP}{XS} = {};
    $o->{CPP}{MAKEFILE} = {};
    $o->{CPP}{MAKEFILE}{CC} ||= 'g++';  # COMPILER
    $o->{CPP}{MAKEFILE}{LD} ||= 'g++';  # LINKER
    $o->{CPP}{AUTO_INCLUDE} ||= <<'END';
/* include this first, else g++ gets parse errors on some versions of perl */
#include <iostream.h>

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "INLINE.h"
END

    while (@_) {
	my ($key, $value) = (shift, shift);

	if ($key eq 'LIBS') {
	    add_list($o->{CPP}{MAKEFILE}, $key, $value, []);
	}
	elsif ($key eq 'INC') {
	    add_string($o->{CPP}{MAKEFILE}, $key, $value, '');
	}
	elsif ($key eq 'TYPEMAPS') {
	    add_list($o->{CPP}{MAKEFILE}, $key, $value, []);
	}
	elsif ($key eq 'MYEXTLIB') { 
	    add_string($o->{CPP}{MAKEFILE}, $key, $value, '');
	}
	elsif ($key eq 'CC') {
	    $o->{CPP}{MAKEFILE}{CC} = $value;
	}
	elsif ($key eq 'LD') {
	    $o->{CPP}{MAKEFILE}{LD} = $value;
	}
	elsif ($key eq 'AUTO_INCLUDE') {
	    add_list($o->{CPP}, $key, $value, '');
	}
	elsif ($key eq 'BOOT') {
	    add_text($o->{CPP}{XS}, $key, $value, '');
	}
	elsif ($key eq 'PREFIX') {
	    croak "Invalid value for 'PREFIX' option"
	      unless ($value =~ /^\w*$/ and
		      $value !~ /\n/);
	    $o->{CPP}{XS}{PREFIX} = $value;
	}
	elsif ($key eq 'MANGLE') {
	    $value = '' unless $value;
	    $value = 'Inline_' if $value eq '1';
	    croak "Invalid value for 'MANGLE' option"
	      unless ($value =~ /^\w*$/ and
		      $value !~ /\n/);
	    $o->{CPP}{XS}{MANGLE} = $value;
	    $o->{CPP}{XS}{PREFIX} = $value;
	}
	else {
	    croak "$key is not a valid config option for C++\n";
	}
	next;
    }
}

sub add_list {
    my ($ref, $key, $value, $default) = @_;
    $value = [$value] unless ref $value;
    croak usage_validate($key) unless ref($value) eq 'ARRAY';
    for (@$value) {
	if (defined $_) {
	    push @{$ref->{$key}}, $_;
	}
	else {
	    $ref->{$key} = $default;
	}
    }
}

sub add_string {
    my ($ref, $key, $value, $default) = @_;
    $value = [$value] unless ref $value;
    croak usage_validate($key) unless ref($value) eq 'ARRAY';
    for (@$value) {
	if (defined $_) {
	    $ref->{$key} .= ' ' . $_;
	}
	else {
	    $ref->{$key} = $default;
	}
    }
}

sub add_text {
    my ($ref, $key, $value, $default) = @_;
    $value = [$value] unless ref $value;
    croak usage_validate($key) unless ref($value) eq 'ARRAY';
    for (@$value) {
	if (defined $_) {
	    chomp;
	    $ref->{$key} .= $_ . "\n";
	}
	else {
	    $ref->{$key} = $default;
	}
    }
}

#==============================================================================
# Parse and compile C++ code
#==============================================================================
sub build {
    my $o = shift;
    $o->parse;
    $o->write_XS;
    $o->write_typemap;
    $o->write_Inline_headers;
    $o->write_Makefile_PL;
    $o->compile;
}

#============================================================================
# Print a small report if PRINT_INFO option is set
#============================================================================
sub info {
    my $o = shift;
    my $info = "";
    
    $o->parse unless $o->{parser};
    
    my $parser = $o->{parser};
    my $data = $parser->{data};    
    if (@{$o->{parser}->{data}->{functions}||[]}) {
	$info .= "The following public C++ functions have been bound to Perl:\n";
	for my $function (sort @{$data->{functions}}) {
	    next if $function =~ /::/;
	    my $return_type = $data->{function}->{$function}->{return_type}||"";
	    my @arg_names = @{$data->{function}->{$function}->{arg_names}||[]};
	    my @arg_types = @{$data->{function}->{$function}->{arg_types}||[]};
	    my @args = map {$_ . ' ' . shift @arg_names} @arg_types;
	    $info .= ("\t" .
		      ($return_type 
		       ? "$return_type $function(" . join(', ', @args) . ")"
		       : "$function(" . join(', ', @args) .  ")") .
		      "\n");
	}
	$info .= "\n";
    }
    else {
	$info .= "No public C++ functions have been bound to Perl.\n\n";
    }

    if (@{$o->{parser}->{data}->{classes}||[]}) {
        $info .= "The following C++ classes have been bound to Perl:\n";
	for my $class (sort @{$data->{classes}}) {
	    $info .= "\t$class\n";
	    for my $thing (sort @{$data->{class}->{$class}}) {
	    	my ($name, $scope, $type) = @{$thing}{qw(name scope thing)};
		next unless $scope eq 'public' and $type eq 'method';
		my $rtype = $thing->{rtype} || "";
		$info .= "\t\t$rtype" . ($rtype ? " " : "");
		$info .= $class . "::$name(";
		$info .= join ', ', (map "$_->{type} $_->{name}", 
				      @{$thing->{args}});
		$info .= ")\n";
	    }
	}
	$info .= "\n";
    }
    else {
        $info .= "No C++ classes have been successfully bound to Perl.\n\n";
    }
    return $info;
}

sub parse {
    my $o = shift;
    return if $o->{parser};
    my $grammar = Inline::CPP::Grammar::grammar()
      or croak "Can't find C++ grammar\n";
    $o->get_maps;
    $o->get_types;

    $::RD_HINT++;
    my $parser = $o->{parser} = Parse::RecDescent->new($grammar);

    $parser->code($o->{code})
      or croak "Bad C++ code passed to Inline at @{[caller(2)]}\n";
}

sub get_maps {
    my $o = shift;
    unshift @{$o->{CPP}{makefile}{TYPEMAPS}}, "$Config::Config{installprivlib}/ExtUtils/typemap";
    if (-f "$FindBin::Bin/typemap") {
	push @{$o->{CPP}{makefile}{TYPEMAPS}}, "$FindBin::Bin/typemap";
    }
}

#============================================================================
# This routine parses XS typemap files to get a list of valid types to create
# bindings to. This code is mostly hacked out of Larry Wall's xsubpp program.
#============================================================================
sub get_types {
    my (%type_kind, %proto_letter, %input_expr, %output_expr);
    my $o = shift;

    my $proto_re = "[" . quotemeta('\$%&*@;') . "]";
    foreach my $typemap (@{$o->{CPP}{makefile}{TYPEMAPS}}) {
	next unless -e $typemap;
	# skip directories, binary files etc.
	warn("Warning: ignoring non-text typemap file '$typemap'\n"), next 
	  unless -T $typemap;
	open(TYPEMAP, $typemap) 
	  or warn ("Warning: could not open typemap file '$typemap': $!\n"), next;
	my $mode = 'Typemap';
	my $junk = "";
	my $current = \$junk;
	while (<TYPEMAP>) {
	    next if /^\s*\#/;
	    my $line_no = $. + 1; 
	    if (/^INPUT\s*$/)   {$mode = 'Input';   $current = \$junk;  next}
	    if (/^OUTPUT\s*$/)  {$mode = 'Output';  $current = \$junk;  next}
	    if (/^TYPEMAP\s*$/) {$mode = 'Typemap'; $current = \$junk;  next}
	    if ($mode eq 'Typemap') {
		chomp;
		my $line = $_;
		TrimWhitespace($_);
		# skip blank lines and comment lines
		next if /^$/ or /^\#/;
		my ($type,$kind, $proto) = 
		  /^\s*(.*?\S)\s+(\S+)\s*($proto_re*)\s*$/ or
		    warn("Warning: File '$typemap' Line $. '$line' TYPEMAP entry needs 2 or 3 columns\n"), next;
		$type = TidyType($type);
		$type_kind{$type} = $kind;
		# prototype defaults to '$'
		$proto = "\$" unless $proto;
		warn("Warning: File '$typemap' Line $. '$line' Invalid prototype '$proto'\n") 
		  unless ValidProtoString($proto);
		$proto_letter{$type} = C_string($proto);
	    }
	    elsif (/^\s/) {
		$$current .= $_;
	    }
	    elsif ($mode eq 'Input') {
		s/\s+$//;
		$input_expr{$_} = '';
		$current = \$input_expr{$_};
	    }
	    else {
		s/\s+$//;
		$output_expr{$_} = '';
		$current = \$output_expr{$_};
	    }
	}
	close(TYPEMAP);
    }

    %Inline::CPP::valid_types = 
      map {($_, 1)}
    grep {defined $input_expr{$type_kind{$_}}}
    keys %type_kind;

    %Inline::CPP::valid_rtypes = 
      map {($_, 1)}
    grep {defined $output_expr{$type_kind{$_}}}
    keys %type_kind;
    $Inline::CPP::valid_rtypes{void} = 1;
}

sub ValidProtoString ($) {
    my $string = shift;
    my $proto_re = "[" . quotemeta('\$%&*@;') . "]";
    return ($string =~ /^$proto_re+$/) ? $string : 0;
}

sub TrimWhitespace {
    $_[0] =~ s/^\s+|\s+$//go;
}

sub TidyType {
    local $_ = shift;
    s|\s*(\*+)\s*|$1|g;
    s|(\*+)| $1 |g;
    s|\s+| |g;
    TrimWhitespace($_);
    $_;
}

sub C_string ($) {
    (my $string = shift) =~ s|\\|\\\\|g;
    $string;
}

sub write_XS {
    my $o = shift;
    my ($pkg, $module, $modfname) = @{$o}{qw(pkg module modfname)};
    
    $o->mkpath($o->{build_dir});
    open XS, "> $o->{build_dir}/$modfname.xs"
      or croak $!;
    
    print XS <<END;
$o->{CPP}{AUTO_INCLUDE}
$o->{code}

END

    my $parser = $o->{parser};
    my $data = $parser->{data};

    for my $class (@{$data->{classes}}) {

#      print "writing prototypes for class $class\n";

	my $thing = $pkg . "::$class";
	# Set up the proper namespace
	print XS <<END;
MODULE = $module     	PACKAGE = $thing

PROTOTYPES: DISABLE

END

	# Write out the class prototypes, renaming the constructor
	# and destructor to new() and DESTROY()
	
	for my $thing (@{$data->{class}->{$class}}) {
	    my ($name, $scope, $type) = @{$thing}{qw|name scope thing|};
	    #   print "name: $name\nscope: $scope\ntype: $type\n";
	    #   print "class: $class\n";
	    next unless ($scope eq 'public' and $type eq 'method');
	    if ($name eq $class) {
		#	       print "Constructor!\n";
		print XS $class, " *\n", $class, "::new";
	    } elsif ($name eq "~$class") {
		#	       print "Destructor!\n";
		print XS "void\n$class", "::DESTROY";
	    } else {
		#	       print "Method!\n";
		print XS "$thing->{rtype}\n$class", "::$thing->{name} ";
	    }
	    print XS ("(", 
		      (join ", ", map {$_->{name}} @{$thing->{args}}),
		      ")\n",
		     );
	    
	    for my $arg (@{$thing->{args}}) {
		print XS "\t$arg->{type}\t$arg->{name}\n";
	    }

	    print XS "\n";
	    
	}
    }

  print XS <<END;
MODULE = $module     	PACKAGE = $pkg

PROTOTYPES: DISABLE

END

    for my $function (@{$data->{functions}}) {
	next if $function =~ /::/;
	my $return_type = $data->{function}->{$function}->{return_type};
	my @arg_names = @{$data->{function}->{$function}->{arg_names}||[]};
	my @arg_types = @{$data->{function}->{$function}->{arg_types}||[]};
	
	print XS ("\n$return_type\n$function (",
		  join(', ', @arg_names), ")\n");
	
	for my $arg_name (@arg_names) {
	    my $arg_type = shift @arg_types;
	    last if $arg_type eq '...';
	    print XS "\t$arg_type\t$arg_name\n";
	}
	
	my $listargs = '';
	$listargs = pop @arg_names if (@arg_names and
				       $arg_names [-1] eq '...');
	my $arg_name_list = join(', ', @arg_names);
	
	if ($return_type eq 'void') {
	    print XS <<END;
    PREINIT:
    I32* temp;
    PPCODE:
    temp = PL_markstack_ptr++;
    $function($arg_name_list);
      if (PL_markstack_ptr != temp) {
	/* truly void, because dXSARGS not invoked */
	PL_markstack_ptr = temp;
	XSRETURN_UNDEF;
      }
      /* must have used dXSARGS; list context implied */
      return; /* assume stack size is correct */
END
	}
	elsif ($listargs) {
	    print XS <<END;
      PREINIT:
      I32* temp;
      CODE:
      temp = PL_markstack_ptr++;
      RETVAL = $function($arg_name_list);
      PL_markstack_ptr = temp;
      OUTPUT:
      RETVAL
END
	}
    }
    
    if (defined $o->{CPP}{XS}{BOOT} and
	$o->{CPP}{XS}{BOOT}) {
	print XS <<END;
BOOT:
$o->{CPP}{XS}{BOOT}
END
    }
    
    close XS;
}

sub write_typemap {
    my $o = shift;

    open TYPEMAP, "> $o->{build_dir}/typemap"
      or croak $!;
    print TYPEMAP "TYPEMAP\n";
#    map {print "$_ *\tO_OBJECT\n"} @{$o->{parser}{data}{classes}};
    for my $cls (@{$o->{parser}{data}{classes}}) {
	print TYPEMAP "$cls *\t\tO_OBJECT\n";
    }
    print TYPEMAP <<'END';

OUTPUT
O_OBJECT
   sv_setref_pv( $arg, CLASS, (void*)$var );

INPUT
O_OBJECT
   if( sv_isobject($arg) && (SvTYPE(SvRV($arg)) == SVt_PVMG))
     $var = ($type)SvIV((SV*)SvRV( $arg ));
   else {
       warn ( \"${Package}::$func_name() -- $var is not a blessed SV reference\" );
       XSRETURN_UNDEF;
   }

END
    close TYPEMAP;
}

#==============================================================================
# Generate the INLINE.h file.
#==============================================================================
sub write_Inline_headers {
    use strict;
    my $o = shift;

    open HEADER, "> $o->{build_dir}/INLINE.h"
      or croak;

    print HEADER <<'END';
#define Inline_Stack_Vars	dXSARGS
#define Inline_Stack_Items      items
#define Inline_Stack_Item(x)	ST(x)
#define Inline_Stack_Reset      sp = mark
#define Inline_Stack_Push(x)	XPUSHs(x)
#define Inline_Stack_Done	PUTBACK
#define Inline_Stack_Return(x)	XSRETURN(x)
#define Inline_Stack_Void       XSRETURN(0)

#define INLINE_STACK_VARS	Inline_Stack_Vars
#define INLINE_STACK_ITEMS	Inline_Stack_Items
#define INLINE_STACK_ITEM(x)	Inline_Stack_Item(x)
#define INLINE_STACK_RESET	Inline_Stack_Reset
#define INLINE_STACK_PUSH(x)    Inline_Stack_Push(x)
#define INLINE_STACK_DONE	Inline_Stack_Done
#define INLINE_STACK_RETURN(x)	Inline_Stack_Return(x)
#define INLINE_STACK_VOID	Inline_Stack_Void

#define inline_stack_vars	Inline_Stack_Vars
#define inline_stack_items	Inline_Stack_Items
#define inline_stack_item(x)	Inline_Stack_Item(x)
#define inline_stack_reset	Inline_Stack_Reset
#define inline_stack_push(x)    Inline_Stack_Push(x)
#define inline_stack_done	Inline_Stack_Done
#define inline_stack_return(x)	Inline_Stack_Return(x)
#define inline_stack_void	Inline_Stack_Void
END

    close HEADER;
}
#==============================================================================
# Generate the Makefile.PL
#==============================================================================
sub write_Makefile_PL {
    use strict;
    use Data::Dumper;

    my $o = shift;
    my %options = (
		   VERSION => '0.00',
		   %{$o->{CPP}{MAKEFILE}},
		   NAME => $o->{module},
		  );

    open MF, "> $o->{build_dir}/Makefile.PL"
      or croak;

    print MF <<END;
use ExtUtils::MakeMaker;
my %options = %\{
END

    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Indent = 1;
    print MF Data::Dumper::Dumper(\ %options);

    print MF <<END;
\};
WriteMakefile(\%options);
END
    close MF;
}

#==============================================================================
# Run the build process.
#==============================================================================
sub compile {
    use strict; 
    use Cwd;
    my ($o, $perl, $make, $cmd, $cwd);
    $o = shift;
     my ($module, $modpname, $modfname, $build_dir, $install_lib) = 
      @{$o}{qw(module modpname modfname build_dir install_lib)};

    -f ($perl = $Config::Config{perlpath})
      or croak "Can't locate your perl binary";
    ($make = $Config::Config{make})
      or croak "Can't locate your make binary";
    $cwd = &cwd;
    for $cmd ("$perl Makefile.PL > out.Makefile_PL 2>&1",
	      \ &fix_make,   # Fix Makefile problems
	      "$make > out.make 2>&1",
	      "$make install > out.make_install 2>&1",
	     ) {
	if (ref $cmd) {
	    $o->$cmd();
	}
	else {
	    chdir $build_dir;
	    system($cmd) and croak <<END;

A problem was encountered while attempting to compile and install your Inline
$o->{language} code. The command that failed was:
  $cmd

The build directory was:
$build_dir

To debug the problem, cd to the build directory, and inspect the output files.

END
	    chdir $cwd;
	}
    }

    if ($o->{config}{CLEAN_AFTER_BUILD} and 
	not $o->{config}{REPORTBUG}
       ) {
	$o->rmpath($o->{config}{BLIB_I}, $modpname);
	unlink "$install_lib/auto/$modpname/.packlist";
	unlink "$install_lib/auto/$modpname/$modfname.bs";
	unlink "$install_lib/auto/$modpname/$modfname.exp"; #MSWin32 VC++
	unlink "$install_lib/auto/$modpname/$modfname.lib"; #MSWin32 VC++
    }
}

#==============================================================================
# This routine fixes problems with the MakeMaker Makefile.
# Yes, it is a kludge, but it is a necessary one.
#
# ExtUtils::MakeMaker cannot be trusted. It has extremely flaky behaviour
# between releases and platforms. I have been burned several times.
#
# Doing this actually cleans up other code that was trying to guess what
# MM would do. This method will always work.
# And, at least this only needs to happen at build time, when we are taking 
# a performance hit anyway!
#==============================================================================
my %fixes = (
	     INSTALLSITEARCH => 'install_lib',
	     INSTALLDIRS => 'installdirs',
	    );

my %regex_fixes =
  (
   CCFLAGS => ['-Dbool=char', ''],
  );

sub fix_make {
    use strict;
    my (@lines, $fix);
    my $o = shift;

    $o->{installdirs} = 'site';

    open(MAKEFILE, "< $o->{build_dir}Makefile")
      or croak "Can't open Makefile for input: $!\n";
    @lines = <MAKEFILE>;
    close MAKEFILE;

    open(MAKEFILE, "> $o->{build_dir}Makefile")
      or croak "Can't open Makefile for output: $!\n";
    for (@lines) {
	if (/^(\w+)\s*=\s*\S*\s*$/ and
	    $fix = $fixes{$1}
	   ) {
	    print MAKEFILE "$1 = $o->{$fix}\n"
	}
	elsif (/^(\w+)\s*=\s*([^\n]*)$/ and
	       $fix = $regex_fixes{$1}
	      ) {
	    my $orig = $1;
	    my $val = $2;
	    $val =~ s|$fix->[0]|$fix->[1]|;
	    print MAKEFILE "$orig = $val\n";
	}
	else {
	    print MAKEFILE;
	}
    }
    close MAKEFILE;
}

1;

__END__
