# $Id$
#
# BioPerl module for Bio::Location::Fuzzy
# Cared for by Jason Stajich <jason@chg.mc.duke.edu>
#
# Copyright Jason Stajich
#
# You may distribute this module under the same terms as perl itself
# POD documentation - main docs before the code

=head1 NAME

Bio::Location::Fuzzy - Implementation of a Location on a Sequence
which has unclear start and/or end locations

=head1 SYNOPSIS

    use Bio::Location::Fuzzy;
    my $fuzzylocation = new Bio::Location::Fuzzy(-start => '<30',
						 -end   => 90,
						 -location_type => '.');

    print "location string is ", $fuzzylocation->to_FTstring(), "\n";
    print "location is of the type ", $fuzzylocation->location_type, "\n";

=head1 DESCRIPTION

This module contains the necessary methods for representing a
Fuzzy Location, one that does not have clear start and/or end points.
This will initially serve to handle features from Genbank/EMBL feature
tables that are written as 1^100 meaning between bases 1 and 100 or
E<lt>100..300 meaning it starts somewhere before 100.  Advanced
implementations of this interface may be able to handle the necessary
logic of overlaps/intersection/contains/union.  It was constructed to
handle fuzzy locations that can be represented in Genbank/EMBL.

=head1 FEEDBACK

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to one
of the Bioperl mailing lists.  Your participation is much appreciated.

  bioperl-l@bioperl.org             - General discussion
  http://bio.perl.org/MailList.html - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
the bugs and their resolution.  Bug reports can be submitted via email
or the web:

  bioperl-bugs@bio.perl.org
  http://bio.perl.org/bioperl-bugs/

=head1 AUTHOR - Jason Stajich

Email jason@chg.mc.duke.edu

=head1 APPENDIX

The rest of the documentation details each of the object
methods. Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::Location::Fuzzy;
use vars qw(@ISA );
use strict;

use Bio::Location::FuzzyLocationI;
use Bio::Location::Simple;

@ISA = qw(Bio::Location::Simple Bio::Location::FuzzyLocationI );

BEGIN {
    use vars qw( %FUZZYCODES %FUZZYPOINTENCODE %FUZZYRANGEENCODE 
		 @LOCATIONCODESBSANE );

    @LOCATIONCODESBSANE = (undef, 'EXACT', 'WITHIN', 'BETWEEN',
			'BEFORE', 'AFTER');

    %FUZZYCODES = ( 'EXACT' => '..', # Position is 'exact
   # Exact position is unknown, but is within the range specified, ((1.2)..100)
		    'WITHIN' => '.', 
		    # 1^2
		    'BETWEEN' => '^',
		    # <100
		    'BEFORE'  => '<',
		    # >10
		    'AFTER'   => '>');   
   
    # The following regular expressions map to fuzzy location types. Every
    # expression must match the complete encoded point string, and must
    # contain two groups identifying min and max. Empty matches are automatic.
    # converted to undef, except for 'EXACT', for which max is set to equal
    # min.
    %FUZZYPOINTENCODE = ( 
			  '\>(\d+)(.{0})' => 'AFTER',
			  '\<(.{0})(\d+)' => 'BEFORE',
			  '(\d+)'  => 'EXACT',
			  '(\d+)(.{0})\>' => 'AFTER',
			  '(.{0})(\d+)\<' => 'BEFORE',
			  '(\d+)\.(\d+)' => 'WITHIN',
			  '(\d+)\^(\d+)' => 'BETWEEN',
		     );
    
    %FUZZYRANGEENCODE  = ( '\.' => 'WITHIN',
			   '\.\.' => 'EXACT',
			   '\^' => 'BETWEEN' );

}

