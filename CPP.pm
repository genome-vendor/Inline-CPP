package Inline::CPP;

use strict;
require Inline::C;
require Inline::CPP::grammar;
use Carp;

use vars qw(@ISA $VERSION);

@ISA = qw(Inline::C);
$VERSION = "0.23";
my $TYPEMAP_KIND = $Inline::CPP::grammar::TYPEMAP_KIND;

#============================================================================
# Register Inline::CPP as an Inline language module
#============================================================================
sub register {
    use Config;
    return {
	    language => 'CPP',
	    aliases => ['cpp', 'C++', 'c++', 'Cplusplus', 'cplusplus'],
	    type => 'compiled',
	    suffix => $Config{dlext},
	   };
}

#============================================================================
# Validate the C++ config options: Now mostly done in Inline::C
#============================================================================
sub validate {
    my $o = shift;
    $o->{ILSM}{MAKEFILE}{CC} ||= '@COMPILER'; # default compiler
    $o->{ILSM}{MAKEFILE}{LIBS} ||= ['@DEFAULTLIBS']; # default libs

    # I haven't traced it out yet, but $o->{STRUCT} gets set before getting
    # properly set from Inline::C's validate().
    $o->{STRUCT} ||= {
		      '.macros' => '',
		      '.xs' => '',
		      '.any' => 0, 
		      '.all' => 0,
		     };
    $o->{ILSM}{AUTO_INCLUDE} ||= <<END;
#ifndef bool
#include <%iostream%>
#endif
#ifdef __CYGWIN__
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "INLINE.h"
#ifdef __CYGWIN__
}
#endif
#ifdef bool
#undef bool
#include <%iostream%>
#endif
END
    $o->{ILSM}{PRESERVE_ELLIPSIS} = 0 
      unless defined $o->{ILSM}{PRESERVE_ELLIPSIS};

    # Filter out the parameters we treat differently than Inline::C
    my @propagate;
    while(@_) {
	my ($key, $value) = (shift, shift);
	if ($key eq 'LIBS') {
	    $value = [$value] unless ref $value eq 'ARRAY';
	    my $num = scalar @{$o->{ILSM}{MAKEFILE}{LIBS}} - 1;
	    $o->{ILSM}{MAKEFILE}{LIBS}[$num] .= ' ' . $_
	      for (@$value);
	    next;
	}
	if ($key eq 'ALTLIBS') {
	    $value = [$value] unless ref $value eq 'ARRAY';
	    push @{$o->{ILSM}{MAKEFILE}{LIBS}}, '';
	    my $num = scalar @{$o->{ILSM}{MAKEFILE}{LIBS}} - 1;
	    $o->{ILSM}{MAKEFILE}{LIBS}[$num] .= ' ' . $_
	      for (@$value);
	    next;
	}
	if ($key eq 'PRESERVE_ELLIPSIS' or 
	    $key eq 'STD_IOSTREAM') {
	    croak "Argument to $key must be 0 or 1" 
	      unless $value == 0 or $value == 1;
	    $o->{ILSM}{$key} = $value;
	    next;
	}
	push @propagate, $key, $value;
    }

    # Replace %iostream% with the correct iostream library
    my $iostream = "iostream";
    $iostream .= ".h" unless (defined $o->{ILSM}{STD_IOSTREAM} and 
			      $o->{ILSM}{STD_IOSTREAM});
    $o->{ILSM}{AUTO_INCLUDE} =~ s|%iostream%|$iostream|g;

    # Forward all unknown requests up to Inline::C
    $o->SUPER::validate(@propagate) if @propagate;
}

