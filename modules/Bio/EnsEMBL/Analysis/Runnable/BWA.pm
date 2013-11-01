=head1 LICENSE

  Copyright (c) 1999-2012 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

    http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.

=cut

=head1 NAME

Bio::EnsEMBL::Analysis::Runnable::BWA

=head1 SYNOPSIS

  my $runnable = 
    Bio::EnsEMBL::Analysis::Runnable::BWA->new();

 $runnable->run;
 my @results = $runnable->output;
 
=head1 DESCRIPTION

This module uses BWA to align fastq to a genomic sequence

=head1 METHODS

=cut


package Bio::EnsEMBL::Analysis::Runnable::BWA;

use warnings ;
use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Analysis::Runnable;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::EnsEMBL::Utils::Argument qw( rearrange );
$| = 1;
@ISA = qw(Bio::EnsEMBL::Analysis::Runnable);

sub new {
  my ( $class, @args ) = @_;
  my $self = $class->SUPER::new(@args);
  my ($options, $fastq,$fastqpair,$outdir,$genome) = rearrange([qw (OPTIONS FASTQ FASTQPAIR OUTDIR GENOME)],@args);
  $self->throw("You must defne a fastq file\n")  unless $fastq ;
  $self->fastq($fastq);
  $self->fastqpair($fastqpair);
  $self->throw("You must defne alignment options\n")  unless $options;
  $self->options($options);
  $self->throw("You must defne an output dir\n")  unless $outdir;
  $self->outdir($outdir);
  $self->throw("You must defne a genome file\n")  unless $genome;
  $self->genome($genome);
  return $self;
}

=head2 run

  Args       : none
  Description: Merges Sam files defined in the config using Samtools
  Returntype : none

=cut 

sub run {
  my ($self) = @_;
  # get a list of files to use
  my @files;

  my $fastq = $self->fastq;
  my $options = $self->options;
  my $outdir = $self->outdir;
  my $program = $self->program;
  my $filename;
  my @tmp = split(/\//,$fastq);
  $filename = pop @tmp;
  print "Filename $filename\n";
  # run bwa
  unless ( -e (  $self->genome.".ann" ) ) {
    $self->throw("Genome file must be indexed \ntry " . $self->program . " index " . $self->genome ."\n"); 
  }
  my $command = "$program aln $options -f $outdir" ."/$filename.sai " . $self->genome 
    ." $fastq";
  print STDERR "Command: $command\n";
  if (system($command)) {
      $self->throw("Error aligning $filename\nError code: $?\n");
  }
  
}




#Containers
#=================================================================

sub fastq {
  my ($self,$value) = @_;

  if (defined $value) {
    $self->{'_fastq'} = $value;
  }
  
  if (exists($self->{'_fastq'})) {
    return $self->{'_fastq'};
  } else {
    return undef;
  }
}

sub fastqpair {
  my ($self,$value) = @_;

  if (defined $value) {
    $self->{'_fastqpair'} = $value;
  }
  
  if (exists($self->{'_fastqpair'})) {
    return $self->{'_fastqpair'};
  } else {
    return undef;
  }
}

sub options {
  my ($self,$value) = @_;

  if (defined $value) {
    $self->{'_options'} = $value;
  }
  
  if (exists($self->{'_options'})) {
    return $self->{'_options'};
  } else {
    return undef;
  }
}

sub outdir {
  my ($self,$value) = @_;

  if (defined $value) {
    $self->{'_outdir'} = $value;
  }
  
  if (exists($self->{'_outdir'})) {
    return $self->{'_outdir'};
  } else {
    return undef;
  }
}


sub genome {
  my ($self,$value) = @_;

  if (defined $value) {
    $self->{'_genome'} = $value;
  }
  
  if (exists($self->{'_genome'})) {
    return $self->{'_genome'};
  } else {
    return undef;
  }
}
