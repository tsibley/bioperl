# $Id$ 
#
# BioPerl module for Bio::Tools::Lucy
#
# Copyright Her Majesty the Queen of England
# written by Andrew Walsh (paeruginosa@hotmail.com) during employment with 
# Agriculture and Agri-food Canada, Cereal Research Centre, Winnipeg, MB
#
# You may distribute this module under the same terms as perl itself
# POD documentation - main docs before the code

=head1 NAME

Bio::Tools::Lucy - Object for analyzing the output from Lucy,
  a vector and quality trimming program from TIGR

=head1 SYNOPSIS

  # Create the Lucy object from an existing Lucy output file 
  @params = ('seqfile' => 'lucy.seq', 'lucy_verbose' => 1);
  $lucyObj = Bio::Tools::Lucy->new(@params);

  # Get names of all sequences
  $names = $lucyObj->get_sequence_names();

  #  Print seq and qual values for sequences >400 bp in order to run CAP3
  foreach $name (@$names) {
      next unless $lucyObj->length_clear($name) > 400;
      print SEQ ">$name\n", $lucyObj->sequence($name), "\n";
      print QUAL ">$name\n", $lucyObj->quality($name), "\n";
  }

  # Get an array of Bio::PrimarySeq objects
  @seqObjs = $lucyObj->get_Seq_Objs();


=head1 DESCRIPTION

Bio::Tools::Lucy.pm provides methods for analyzing the sequence and
quality values generated by Lucy program from TIGR.

Lucy will identify vector, poly-A/T tails, and poor quality regions in
a sequence.  (www.genomics.purdue.edu/gcg/other/lucy.pdf)

The input to Lucy can be the Phred sequence and quality files
generated from running Phred on a set of chromatograms.

Lucy can be obtained (free of charge to academic users) from
www.tigr.org/softlab

There are a few methods that will only be available if you make some
minor changes to the source for Lucy and then recompile.  The changes
are in the 'lucy.c' file and there is a diff between the original and
the modified file in the Appendix

Please contact the author of this module if you have any problems
making these modifications.

You do not have to make these modifications to use this module.

=head2 Creating a Lucy object

  @params = ('seqfile' => 'lucy.seq', 'adv_stderr' => 1, 
	     'fwd_desig' => '_F', 'rev_desig' => '_R');
  $lucyObj = Bio::Tools::Lucy->new(@params);

=head2 Using a Lucy object

  You should get an array with the sequence names in order to use
  accessor methods.  Note: The Lucy binary program will fail unless
  the sequence names provided as input are unique.

  $names_ref = $lucyObj->get_sequence_names();

  This code snippet will produce a Fasta format file with sequence
  lengths and %GC in the description line.

  foreach $name (@$names) {
      print FILE ">$name\t",
		 $lucyObj->length_clear($name), "\t",
		 $lucyObj->per_GC($name), "\n",
		 $lucyObj->sequence($name), "\n";  
  }


  Print seq and qual values for sequences >400 bp in order to assemble
  them with CAP3 (or other assembler).

  foreach $name (@$names) {
      next unless $lucyObj->length_clear($name) > 400;
      print SEQ ">$name\n", $lucyObj->sequence($name), "\n";
      print QUAL ">$name\n", $lucyObj->quality($name), "\n";
  }

  Get all the sequences as Bio::PrimarySeq objects (eg., for use with
  Bio::Tools::Blast to perform BLAST).

  @seqObjs = $lucyObj->get_Seq_Objs();

  Or use only those sequences that are full length and have a Poly-A
  tail.

  foreach $name (@$names) {
      next unless ($lucyObj->full_length($name) and $lucy->polyA($name));
      push @seqObjs, $lucyObj->get_Seq_Obj($name);
  }


  Get the names of those sequences that were rejected by Lucy.

  $rejects_ref = $lucyObj->get_rejects();

  Print the names of the rejects and 1 letter code for reason they
  were rejected.

  foreach $key (sort keys %$rejects_ref) {
      print "$key:  ", $rejects_ref->{$key};
  }

  There is a lot of other information available about the sequences
  analyzed by Lucy (see APPENDIX).  This module can be used with the
  DBI module to store this sequence information in a database.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules.  Send your comments and suggestions preferably to one
of the Bioperl mailing lists.  Your participation is much appreciated.

    bioperl-l@bioperl.org             - General discussion
    http://bio.perl.org/MailList.html - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
the bugs and their resolution. Bug reports can be submitted via email
or the web:

    bioperl-bugs@bio.perl.org
    http://bugzilla.bioperl.org/