#============================================================================
# Print a small report if PRINT_INFO option is set
#============================================================================
sub info {
    my $o = shift;
    my $info = "";

    $o->parse unless $o->{ILSM}{parser};
    my $data = $o->{ILSM}{parser}{data};

    if (defined $o->{ILSM}{parser}{data}{classes}) {
	$info .= "The following C++ classes have been bound to Perl:\n";
	for my $class (sort @{$data->{classes}}) {
	    my @parents = grep { $_->{thing} eq 'inherits' }
	      @{$data->{class}{$class}};
	    $info .= "\tclass $class";
	    $info .= (" : " 
		      . join (', ', 
			      map { $_->{scope} . " " . $_->{name} } @parents)
		     ) if @parents;
	    $info .= " {\n";
	    for my $thing (sort { $a->{name} cmp $b->{name} } 
			   @{$data->{class}{$class}}) {
		my ($name, $scope, $type) = @{$thing}{qw(name scope thing)};
		next unless $scope eq 'public' and $type eq 'method';
		my $rtype = $thing->{rtype} || "";
		$info .= "\t\t$rtype" . ($rtype ? " " : "");
		$info .= $class . "::$name(";
		my @args = grep { $_->{name} ne '...' } @{$thing->{args}};
		my $ellipsis = (scalar @{$thing->{args}} - scalar @args) != 0;
		$info .= join ', ', (map "$_->{type} $_->{name}", @args), 
		  $ellipsis ? "..." : ();
		$info .= ");\n";
	    }
	    $info .= "\t};\n"
	}
	$info .= "\n";
    }
    else {
        $info .= "No C++ classes have been successfully bound to Perl.\n\n";
    }
    if (defined $o->{ILSM}{parser}{data}{functions}) {
	$info .= "The following C++ functions have been bound to Perl:\n";
	for my $function (sort @{$data->{functions}}) {
	    my $func = $data->{function}{$function};
	    $info .= "\t" . $func->{rtype} . " ";
	    $info .= $func->{name} . "(";
	    my @args = grep { $_->{name} ne '...' } @{$func->{args}};
	    my $ellipsis = (scalar @{$func->{args}} - scalar @args) != 0;
	    $info .= join ', ', (map "$_->{type} $_->{name}", @args), 
	      $ellipsis ? "..." : ();
	    $info .= ");\n";
	}
	$info .= "\n";
    }
    else {
	$info .= "No C++ functions have been bound to Perl.\n\n";
    }
    $info .= Inline::Struct::info($o) if $o->{STRUCT}{'.any'};
    return $info;
}

#============================================================================
# Generate a C++ parser
#============================================================================
sub get_parser {
    my $o = shift;
    my $grammar = Inline::CPP::grammar::grammar()
      or croak "Can't find C++ grammar\n";
    $::RD_HINT++;
    require Parse::RecDescent;
    my $parser = Parse::RecDescent->new($grammar);
    $parser->{data}{typeconv} = $o->{ILSM}{typeconv};
    $parser->{ILSM} = $o->{ILSM}; # give parser access to config options
    return $parser;
}

#============================================================================
# Intercept xs_generate and create the typemap file
#============================================================================
sub xs_generate {
    my $o = shift;
    $o->write_typemap;
    $o->SUPER::xs_generate;
}

#============================================================================
# Return bindings for functions and classes
#============================================================================
sub xs_bindings {
    my $o = shift;
    my ($pkg, $module) = @{$o->{API}}{qw(pkg module modfname)};
    my $data = $o->{ILSM}{parser}{data};
    my $XS = '';

    warn("Warning: No Inline C++ functions or classes bound to Perl\n" .
	 "Check your C++ for Inline compatibility.\n\n")
      if ((not defined $data->{classes}) 
	  and (not defined $data->{functions})
	  and ($^W));

    for my $class (@{$data->{classes}}) {
	my $proper_pkg = $pkg . "::$class";
	# Set up the proper namespace
	$XS .= <<END;
MODULE = $module     	PACKAGE = $proper_pkg

PROTOTYPES: DISABLE

END

	my ($ctor, $dtor, $abstract) = (0, 0, 0);
	for my $thing (@{$data->{class}{$class}}) {
	    my ($name, $scope, $type) = @{$thing}{qw|name scope thing|};

	    # Let Perl handle inheritance
	    if ($type eq 'inherits' and $scope eq 'public') {
		$o->{ILSM}{XS}{BOOT} ||= '';
		my $ISA_name = "${pkg}::${class}::ISA";
		my $parent = "${pkg}::${name}";
		$o->{ILSM}{XS}{BOOT} .= <<END;
{
#ifndef get_av
    AV *isa = perl_get_av("$ISA_name", 1);
#else
    AV *isa = get_av("$ISA_name", 1);
#endif
    av_push(isa, newSVpv("$parent", 0));
}
END
	    }

	    # Get/set methods will go here:

	    # Cases we skip:
            $abstract ||= ($type eq 'method' and $thing->{abstract});
	    next if ($type eq 'method' and $thing->{abstract});
	    next unless ($scope eq 'public' and $type eq 'method');

	    # generate an XS wrapper
	    $ctor ||= ($name eq $class);
	    $dtor ||= ($name eq "~$class");
	    $XS .= $o->wrap($thing, $name, $class);
	}

	# Provide default constructor and destructor:
	$XS .= <<END unless ($ctor or $abstract);
$class *
${class}::new()

END
	$XS .= <<END unless ($dtor or $abstract);
void
${class}::DESTROY()

END
    }

    my $prefix = (($o->{ILSM}{XS}{PREFIX}) ?
		  "PREFIX = $o->{ILSM}{XS}{PREFIX}" :
		  '');
    $XS .= <<END;
MODULE = $module     	PACKAGE = $pkg	$prefix

PROTOTYPES: DISABLE

END

    for my $function (@{$data->{functions}}) {
	next if $data->{function}{$function}{rtype} =~ 'static'; # special case
	$XS .= $o->wrap($data->{function}{$function}, $function);
    }

    return $XS;
}