=head2 new

 Title   : new
 Usage   : my $fuzzyloc = new Bio::Location::Fuzzy( @args);
 Function: Builds a location with ambiguous start/end range info
 Returns : Bio::Location::Fuzzy object
 Args    : -start    => value for start  (initialize by superclass)
           -end      => value for end    (initialize by superclass)
           -strand   => value for strand (initialize by superclass)
           -location_type => either ('EXACT', 'WITHIN', 'BETWEEN') OR
                               ( 1,2,3)
           -start_ext=> extension for start - defaults to 0, 
           -start_fuz=  fuzzy code for start can be 
                      ( 'EXACT', 'WITHIN', 'BETWEEN', 'BEFORE', 'AFTER') OR
                      a value 1 - 5 corresponding to index+1 above
           -end_ext=> extension for end - defaults to 0, 
           -end_fuz=  fuzzy code for end can be 
                      ( 'EXACT', 'WITHIN', 'BETWEEN', 'BEFORE', 'AFTER') OR
                      a value 1 - 5 corresponding to index+1 above

=cut

sub new {
    my ($class, @args) = @_;
    my $self = $class->SUPER::new(@args);
    my ($location_type, $start_ext, $start_fuz, $end_ext, $end_fuz) = 
	$self->_rearrange([ qw(LOCATION_TYPE START_EXT START_FUZ 
			       END_EXT END_FUZ )
			    ], @args);

    $location_type  && $self->location_type($location_type);
    $start_ext && $self->max_start($self->min_start + $start_ext);
    $end_ext   && $self->max_end($self->min_end + $end_ext);
    $start_fuz && $self->start_pos_type($start_fuz);
    $end_fuz   && $self->end_pos_type($end_fuz);
    return $self;
}

=head2 location_type

  Title   : location_type
  Usage   : my $location_type = $location->location_type();
  Function: Get location type encoded as text
  Returns : string ('EXACT', 'WITHIN', 'BETWEEN')
  Args    : none

=cut

sub location_type {
    my ($self,$value) = @_;
    if( defined $value || ! defined $self->{'_location_type'} ) {
	$value = 'EXACT' unless defined $value;
	if(! defined $FUZZYCODES{$value})  {
	    $value = uc($value);
	    if( $value =~ /\.\./ ) {
		$value = 'EXACT';
	    } elsif( $value =~ /^\.$/ ) {
		$value = 'WITHIN';
	    } elsif( $value =~ /\^/ ) {
		$value = 'BETWEEN';
	    } elsif( $value ne 'EXACT' && $value ne 'WITHIN' && 
		     $value ne 'BETWEEN' ) {
		$self->throw("Did not specify a valid location type");
	    }
	}
	$self->{'_location_type'} = $value;
    }
    return $self->{'_location_type'};
}

=head1 LocationI methods

=head2 length

  Title   : length
  Usage   : $length = $fuzzy_loc->length();
  Function: Get the length of this location.

            Note that the length of a fuzzy location will always depend
            on the currently active interpretation of start and end. The
            result will therefore vary for different CoordinatePolicy objects.

  Returns : an integer
  Args    : none

=cut

#sub length {
#    my($self) = @_;
#    return $self->SUPER::length() if( !$self->start || !$self->end);
#    $self->warn('Length is not valid for a FuzzyLocation'); 
#    return 0;
#}

=head2 start

  Title   : start
  Usage   : $start = $fuzzy->start();
  Function: get/set start of this range, handling fuzzy_starts
  Returns : a positive integer representing the start of the location
  Args    : start location on set (can be fuzzy point string)

=cut

sub start {
    my($self,$value) = @_;
    if( defined $value ) {
	my ($encode,$min,$max) = $self->_fuzzypointdecode($value);	
	$self->start_pos_type($encode);
	$self->min_start($min);
	$self->max_start($max);
    }
    return $self->SUPER::start();
}

=head2 end

  Title   : end
  Usage   : $end = $fuzzy->end();
  Function: get/set end of this range, handling fuzzy_ends
  Returns : a positive integer representing the end of the range
  Args    : end location on set (can be fuzzy string)

=cut

sub end {
    my($self,$value) = @_;
    if( defined $value ) {
	my ($encode,$min,$max) = $self->_fuzzypointdecode($value);
	$self->end_pos_type($encode);
	$self->min_end($min);
	$self->max_end($max);
    }
    return $self->SUPER::end();
}

=head2 min_start

  Title   : min_start
  Usage   : $min_start = $fuzzy->min_start();
  Function: get/set the minimum starting point
  Returns : the minimum starting point from the contained sublocations
  Args    : integer or undef on set

=cut