=head1 AUTHOR

Andrew G. Walsh		paeruginosa@hotmail.com

=head1 APPENDIX

Methods available to Lucy objects are described below.  Please note
that any method beginning with an underscore is considered internal
and should not be called directly.

=cut


package Bio::Tools::Lucy;

use vars qw($AUTOLOAD @ISA @ATTR %OK_FIELD);
use strict;
use Bio::PrimarySeq;
use Bio::Root::Root;
use Bio::Root::IO;

@ISA = qw(Bio::Root::Root Bio::Root::IO);
@ATTR = qw(seqfile qualfile stderrfile infofile lucy_verbose fwd_desig rev_desig adv_stderr); 
foreach my $attr (@ATTR) {
    $OK_FIELD{$attr}++
}

sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s/.*:://;
    $attr = lc $attr;
    $self->throw("Unallowed parameter: $attr !") unless $OK_FIELD{$attr};
    $self->{$attr} = shift if @_;
    return $self->{$attr};
}

=head2 new

 Title	 :  new
 Usage	 :  $lucyObj = Bio::Tools::Lucy->new(seqfile => lucy.seq, rev_desig => '_R', 
	    fwd_desig => '_F')
 Function:  creates a Lucy object from Lucy analysis files
 Returns :  reference to Bio::Tools::Lucy object
 Args	 :  seqfile	Fasta sequence file generated by Lucy
	    qualfile	Quality values file generated by Lucy
	    infofile	Info file created when Lucy is run with -debug 'infofile' option
	    stderrfile	Standard error captured from Lucy when Lucy is run 
			with -info option and STDERR is directed to stderrfile 
			(ie. lucy ... 2> stderrfile).
			Info in this file will include sequences dropped for low 
			quality. If you've modified Lucy source (see adv_stderr below), 
			it will also include info on which sequences were dropped because 
			they were vector, too short, had no insert, and whether a poly-A 
			tail was found (if Lucy was run with -cdna option).
	    lucy_verbose verbosity level (0-1).  
	    fwd_desig	The string used to determine whether sequence is a forward read.  
			The parser will assume that this match will occus at the 
			end of the sequence name string.
	    rev_desig	As above, for reverse reads. 
 	    adv_stderr	Can be set to a true value (1).  Will only work if you have modified 
			the Lucy source code as outlined in DESCRIPTION and capture 
			the standard error from Lucy.

If you don't provide filenames for qualfile, infofile or stderrfile,
the module will assume that .qual, .info, and .stderr are the file
extensions and search in the same directory as the .seq file for these
files.

For example, if you create a Lucy object with $lucyObj =
Bio::Tools::Lucy-E<gt>new(seqfile =E<gt>lucy.seq), the module will
find lucy.qual, lucy.info and lucy.stderr.

You can omit any or all of the quality, info or stderr files, but you
will not be able to use all of the object methods (see method
documentation below).

=cut

sub new {
    my ($class,@args) = @_;
    my $self = $class->SUPER::new(@args);
    my ($attr, $value);
    while (@args) {
	$attr = shift @args;
	$attr = lc $attr;
	$value = shift @args;
	$self->{$attr} = $value;
    }
    &_parse($self);	
    return $self;
}

=head2 _parse

 Title	 :  _parse
 Usage	 :  n/a (internal function)
 Function:  called by new() to parse Lucy output files
 Returns :  nothing
 Args	 :  none

=cut