#============================================================================
# Generate an XS wrapper around anything: a C++ method or function
#============================================================================
sub wrap {
    my $o = shift;
    my $thing = shift;
    my $name = shift;
    my $class = shift || "";

    my ($XS, $PREINIT, $CODE) = ("", "", "");
    my ($ctor, $dtor) = (0, 0);

    if ($name eq $class) { 	# ctor
	$XS .= $class . " *\n" . $class . "::new";
	$ctor = 1;
    }
    elsif ($name eq "~$class") { # dtor
	$XS .= "void\n$class" . "::DESTROY";
	$dtor = 1;
    }
    elsif ($class) {		# method
	$XS .= "$thing->{rtype}\n$class" . "::$thing->{name}";
    }
    else {			# function
	$XS .= "$thing->{rtype}\n$thing->{name}";
    }

    # Filter out optional subroutine arguments
    my (@args, @opts, $ellipsis, $void);
    $_->{optional} ? push@opts,$_ : push@args,$_ for @{$thing->{args}};
    $ellipsis = pop @args if (@args and $args[-1]->{name} eq '...');
    $void = ($thing->{rtype} and $thing->{rtype} eq 'void');
    $XS .= join '', 
	     ("(", 
	      (join ", ", (map {$_->{name}} @args), 
	         (scalar @opts or $ellipsis) ? '...' : ()),
	      ")\n",
	     );

    # Declare the non-optional arguments for XS type-checking
    $XS .= "\t$_->{type}\t$_->{name}\n" for @args;

    # Wrap "complicated" subs in stack-checking code
    if ($void or $ellipsis) {
	$PREINIT .= "\tI32 *\t__temp_markstack_ptr;\n";
	$CODE .= "\t__temp_markstack_ptr = PL_markstack_ptr++;\n";
    }

    if (@opts) {
	$PREINIT .= "\t$_->{type}\t$_->{name};\n" for @opts;
	$CODE .= "switch(items" . ($class ? '-1' : '') . ") {\n";

	my $offset = scalar @args; # which is the first optional?
	my $total = $offset + scalar @opts;
	for (my $i=$offset; $i<$total; $i++) {
	    $CODE .= "case " . ($i+1) . ":\n";
	    my @tmp;
	    for (my $j=$offset; $j<=$i; $j++) {
		my $targ = $opts[$j-$offset]->{name};
		my $type = $opts[$j-$offset]->{type};
		my $src  = "ST($j)";
		$CODE .= $o->typeconv($targ,$src,$type,'input_expr')
		  . ";\n";
		push @tmp, $targ;
	    }
	    $CODE .= "\t";
	    $CODE .= "RETVAL = "
	      unless $void;
	    call_or_instantiate(\$CODE, $name, $ctor, $dtor, $class, 
				$thing->{rconst}, $thing->{rtype},
				(map { $_->{name} } @args), @tmp);
	    $CODE .= "\tbreak; /* case " . ($i+1) . " */\n";
	}
	$CODE .= "default:\n";
	$CODE .= "\tRETVAL = "
	  unless $void;
	call_or_instantiate(\$CODE, $name, $ctor, $dtor, $class, 
			    $thing->{rconst}, $thing->{rtype},
			    map { $_->{name} } @args);
	$CODE .= "} /* switch(items) */ \n";
    }
    elsif ($void) {
	$CODE .= "\t";
	call_or_instantiate(\$CODE, $name, $ctor, $dtor, $class, 0, '', 
			    map { $_->{name} } @args);
    }
    elsif ($ellipsis or $thing->{rconst}) {
	$CODE .= "\t";
	$CODE .= "RETVAL = ";
	call_or_instantiate(\$CODE, $name, $ctor, $dtor, $class, 
			    $thing->{rconst}, $thing->{rtype},
			    map { $_->{name} } @args);
    }
    if ($void) {
	$CODE .= <<'END';
        if (PL_markstack_ptr != __temp_markstack_ptr) {
          /* truly void, because dXSARGS not invoked */
          PL_markstack_ptr = __temp_markstack_ptr;
          XSRETURN_EMPTY; /* return empty stack */
        }
        /* must have used dXSARGS; list context implied */
        return; /* assume stack size is correct */
END
    }
    elsif ($ellipsis) {
	$CODE .= "\tPL_markstack_ptr = __temp_markstack_ptr;\n";
    }

    # The actual function:
    $XS .= "PREINIT:\n$PREINIT" if length $PREINIT;
    $XS .= "PP" if $void;
    $XS .= "CODE:\n$CODE" if length $CODE;
    $XS .= "OUTPUT:\nRETVAL\n" 
      if (length $CODE and not $void);
    $XS .= "\n";
    return $XS;
}