sub min_start {
    my ($self,@args) = @_;

    if(@args) {
	$self->{'_min_start'} = $args[0]; # the value may be undef!
    }
    return $self->{'_min_start'};
}

=head2 max_start

  Title   : max_start
  Usage   : my $maxstart = $location->max_start();
  Function: Get/set maximum starting location of feature startpoint  
  Returns : integer or undef if no maximum starting point.
  Args    : integer or undef on set

=cut

sub max_start {
    my ($self,@args) = @_;

    if(@args) {
	$self->{'_max_start'} = $args[0]; # the value may be undef!
    }
    return $self->{'_max_start'};
}

=head2 start_pos_type

  Title   : start_pos_type
  Usage   : my $start_pos_type = $location->start_pos_type();
  Function: Get/set start position type.
  Returns : type of position coded as text 
            ('BEFORE', 'AFTER', 'EXACT','WITHIN', 'BETWEEN')
  Args    : a string on set

=cut

sub start_pos_type {
    my ($self,$value) = @_;
    if(defined $value &&  $value =~ /^\d+$/ ) {
	if( $value == 0 ) { $value = 'EXACT'; }
	else { 
	    my $v = $LOCATIONCODESBSANE[$value];
	    if( ! defined $v ) {
		$self->warn("Provided value $value which I don't understand, reverting to 'EXACT'");
		$v = 'EXACT';
	    }
	    $value = $v;
	}
    }
    if(defined($value)) {
	$self->{'_start_pos_type'} = $value;
    }
    return $self->{'_start_pos_type'};
}

=head2 min_end

  Title   : min_end
  Usage   : my $minend = $location->min_end();
  Function: Get/set minimum ending location of feature endpoint 
  Returns : integer or undef if no minimum ending point.
  Args    : integer or undef on set

=cut

sub min_end {
    my ($self,@args) = @_;

    if(@args) {
	$self->{'_min_end'} = $args[0]; # the value may be undef!
    }
    return $self->{'_min_end'};
}

=head2 max_end

  Title   : max_end
  Usage   : my $maxend = $location->max_end();
  Function: Get/set maximum ending location of feature endpoint 
  Returns : integer or undef if no maximum ending point.
  Args    : integer or undef on set

=cut

sub max_end {
    my ($self,@args) = @_;

    if(@args) {
	$self->{'_max_end'} = $args[0]; # the value may be undef!
    }
    return $self->{'_max_end'};
}

=head2 end_pos_type

  Title   : end_pos_type
  Usage   : my $end_pos_type = $location->end_pos_type();
  Function: Get/set end position type.
  Returns : type of position coded as text 
            ('BEFORE', 'AFTER', 'EXACT','WITHIN', 'BETWEEN')
  Args    : a string on set

=cut

sub end_pos_type {
    my ($self,$value) = @_;
    if( defined $value && $value =~ /^\d+$/ ) {
	if( $value == 0 ) { $value = 'EXACT'; }
	else { 
	    my $v = $LOCATIONCODESBSANE[$value];
	    if( ! defined $v ) {
		$self->warn("Provided value $value which I don't understand, reverting to 'EXACT'");
		$v = 'EXACT';
	    }
	    $value = $v;
	}
    }

    if(defined($value)) {
	$self->{'_end_pos_type'} = $value;
    }
    return $self->{'_end_pos_type'};
}

=head2 seq_id

  Title   : seq_id
  Usage   : my $seqid = $location->seq_id();
  Function: Get/Set seq_id that location refers to
  Returns : seq_id
  Args    : [optional] seq_id value to set

=cut

=head2 coordinate_policy

  Title   : coordinate_policy
  Usage   : $policy = $location->coordinate_policy();
            $location->coordinate_policy($mypolicy); # set may not be possible
  Function: Get the coordinate computing policy employed by this object.

            See Bio::Location::CoordinatePolicyI for documentation about
            the policy object and its use.

            The interface *does not* require implementing classes to accept
            setting of a different policy. The implementation provided here
            does, however, allow to do so.

            Implementors of this interface are expected to initialize every
            new instance with a CoordinatePolicyI object. The implementation
            provided here will return a default policy object if none has
            been set yet. To change this default policy object call this
            method as a class method with an appropriate argument. Note that
            in this case only subsequently created Location objects will be
            affected.

  Returns : A Bio::Location::CoordinatePolicyI implementing object.
  Args    : On set, a Bio::Location::CoordinatePolicyI implementing object.