sub _parse {
    my $self = shift;
    $self->{seqfile} =~ /^(\S+)\.\S+$/;
    my $file = $1;
    
    print "Opening $self->{seqfile} for parsing...\n" if $self->{lucy_verbose};
    open SEQ, "$self->{seqfile}" or $self->throw("Could not open sequence file: $self->{seqfile}");
    my ($name, $line);
    my $seq = "";
    my @lines = <SEQ>;
    while ($line = pop @lines) {
	chomp $line;
	if ($line =~ /^>(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/) {    
            $name = $1;
	    if ($self->{fwd_desig}) {
		$self->{sequences}{$name}{direction} = "F" if $name =~ /^(\S+)($self->{fwd_desig})$/;
	    }
	    if ($self->{rev_desig}) {
                $self->{sequences}{$name}{direction} = "R" if $name =~ /^(\S+)($self->{rev_desig})$/;
            }
	    $self->{sequences}{$name}{min_clone_len} = $2; # this is used for TIGR Assembler, as are $3 and $4
	    $self->{sequences}{$name}{max_clone_len} = $3;
	    $self->{sequences}{$name}{med_clone_len} = $4; 
	    $self->{sequences}{$name}{beg_clear} = $5;
	    $self->{sequences}{$name}{end_clear} = $6;
	    $self->{sequences}{$name}{length_raw} = $seq =~ tr/[AGCTN]//; # from what I've seen, these are the bases Phred calls.  Please let me know if I'm wrong.     
	    my $beg = $5-1; # substr function begins with index 0
	    $seq = $self->{sequences}{$name}{sequence} = substr ($seq, $beg, $6-$beg);
	    my $count = $self->{sequences}{$name}{length_clear} = $seq =~ tr/[AGCTN]//;
	    my $countGC =  $seq =~ tr/[GC]//;
	    $self->{sequences}{$name}{per_GC} = $countGC/$count * 100;
	    $seq = "";
	}
	else {
	    $seq = $line.$seq;
	} 
    }


# now parse quality values (check for presence of quality file first) 
    if ($self->{qualfile}) {
	open QUAL, "$self->{qualfile}" or $self->throw("Could not open quality file: $self->{qualfile}");
	@lines = <QUAL>;
    }
    elsif (-e "$file.qual") {
	print "You did not set qualfile, but I'm opening $file.qual\n" if $self->{lucy_verbose};
	$self->qualfile("$file.qual");
	open QUAL, "$file.qual" or $self->throw("Could not open quality file: $file.qual");
	@lines = <QUAL>;
    }
    else {
	print "I did not find a quality file.  You will not be able to use all of the accessor methods.\n" if $self->{lucy_verbose};
	@lines = ();
    }

    my (@vals, @slice, $num, $tot, $vals);  
    my $qual = ""; 
    while ($line = pop @lines) {
	chomp $line;
 	if ($line =~ /^>(\S+)/) {
	    $name = $1;
	    @vals = split /\s/ , $qual;
	    @slice = @vals[$self->{sequences}{$name}{beg_clear} .. $self->{sequences}{$name}{end_clear}];
	    $vals = join "\t", @slice;
	    $self->{sequences}{$name}{quality} = $vals;
	    $qual = "";
	    foreach $num (@slice) {
		$tot += $num;
	    }
	    $num = @slice;
	    $self->{sequences}{$name}{avg_quality} = $tot/$num;
	    $tot = 0;
	}
	else {
	    $qual = $line.$qual;
	}
    }

# determine whether reads are full length

    if ($self->{infofile}) {
        open INFO, "$self->{infofile}" or $self->throw("Could not open info file: $self->{infofile}");
	@lines = <INFO>;
    }
    elsif (-e "$file.info") {
	print "You did not set infofile, but I'm opening $file.info\n" if $self->{lucy_verbose};
	$self->infofile("$file.info");
        open INFO, "$file.info" or $self->throw("Could not open info file: $file.info");
	@lines = <INFO>;
    }
    else {
	print "I did not find an info file.  You will not be able to use all of the accessor methods.\n" if $self->{lucy_verbose};
	@lines = ();
    }

    foreach (@lines) {
	/^(\S+).+CLV\s+(\d+)\s+(\d+)$/;
	if ($2>0 && $3>0) {
	    $self->{sequences}{$1}{full_length} = 1 if $self->{sequences}{$1}; # will show cleavage info for rejected sequences too
	}
    }


# parse rejects (and presence of poly-A if Lucy has been modified)

    if ($self->{stderrfile}) {
        open STDERR_LUCY, "$self->{stderrfile}" or $self->throw("Could not open quality file: $self->{stderrfile}");
	@lines = <STDERR_LUCY>;

    }
    elsif (-e "$file.stderr") {
	print "You did not set stderrfile, but I'm opening $file.stderr\n" if $self->{lucy_verbose};
	$self->stderrfile("$file.stderr");
        open STDERR_LUCY, "$file.stderr" or $self->throw("Could not open quality file: $file.stderr");
	@lines = <STDERR_LUCY>;
    }
    else {
	print "I did not find a standard error file.  You will not be able to use all of the accessor methods.\n" if $self->{lucy_verbose};
        @lines = ();
    }

    if ($self->{adv_stderr}) {
	foreach (@lines) {
	    $self->{reject}{$1} = "Q" if /dropping\s+(\S+)/;
	    $self->{reject}{$1} = "V" if /Vector: (\S+)/;
	    $self->{reject}{$1} = "E" if /Empty: (\S+)/;
	    $self->{reject}{$1} = "S" if /Short: (\S+)/;
	    $self->{sequences}{$1}{polyA} = 1 if /(\S+) has PolyA/;
	    if (/Dropped PolyA: (\S+)/) {
		$self->{reject}{$1} = "P";		
		delete $self->{sequences}{$1};
	    }
	}
    }
    else {
	foreach (@lines) {
	    $self->{reject}{$1} = "R" if /dropping\s+(\S+)/;
	}
    }

}

=head2 get_Seq_Objs

 Title   :  get_Seq_Objs
 Usage   :  $lucyObj->get_Seq_Objs()
 Function:  returns an array of references to Bio::PrimarySeq objects 
	    where -id = 'sequence name' and -seq = 'sequence'

 Returns :  array of Bio::PrimarySeq objects
 Args	 :  none

=cut

sub get_Seq_Objs {
    my $self = shift;
    my($seqobj, @seqobjs);
    foreach my $key (sort keys %{$self->{sequences}}) {
	$seqobj = Bio::PrimarySeq->new( -seq => "$self->{sequences}{$key}{sequence}",
					-id => "$key");
	push @seqobjs, $seqobj;
    }
    return \@seqobjs;
} 

=head2 get_Seq_Obj

 Title   :  get_Seq_Obj
 Usage   :  $lucyObj->get_Seq_Obj($seqname)
 Function:  returns reference to a Bio::PrimarySeq object where -id = 'sequence name'
	    and -seq = 'sequence'
 Returns :  reference to Bio::PrimarySeq object
 Args	 :  name of a sequence 

=cut

sub get_Seq_Obj {
    my ($self, $key) = @_;
    my $seqobj = Bio::PrimarySeq->new( -seq => "$self->{sequences}{$key}{sequence}",
                                    -id => "$key");
    return $seqobj;
}

=head2 get_sequence_names

 Title   :  get_sequence_names
 Usage   :  $lucyObj->get_sequence_names
 Function:  returns reference to an array of names of the sequences analyzed by Lucy.
	    These names are required for most of the accessor methods.  
	    Note: The Lucy binary will fail unless sequence names are unique.
 Returns :  array reference
 Args	 :  none 

=cut

sub get_sequence_names {
    my $self = shift;
    my @keys = sort keys %{$self->{sequences}};
    return \@keys;
}

=head2 sequence

 Title   :  sequence
 Usage   :  $lucyObj->sequence($seqname)
 Function:  returns the DNA sequence of one of the sequences analyzed by Lucy.
 Returns :  string
 Args	 :  name of a sequence                   

=cut

sub sequence {
    my ($self, $key) = @_;
    return $self->{sequences}{$key}{sequence};
}

=head2 quality

 Title   :  quality
 Usage   :  $lucyObj->quality($seqname)
 Function:  returns the quality values of one of the sequences analyzed by Lucy.
	    This method depends on the user having provided a quality file.
 Returns :  string
 Args    :  name of a sequence

=cut

sub quality {
    my($self, $key) = @_;
    return $self->{sequences}{$key}{quality};
}

=head2 avg_quality

 Title   :  avg_quality
 Usage   :  $lucyObj->avg_quality($seqname)
 Function:  returns the average quality value for one of the sequences analyzed by Lucy.
 Returns :  float
 Args    :  name of a sequence

=cut

sub avg_quality {
    my($self, $key) = @_;
    return $self->{sequences}{$key}{avg_quality};
}

=head2 direction

 Title   :  direction
 Usage   :  $lucyObj->direction($seqname)
 Function:  returns the direction for one of the sequences analyzed by Lucy
	    providing that 'fwd_desig' or 'rev_desig' were set when the
 	    Lucy object was created.
	    Strings returned are: 'F' for forward, 'R' for reverse.  
 Returns :  string 
 Args    :  name of a sequence

=cut

sub direction {
    my($self, $key) = @_;
    return $self->{sequences}{$key}{direction} if $self->{sequences}{$key}{direction}; 
    return "";
}

=head2 length_raw

 Title   :  length_raw
 Usage   :  $lucyObj->length_raw($seqname)
 Function:  returns the length of a DNA sequence prior to quality/ vector 
	    trimming by Lucy.
 Returns :  integer
 Args    :  name of a sequence

=cut

sub length_raw {
    my($self, $key) = @_;
    return $self->{sequences}{$key}{length_raw};
}

=head2 length_clear

 Title   :  length_clear
 Usage   :  $lucyObj->length_clear($seqname)
 Function:  returns the length of a DNA sequence following quality/ vector   
            trimming by Lucy.
 Returns :  integer
 Args    :  name of a sequence

=cut

sub length_clear {
    my($self, $key) = @_;
    return $self->{sequences}{$key}{length_clear};
}

=head2 start_clear

 Title   :  start_clear
 Usage   :  $lucyObj->start_clear($seqname)
 Function:  returns the beginning position of good quality, vector free DNA sequence 
	    determined by Lucy.
 Returns :  integer
 Args    :  name of a sequence

=cut

sub start_clear {
    my($self, $key) = @_;
    return $self->{sequences}{$key}{beg_clear};
}


=head2 end_clear

 Title   :  end_clear
 Usage   :  $lucyObj->end_clear($seqname)
 Function:  returns the ending position of good quality, vector free DNA sequence
            determined by Lucy.
 Returns :  integer
 Args    :  name of a sequence

=cut

sub end_clear {
    my($self, $key) = @_;
    return $self->{sequences}{$key}{end_clear};
}

=head2 per_GC

 Title   :  per_GC
 Usage   :  $lucyObj->per_GC($seqname)
 Function:  returns the percente of the good quality, vector free DNA sequence
            determined by Lucy.
 Returns :  float
 Args    :  name of a sequence

=cut

sub per_GC {
    my($self, $key) = @_;
    return $self->{sequences}{$key}{per_GC};
}

=head2 full_length

 Title   :  full_length
 Usage   :  $lucyObj->full_length($seqname)
 Function:  returns the truth value for whether or not the sequence read was
            full length (ie. vector present on both ends of read).  This method
            depends on the user having provided the 'info' file (Lucy must be
            run with the -debug 'info_filename' option to get this file).
 Returns :  boolean 
 Args    :  name of a sequence

=cut

sub full_length {
    my($self, $key) = @_;
    return 1 if $self->{sequences}{$key}{full_length};
    return 0;
}

=head2 polyA

 Title   :  polyA
 Usage   :  $lucyObj->polyA($seqname)
 Function:  returns the truth value for whether or not a poly-A tail was detected
            and clipped by Lucy.  This method depends on the user having modified
            the source for Lucy as outlined in DESCRIPTION and invoking Lucy with
            the -cdna option and saving the standard error.
            Note, the final sequence will not show the poly-A/T region.
 Returns :  boolean
 Args    :  name of a sequence

=cut

sub polyA {
    my($self, $key) = @_;
    return 1 if $self->{sequences}{$key}{polyA};
    return 0;
}

=head2 get_rejects

 Title   :  get_rejects
 Usage   :  $lucyObj->get_rejects()
 Function:  returns a hash containing names of rejects and a 1 letter code for the 
 	    reason Lucy rejected the sequence.
	    Q- rejected because of low quality values
	    S- sequence was short
	    V- sequence was vector 
	    E- sequence was empty
	    P- poly-A/T trimming caused sequence to be too short
	    In order to get the rejects, you must provide a file with the standard
	    error from Lucy.  You will only get the quality category rejects unless
	    you have modified the source and recompiled Lucy as outlined in DESCRIPTION.
 Returns :  hash reference
 Args    :  none

=cut

sub get_rejects {
    my $self = shift;
    return $self->{reject};
}

=head2 Diff for Lucy source code 

  352a353,354
  >       /* AGW added next line */
  >       fprintf(stderr, "Empty: %s\n", seqs[i].name);
  639a642,643
  > 	    /* AGW added next line */
  > 	    fprintf(stderr, "Short/ no insert: %s\n", seqs[i].name);
  678c682,686
  < 	if (left) seqs[i].left+=left;
  ---
  > 	if (left) {
  > 	  seqs[i].left+=left;
  > 	  /*  AGW added next line */
  > 	  fprintf(stderr, "%s has PolyA (left).\n", seqs[i].name);
  > 	}
  681c689,693
  < 	if (right) seqs[i].right-=right;
  ---
  > 	if (right) {
  > 	  seqs[i].right-=right;
  > 	  /* AGW added next line */
  > 	  fprintf(stderr, "%s has PolyA (right).\n", seqs[i].name);
  > 	}
  682a695,696
  > 	  /* AGW added next line */
  > 	  fprintf(stderr, "Dropped PolyA: %s\n", seqs[i].name);	
  734a749,750
  > 	  /* AGW added next line */
  > 	  fprintf(stderr, "Vector: %s\n", seqs[i].name);

=cut

1;