sub call_or_instantiate {
    my $text_ref = shift;
    my ($name, $ctor, $dtor, $class, $const, $type, @args) = @_;

    # Create an rvalue (which might be const-casted later).
    my $rval = '';
    $rval .= "new " if $ctor;
    $rval .= "delete " if $dtor;
    $rval .= "THIS->" if ($class and not ($ctor or $dtor));
    $rval .= "$name(" . join (',', @args) . ")";

    $$text_ref .= const_cast($rval, $const, $type);
    $$text_ref .= ";\n"; # this is a convenience
}

sub const_cast {
    my $value = shift;
    my $const = shift;
    my $type  = shift;
    return $value unless $const and $type =~ /\*|\&/;
    return "const_cast<$type>($value)";
}

sub write_typemap {
    my $o = shift;
    my $filename = "$o->{API}{build_dir}/CPP.map";
    my $type_kind = $o->{ILSM}{typeconv}{type_kind};
    my $typemap = "";
    $typemap .= $_ . "\t"x2 . $TYPEMAP_KIND . "\n" 
      for grep { $type_kind->{$_} eq $TYPEMAP_KIND } keys %$type_kind;
    return unless length $typemap;
    open TYPEMAP, "> $filename"
      or croak "Error: Can't write to $filename: $!";
    print TYPEMAP <<END;
TYPEMAP
$typemap
OUTPUT
$TYPEMAP_KIND
$o->{ILSM}{typeconv}{output_expr}{$TYPEMAP_KIND}
INPUT
$TYPEMAP_KIND
$o->{ILSM}{typeconv}{input_expr}{$TYPEMAP_KIND}
END
    close TYPEMAP;
    $o->validate(TYPEMAPS => $filename);
}

# Generate type conversion code: perl2c or c2perl.
sub typeconv {
    my $o = shift;
    my $var = shift;
    my $arg = shift;
    my $type = shift;
    my $dir = shift;
    my $preproc = shift;
    my $tkind = $o->{ILSM}{typeconv}{type_kind}{$type};
    my $ret =
      eval qq{qq{$o->{ILSM}{typeconv}{$dir}{$tkind}}};
    chomp $ret;
    $ret =~ s/\n/\\\n/g if $preproc;
    return $ret;
}

1;

__END__
