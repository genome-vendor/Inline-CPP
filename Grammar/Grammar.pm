package Inline::CPP::Grammar;

use strict;

$Inline::CPP::Grammar::VERSION = '0.10';

sub grammar {
   <<'END';

code: part(s) {1}

part: comment
    | class_def
      {
#         print "Found a class: $item[1]->[0]\n";
         my $class = $item[1]->[0];
         my @parts;
         foreach (@{$item[1]->[1]}) { push @parts, @$_ }
         push @{$thisparser->{data}->{classes}}, $class;
         $thisparser->{data}->{class}->{$class} = \@parts;
      }
    | function_def
      {
#         print "found a function: $item[1]->{name}\n";
         my $func = $item[1]->{name};
	 my %func = ();
         $func{return_type} = $item[1]->{rtype};
	 for my $arg (@{$item[1]->{args}}) {
	    push @{$func{arg_names}}, $arg->{name};
	    push @{$func{arg_types}}, $arg->{type};
	 }
	 unless ($func =~ /::/) {
	     push @{$thisparser->{data}->{functions}}, $func;
	     $thisparser->{data}->{function}->{$func} = \%func;
	 }
      }
    | all

class_def: 'class' IDENTIFIER '{' class_part(s) '}' ';' 
           { 
#              print "Found a class definition: $item[2]\n";
	      [@item[2,4]]
	   }

class_part: comment { [ {thing => 'comment'} ] }
          | 'public:' class_decl(s)
            {
              for my $decl (@{$item[2]}) {
                $decl->{scope} = 'public';
              }
#              print "Found a public part\n";
	      $item[2]
	    }
          | 'private:' class_decl(s)
	    {
              for my $decl (@{$item[2]}) {
                $decl->{scope} = 'private';
              }
#              print "Found a private part\n";
	      $item[2]
	    }

class_decl: comment { {thing => 'comment'} }
          | method_def
	    {
              $item[1]->{thing} = 'method';
#	      print "class_decl found a method: $item[1]->{name}\n";
	      $item[1];
	    }
          | member_def
	    {
              $item[1]->{thing} = 'member';
#	      print "class_decl found a member: $item[1]\n";
	      $item[1];
	    }

function_def: /[:_~a-z]+/i '(' <leftop: arg ',' arg>(s?) ')'
              {
                {name => $item[1], args => $item[3]}
              }
            | /[:_~a-z]+/i '(' <leftop: arg ',' arg>(s?) ')'
              {
                {name => $item[1], args => $item[3]}
              }
            | rtype /[:_~a-z]+/i '(' <leftop: arg ',' arg>(s?) ')'
              {
                {rtype => $item[1], name => $item[2], args => $item[4]}
              }
            | rtype /[:_~a-z]+/i '(' <leftop: arg ',' arg>(s?) ')'
              {
                {rtype => $item[1], name => $item[2], args => $item[4]}
              }

method_def: IDENTIFIER '(' <leftop: arg ',' arg>(s?) ')' ';'
            {
#	      print "con-/de-structor found: $item[1]\n";
	      {name => $item[1], args => $item[3]}
            }
          | rtype IDENTIFIER '(' <leftop: arg ',' arg>(s?) ')' ';'
            {
#	      print "method found: $item[2]\n";
	      {name => $item[2], rtype => $item[1], args => $item[4]}
            }

member_def: anytype IDENTIFIER ';'
            { 
#	      print "member found: $item[1]\n";
	      {type => $item[1], name => $item[2]}
            }
          | anytype IDENTIFIER '=' all
            { 
#	      print "member found: $item[1]\n";
	      {type => $item[1], name => $item[2]}
            }

arg: type IDENTIFIER '=' /[^ \)]+/ { {type=>$item[1], name => $item[2]} }
   | type IDENTIFIER
     { 
#       print "argument $item[1] found\n";
       {type => $item[1], name => $item[2]}
     }
   | '...' { {name => '...', type => '...'} }

IDENTIFIER: /[~_a-z]\w*/i
	    {
#	      print "IDENTIFIER: $item[1]\n";
	      $item[1]
	    }

comment:  m{\s* // [^\n]* \n }x
	| m{\s* /\* (?:[^*]+|\*(?!/))* \*/  ([ \t]*)? }x

rtype:	TYPE star(s?)
        {
         $return = $item[1];
         $return .= join '',' ',@{$item[2]} if @{$item[2]};
         return undef unless (defined $Inline::CPP::valid_rtypes{$return});
        }
      | modifier(s) TYPE star(s?)
	{
         $return = $item[2];
         $return = join ' ',@{$item[1]},$return 
           if @{$item[1]} and $item[1][0] ne 'extern';
         $return .= join '',' ',@{$item[3]} if @{$item[3]};
         return undef unless (defined $Inline::CPP::valid_rtypes{$return});
	}
type:   TYPE star(s?)
        {
         $return = $item[1];
         $return .= join '',' ',@{$item[2]} if @{$item[2]};
         return undef unless (defined $Inline::CPP::valid_types{$return});
        }
      | modifier(s) TYPE star(s?)
	{
         $return = $item[2];
         $return = join ' ',@{$item[1]},$return if @{$item[1]};
         $return .= join '',' ',@{$item[3]} if @{$item[3]};
         return undef unless (defined $Inline::CPP::valid_types{$return});
	}

anytype: TYPE star(s?)
         {
           $return = $item[1];
           $return .= join '',' ',@{$item[2]} if @{$item[2]};
         }
       | modifier(s) TYPE star(s?)
         {
           $return = $item[2];
           $return = join ' ',@{$item[1]},$return if @{$item[1]};
           $return .= join '',' ',@{$item[3]} if @{$item[3]};
         }

modifier: 'extern' | 'unsigned' | 'long' | 'short' | 'const'

star: '*' | '&'

TYPE: /\w+/

all: /.*/

END

}
