package Inline::CPP;

use strict;
require Inline::C;
require Inline::CPP::grammar;
use Config;
use Carp;

use vars qw(@ISA $VERSION);

@ISA = qw(Inline::C);
$VERSION = "0.20";
my $TYPEMAP_KIND = $Inline::CPP::grammar::TYPEMAP_KIND;

#============================================================================
# Register Inline::CPP as an Inline language module
#============================================================================
sub register {
    my $suffix = ($^O eq 'aix') ? 'so' : $Config{so};
    return {
	    language => 'CPP',
	    aliases => ['cpp', 'C++', 'c++', 'Cplusplus', 'cplusplus'],
	    type => 'compiled',
	    suffix => $suffix,
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
#include <iostream.h>
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
#include <iostream.h>
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
	if ($key eq 'PRESERVE_ELLIPSIS') {
	    croak "Argument to PRESERVE_ELLIPSIS must be numeric" 
	      unless $value =~ /^\d+$/;
	    $o->{ILSM}{PRESERVE_ELLIPSIS} = $value;
	    next;
	}
	push @propagate, $key, $value;
    }

    $o->SUPER::validate(@propagate) if @propagate;
}

#============================================================================
# Print a small report if PRINT_INFO option is set
#============================================================================
sub info {
    my $o = shift;
    my $info = "";

    $o->parse unless $o->{parser};
    my $data = $o->{parser}{data};

    if (defined $o->{parser}{data}{classes}) {
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
	    for my $thing (sort { $a->{name} <=> $b->{name} } 
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
    if (defined $o->{parser}{data}{functions}) {
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

sub parse {
    my $o = shift;
    return if $o->{parser};
    my $grammar = Inline::CPP::grammar::grammar()
      or croak "Can't find C++ grammar\n";
    $o->get_maps;
    $o->get_types;

    $::RD_HINT++;
    require Parse::RecDescent;
    my $parser = $o->{parser} = Parse::RecDescent->new($grammar);
    $parser->{data}{typeconv} = $o->{typeconv};
    $parser->{ILSM} = $o->{ILSM}; # give parser access to config options

    $o->{ILSM}{code} = $o->filter(@{$o->{ILSM}{FILTERS}});
    Inline::Struct::parse($o) if $o->{STRUCT}{'.any'};
    $parser->code($o->{ILSM}{code})
      or croak "Bad C++ code passed to Inline at @{[caller(2)]}\n";
}

sub write_XS {
    my $o = shift;
    my ($pkg, $module, $modfname) = @{$o}{qw(pkg module modfname)};

    $o->mkpath($o->{build_dir});
    open XS, "> $o->{build_dir}/$modfname.xs"
      or croak $!;

    print XS <<END;
$o->{ILSM}{AUTO_INCLUDE}
$o->{STRUCT}{'.macros'}
$o->{ILSM}{code}
$o->{STRUCT}{'.xs'}
END

    my $data = $o->{parser}{data};

    warn("Warning: No Inline C++ functions or classes bound to Perl\n" .
	 "Check your C++ for Inline compatibility.\n\n")
      if ((not defined $data->{classes}) 
	  and (not defined $data->{functions})
	  and ($^W));

    for my $class (@{$data->{classes}}) {
	my $proper_pkg = $pkg . "::$class";
	# Set up the proper namespace
	print XS <<END;
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
	    print XS $o->generate_XS($thing, $name, $class);
	}

	# Provide default constructor and destructor:
	print XS <<END unless ($ctor or $abstract);
$class *
${class}::new()

END
	print XS <<END unless ($dtor or $abstract);
void
${class}::DESTROY()

END
    }

    my $prefix = (($o->{ILSM}{XS}{PREFIX}) ?
		  "PREFIX = $o->{ILSM}{XS}{PREFIX}" :
		  '');
    print XS <<END;
MODULE = $module     	PACKAGE = $pkg	$prefix

PROTOTYPES: DISABLE

END

    for my $function (@{$data->{functions}}) {
	next if $data->{function}{$function}{rtype} =~ 'static'; # special case
	print XS $o->generate_XS($data->{function}{$function}, $function);
    }

    if (defined $o->{ILSM}{XS}{BOOT} and
	$o->{ILSM}{XS}{BOOT}) {
	print XS <<END;
BOOT:
$o->{ILSM}{XS}{BOOT}
END
    }

    close XS;
    $o->write_typemap;
}

sub generate_XS {
    my $o = shift;
    my $thing = shift;
    my $name = shift;
    my $class = shift || "";

    my ($XS, $PREINIT, $CODE) = ("", "", "");
    my ($ctor, $dtor) = (0, 0);

    if ($name eq $class) {
	$XS .= $class . " *\n" . $class . "::new";
	$ctor = 1;
    }
    elsif ($name eq "~$class") {
	$XS .= "void\n$class" . "::DESTROY";
	$dtor = 1;
    }
    elsif ($class) {
	$XS .= "$thing->{rtype}\n$class" . "::$thing->{name}";
    }
    else {
	$XS .= "$thing->{rtype}\n$thing->{name}";
    }

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

    for my $arg (@args) {
	$XS .= "\t$arg->{type}\t$arg->{name}\n";
    }
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
	    my $rval = '';
	    $rval .= "new " if $ctor;
	    $rval .= "delete " if $dtor;
	    $rval .= "THIS->" if (length($class) and not ($ctor or $dtor));
	    $rval .= join '', "$name(", 
	      join (',', (map{$_->{name}}@args), @tmp), ")";
	    $CODE .= $o->const_cast($thing, $rval) . ";\n";
	    $CODE .= "\tbreak; /* case " . ($i+1) . " */\n";
	}
	$CODE .= "default:\n";
	$CODE .= "\tRETVAL = "
	  unless $void;
	my $rval = '';
	$rval .= "new " if $ctor;
	$rval .= "delete " if $dtor;
	$rval .= "THIS->" if ($class and not ($ctor or $dtor));
	$rval .= join '', "$name(", 
	  join (',', map{$_->{name}}@args), ")";
	$CODE .= $o->const_cast($thing, $rval) . ";\n";
	$CODE .= "} /* switch(items) */ \n";
    }
    elsif ($void) {
	$CODE .= "\t";
	$CODE .= "new " if $ctor;
	$CODE .= "delete " if $dtor;
	$CODE .= "THIS->" if ($class and not ($ctor or $dtor));
	$CODE .= join '', "$name(", 
	  join (',', map{$_->{name}}@args), ");\n";
    }
    elsif ($ellipsis or $thing->{rconst}) {
	$CODE .= "\t";
	$CODE .= "RETVAL = ";
	my $rval = '';
	$rval .= "new " if $ctor;
	$rval .= "delete " if $dtor;
	$rval .= "THIS->" if ($class and not ($ctor or $dtor));
	$rval .= join '', "$name(",
	  join (',', map{$_->{name}}@args), ")";
	$CODE .= $o->const_cast($thing, $rval) . ";\n";
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

sub const_cast {
    my $o = shift;
    my $thing = shift;
    my $value = shift;
    return ($thing->{rconst}
	    ? "const_cast<$thing->{rtype}>($value)"
	    : $value);
}

sub write_typemap {
    my $o = shift;
    my $filename = "$o->{build_dir}/CPP.map";
    my $type_kind = $o->{typeconv}{type_kind};
    my $typemap = "";
    $typemap .= $_ . "\t"x2 . $TYPEMAP_KIND . "\n" 
      for grep { $type_kind->{$_} eq $TYPEMAP_KIND } keys %$type_kind;
    return unless length $typemap;
    open TYPEMAP, "> $filename"
      or croak $!;
    print TYPEMAP <<END;
TYPEMAP
$typemap
OUTPUT
$TYPEMAP_KIND
$o->{typeconv}{output_expr}{$TYPEMAP_KIND}
INPUT
$TYPEMAP_KIND
$o->{typeconv}{input_expr}{$TYPEMAP_KIND}
END
    close TYPEMAP;
    $o->validate( TYPEMAPS => $filename );
}

# Generate type conversion code: perl2c or c2perl.
sub typeconv {
    my $o = shift;
    my $var = shift;
    my $arg = shift;
    my $type = shift;
    my $dir = shift;
    my $preproc = shift;
    my $tkind = $o->{typeconv}{type_kind}{$type};
    my $ret =
      eval qq{qq{$o->{typeconv}{$dir}{$tkind}}};
    chomp $ret;
    $ret =~ s/\n/\\\n/g if $preproc;
    return $ret;
}

1;

__END__
