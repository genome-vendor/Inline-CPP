package Inline::CPP::grammar;

use strict;
use vars qw($TYPEMAP_KIND $VERSION);
$VERSION = '0.23';

#============================================================================
# Regular expressions to match code blocks, numbers, strings, parenthesized
# expressions, function calls, and macros. The more complex regexes are only
# implemented in 5.6.0 and above, so they're in eval-blocks.
#
# These are all adapted from the output of Damian Conway's excellent 
# Regexp::Common module. In future, Inline::CPP may depend directly on it,
# but for now I'll just duplicate the code.
use vars qw($code_block $string $number $parens $funccall);
#============================================================================
eval <<'END'; # $RE{balanced}{-parens=>q|{}()[]"'|}
$code_block = qr'(?-xism:(?-xism:(?:[{](?:(?>[^][)(}{]+)|(??{$Inline::CPP::grammar::code_block}))*[}]))|(?-xism:(?-xism:(?:[(](?:(?>[^][)(}{]+)|(??{$Inline::CPP::grammar::code_block}))*[)]))|(?-xism:(?-xism:(?:[[](?:(?>[^][)(}{]+)|(??{$Inline::CPP::grammar::code_block}))*[]]))|(?-xism:(?!)))))';
END
$code_block = qr'{[^}]*}' if $@; # For the stragglers: here's a lame regexp.

eval <<'END'; # $RE{balanced}{-parens=>q|()"'|}
$parens = qr'(?-xism:(?-xism:(?:[(](?:(?>[^)(]+)|(??{$Inline::CPP::grammar::parens}))*[)]))|(?-xism:(?!)))';
END
$parens = qr'\([^)]*\)' if $@; # For the stragglers: here's another

# $RE{quoted}
$string = qr'(?:(?:\")(?:[^\\\"]*(?:\\.[^\\\"]*)*)(?:\")|(?:\')(?:[^\\\']*(?:\\.[^\\\']*)*)(?:\')|(?:\`)(?:[^\\\`]*(?:\\.[^\\\`]*)*)(?:\`))';

# $RE{num}{real}|$RE{num}{real}{-base=>16}|$RE{num}{int}
$number = qr'(?:(?i)(?:[+-]?)(?:(?=[0123456789]|[.])(?:[0123456789]*)(?:(?:[.])(?:[0123456789]{0,}))?)(?:(?:[E])(?:(?:[+-]?)(?:[0123456789]+))|))|(?:(?i)(?:[+-]?)(?:(?=[0123456789ABCDEF]|[.])(?:[0123456789ABCDEF]*)(?:(?:[.])(?:[0123456789ABCDEF]{0,}))?)(?:(?:[G])(?:(?:[+-]?)(?:[0123456789ABCDEF]+))|))|(?:(?:[+-]?)(?:\d+))';
$funccall = qr/[_a-zA-Z][_a-zA-Z0-9]*(?:$Inline::CPP::grammar::parens)?/;