=cut

=head2 to_FTstring

  Title   : to_FTstring
  Usage   : my $locstr = $location->to_FTstring()
  Function: Get/Set seq_id that location refers to
  Returns : seq_id
  Args    : [optional] seq_id value to set

=cut

sub to_FTstring {
    my ($self) = @_;
    my (%vals) = ( 'start' => $self->start,
		   'min_start' => $self->min_start,
		   'max_start' => $self->max_start,
		   'start_code' => $self->start_pos_type,
		   'end' => $self->end,
		   'min_end' => $self->min_end,
		   'max_end' => $self->max_end,
		   'end_code' => $self->end_pos_type );
    
    my (%strs) = ( 'start' => '',
		   'end'   => '');
    my ($delimiter) = $FUZZYCODES{$self->location_type};
    # I'm lazy, lets do this in a loop since behaviour will be the same for 
    # start and end
    foreach my $point ( qw(start end) ) {
	if( $vals{$point."_code"} ne 'EXACT' ) {
	    
	    if( (!defined $vals{"min_$point"} ||
		 !defined $vals{"max_$point"})
		&& ( $vals{$point."_code"} eq 'WITHIN' || 
		     $vals{$point."_code"} eq 'BETWEEN')
		     ) {
		$vals{"min_$point"} = '' unless defined $vals{"min_$point"};
		$vals{"max_$point"} = '' unless defined $vals{"max_$point"};
		
		$self->warn("Fuzzy codes for start are in a strange state, (".
			    join(",", ($vals{"min_$point"}, 
				       $vals{"max_$point"},
				       $vals{$point."_code"})). ")");
		return '';
	    }
	    if( defined $vals{$point."_code"} && 
		($vals{$point."_code"} eq 'BEFORE' ||
		 $vals{$point."_code"} eq 'AFTER')
		) {
		$strs{$point} .= $FUZZYCODES{$vals{$point."_code"}};
	    } 
	    if( defined $vals{"min_$point"} ) {
		$strs{$point} .= $vals{"min_$point"};
	    }
	    if( defined $vals{$point."_code"} && 
		($vals{$point."_code"} eq 'WITHIN' ||
		 $vals{$point."_code"} eq 'BETWEEN')
		) {
		$strs{$point} .= $FUZZYCODES{$vals{$point."_code"}};
	    }
	    if( defined $vals{"max_$point"} ) {
		$strs{$point} .= $vals{"max_$point"};
	    }
	} else { 
	    $strs{$point} = $vals{$point};
	}
    }
    my $str = $strs{'start'} . $delimiter . $strs{'end'};
    if( $self->strand == -1 ) {
	$str = sprintf("complement(%s)", $str);
    }
    return $str;
}

=head2 _fuzzypointdecode

  Title   : _fuzzypointdecode
  Usage   : ($type,$min,$max) = $self->_fuzzypointdecode('<5');
  Function: Decode a fuzzy string.
  Returns : A 3-element array consisting of the type of location, the
            minimum integer, and the maximum integer describing the range
            of coordinates this start or endpoint refers to. Minimum or
            maximum coordinate may be undefined.
          : Returns empty array on fail.
  Args    : fuzzypoint string

=cut

sub _fuzzypointdecode {
    my ($self, $string) = @_;
    return () if( !defined $string);
    # strip off leading and trailing space
    $string =~ s/^\s*(\S+)\s*/$1/;
    foreach my $pattern ( keys %FUZZYPOINTENCODE ) {
	if( $string =~ /^$pattern$/ ) {
	    my ($min,$max) = ($1,$2);
	    if($FUZZYPOINTENCODE{$pattern} eq 'EXACT') {
		$max = $min;
	    } else {
		$max = undef if(length($max) == 0);
		$min = undef if(length($min) == 0);
	    }
	    return ($FUZZYPOINTENCODE{$pattern},$min,$max);
	}
    }
    if( $self->verbose >= 1 ) {
	$self->warn("could not find a valid fuzzy encoding for $string");
    }
    return ();
}

1;