#============================================================================
# Inline::CPP's grammar
#============================================================================
sub grammar {
   <<'END';

{ use Data::Dumper; }

code: part(s) {1}

part: comment
    | class_def
      {
#         print "Found a class: $item[1]->[0]\n";
         my $class = $item[1]->[0];
         my @parts;
         for my $part (@{$item[1]->[1]}) { push @parts, @$_ for @$part }
         push @{$thisparser->{data}{classes}}, $class
           unless defined $thisparser->{data}{class}{$class};
         $thisparser->{data}{class}{$class} = \@parts;
#	 print "Class:\n", Dumper \@parts;
	 Inline::CPP::grammar::typemap($thisparser, $class);
	 1;
      }
    | function_def
      {
#         print "found a function: $item[1]->{name}\n";
         my $name = $item[1]->{name};
	 my $i=0;
	 for my $arg (@{$item[1]->{args}}) {
	    $arg->{name} = 'dummy' . ++$i unless defined $arg->{name};
	 }
	 Inline::CPP::grammar::strip_ellipsis($thisparser,
					      $item[1]->{args});
	 push @{$thisparser->{data}{functions}}, $name
           unless defined $thisparser->{data}{function}{$name};
	 $thisparser->{data}{function}{$name} = $item[1];
#	 print Dumper $item[1];
	 1;
      }
    | all

class_def: class IDENTIFIER '{' class_part(s) '}' ';' 
           { 
#              print "Found a class definition: $item[2]\n";
 	      [@item[2,4]]
	   }
	 | class IDENTIFIER ':' <leftop: inherit ',' inherit> '{' class_part(s) '}' ';'
	   {
#	       print "Found a class definition: $item[2]\n";
	      push @{$item[6]}, [$item[4]]; 
	      [@item[2,6]]
	   }

inherit: scope IDENTIFIER 
	{ {thing => 'inherits', name => $item[2], scope => $item[1]} }

class_part: comment { [ {thing => 'comment'} ] }
	  | scope ':' class_decl(s)
            {
	      for my $part (@{$item[3]}) {
                  $_->{scope} = $item[1] for @$part;
	      }
	      $item[3]
	    }
	  | class_decl(s)
            {
	      for my $part (@{$item[1]}) {
                  $_->{scope} = $thisparser->{data}{defaultscope} 
		    for @$part;
	      }
	      $item[1]
	    }

class_decl: comment { [{thing => 'comment'}] }
          | method_def
	    {
              $item[1]->{thing} = 'method';
#	      print "class_decl found a method: $item[1]->{name}\n";
	      my $i=0;
	      for my $arg (@{$item[1]->{args}}) {
		$arg->{name} = 'dummy' . ++$i unless defined $arg->{name};
	      }
	      Inline::CPP::grammar::strip_ellipsis($thisparser,
						   $item[1]->{args});
	      [$item[1]];
	    }
          | member_def
	    {
#	      print "class_decl found one or more members:\n", Dumper(\@item);
              $_->{thing} = 'member' for @{$item[1]};
	      $item[1];
	    }

function_def: rtype IDENTIFIER '(' <leftop: arg ',' arg>(s?) ')' ';'
              {
                {rtype => $item[1], name => $item[2], args => $item[4]}
              }
            | rtype IDENTIFIER '(' <leftop: arg ',' arg>(s?) ')' code_block
              {
                {rtype => $item[1], name => $item[2], args => $item[4]}
              }

method_def: IDENTIFIER '(' <leftop: arg ',' arg>(s?) ')' method_imp
            {
#	      print "con-/de-structor found: $item[1]\n";
              {name => $item[1], args => $item[3], abstract => ${$item[5]}};
            }
          | rtype IDENTIFIER '(' <leftop: arg ',' arg>(s?) ')' method_imp
            {
#	      print "method found: $item[2]\n";
	      $return = 
                {name => $item[2], rtype => $item[1], args => $item[4], 
	         abstract => ${$item[6]},
                 rconst => $thisparser->{data}{smod}{const},
                };
	      $thisparser->{data}{smod}{const} = 0; 
            }

# By adding smod, we allow 'const' member functions. This would also bind to
# incorrect C++ with the word 'static' after the argument list, but we don't
# care at all because such code would never be compiled successfully.

# By adding init, we allow constructors to initialize references. Again, we'll
# allow them anywhere, but our goal is not to enforce c++ standards -- that's
# the compiler's job.
method_imp: smod(?) ';' { \0 }
          | smod(?) initlist(?) code_block { \0 }
          | smod(?) '=' '0' ';' { \1 }
          | smod(?) '=' '0' code_block { \0 }

initlist: ':' <leftop: subexpr ',' subexpr>

member_def: anytype <leftop: var ',' var> ';'
            { 
	      my @retval;
	      for my $def (@{$item[2]}) {
	          my $type = join '', $item[1], @{$def->[0]};
		  my $name = $def->[1];
#	          print "member found: type=$type, name=$name\n";
		  push @retval, { name => $name, type => $type };
	      }
	      \@retval;
            }

var: star(s?) IDENTIFIER '=' expr { [@item[1,2]] }
   | star(s?) IDENTIFIER          { [@item[1,2]] }

arg: type IDENTIFIER '=' expr
     { 
#       print "argument $item[2] found\n";
#       print "expression: $item[4]\n";
	{type => $item[1], name => $item[2], optional => 1, 
	 offset => $thisoffset} 
     }
   | type IDENTIFIER
     { 
#       print "argument $item[2] found\n";
       {type => $item[1], name => $item[2], offset => $thisoffset}
     }
   | type { {type => $item[1]} }
   | '...' 
     { {name => '...', type => '...', offset => $thisoffset} }

IDENTIFIER: /[~_a-z]\w*/i
	    {
#	      print "IDENTIFIER: $item[1]\n";
	      $item[1]
	    }

# Parse::RecDescent is retarded in this one case: if a subrule fails, it
# gives up the entire rule. This is a stupid way to get around that. 
rtype: rtype2 | rtype1
rtype1: TYPE star(s?)
        {
         $return = $item[1];
         $return .= join '',' ',@{$item[2]} if @{$item[2]};
#	 print "rtype1: $return\n";
         return undef 
           unless(defined$thisparser->{data}{typeconv}{valid_rtypes}{$return});
        }
rtype2: modifier(s) TYPE star(s?)
	{
         $return = $item[2];
         $return = join ' ',grep{$_}@{$item[1]},$return
           if @{$item[1]};
         $return .= join '',' ',@{$item[3]} if @{$item[3]};
#	 print "rtype2: $return\n";
         return undef
           unless(defined$thisparser->{data}{typeconv}{valid_rtypes}{$return});
	 $return = 'static ' . $return
	   if $thisparser->{data}{smod}{static};
         $thisparser->{data}{smod}{static} = 0;
	}

type: type2 | type1
type1: TYPE star(s?)
        {
         $return = $item[1];
         $return .= join '',' ',@{$item[2]} if @{$item[2]};
         return undef
           unless(defined$thisparser->{data}{typeconv}{valid_types}{$return});
        }
type2: modifier(s) TYPE star(s?)
	{
         $return = $item[2];
         $return = join ' ',grep{$_}@{$item[1]},$return if @{$item[1]};
         $return .= join '',' ',@{$item[3]} if @{$item[3]};
         return undef
           unless(defined$thisparser->{data}{typeconv}{valid_types}{$return});
	}

anytype: anytype2 | anytype1
anytype1: TYPE star(s?)
         {
           $return = $item[1];
           $return .= join '',' ',@{$item[2]} if @{$item[2]};
         }
anytype2: modifier(s) TYPE star(s?)
         {
           $return = $item[2];
           $return = join ' ',grep{$_}@{$item[1]},$return if @{$item[1]};
           $return .= join '',' ',@{$item[3]} if @{$item[3]};
         }

comment: m{\s* // [^\n]* \n }x
       | m{\s* /\* (?:[^*]+|\*(?!/))* \*/  ([ \t]*)? }x

# long and short aren't recognized as modifiers because they break when used
# as regular types. Another Parse::RecDescent problem is greedy matching; I
# need tmodifier to "give back" long or short in cases where keeping them would 
# cause the modifier rule to fail. One side-effect is 'long long' can never
# be parsed correctly here.
modifier: tmod
        | smod { ++$thisparser->{data}{smod}{$item[1]}; ''}
	| nmod { '' }
tmod: 'unsigned' # | 'long' | 'short'
smod: 'const' | 'static'
nmod: 'extern' | 'virtual' | 'mutable' | 'volatile' | 'inline'

scope: 'public' | 'private' | 'protected'

class: 'class' { $thisparser->{data}{defaultscope} = 'private'; $item[1] }
     | 'struct' { $thisparser->{data}{defaultscope} = 'public'; $item[1] }

star: '*' | '&'

code_block: /$Inline::CPP::grammar::code_block/

# Consume expressions
expr: <leftop: subexpr OP subexpr> { 
	my $o = join '', @{$item[1]}; 
#	print "expr: $o\n";
	$o;
}
subexpr: /$Inline::CPP::grammar::funccall/ # Matches a macro, too
       | /$Inline::CPP::grammar::string/
       | /$Inline::CPP::grammar::number/
       | UOP subexpr
OP: '+' | '-' | '*' | '/' | '^' | '&' | '|' | '%' | '||' | '&&'
UOP: '~' | '!' | '-' | '*' | '&'

TYPE: /\w+/

all: /.*/

END

}

#============================================================================
# Generate typemap code for the classes and structs we bind to. This allows
# functions declared after a class to return or accept class objects as 
# parameters.
#============================================================================
$TYPEMAP_KIND = 'O_Inline_CPP_Class';
sub typemap {
    my $parser = shift;
    my $typename = shift;

#    print "Inline::CPP::grammar::typemap(): typename=$typename\n";

    my ($TYPEMAP, $INPUT, $OUTPUT);
    $TYPEMAP = "$typename *\t\t$TYPEMAP_KIND\n";
    $INPUT = <<END;
    if (sv_isobject(\$arg) && (SvTYPE(SvRV(\$arg)) == SVt_PVMG)) {
        \$var = (\$type)SvIV((SV*)SvRV( \$arg ));
    }
    else {
        warn ( \\"\${Package}::\$func_name() -- \$var is not a blessed reference\\" );
        XSRETURN_UNDEF;
    }
END
    $OUTPUT = <<END;
    sv_setref_pv( \$arg, CLASS, (void*)\$var );
END

    my $ctypename = $typename . " *";
    $parser->{data}{typeconv}{input_expr}{$TYPEMAP_KIND} ||= $INPUT;
    $parser->{data}{typeconv}{output_expr}{$TYPEMAP_KIND} ||= $OUTPUT;
    $parser->{data}{typeconv}{type_kind}{$ctypename} = $TYPEMAP_KIND;
    $parser->{data}{typeconv}{valid_types}{$ctypename}++;
    $parser->{data}{typeconv}{valid_rtypes}{$ctypename}++;
}

#============================================================================
# Default action is to strip ellipses from the C++ code. This allows having
# _only_ a '...' in the code, just like XS. It is the default.
#============================================================================
sub strip_ellipsis {
    my $parser = shift;
    my $args = shift;
    return if $parser->{ILSM}{PRESERVE_ELLIPSIS};
    for (my $i=0; $i<@$args; $i++) {
	next unless $args->[$i]{name} eq '...';
	# if it's the first one, just strip it
	if ($i==0) {
	    substr($parser->{ILSM}{code}, $args->[$i]{offset} - 3, 3) = "   ";
	}
	else {
	    my $prev = $i - 1;
	    my $prev_offset = $args->[$prev]{offset};
	    my $length = $args->[$i]{offset} - $prev_offset;
	    substr($parser->{ILSM}{code}, $prev_offset, $length) =~ s/\S/ /g;
	}
    }
}
