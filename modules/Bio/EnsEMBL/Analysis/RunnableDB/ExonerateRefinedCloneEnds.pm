
=head1 LICENSE

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=cut

=head1 NAME

Bio::EnsEMBL::Analysis::RunnableDB::ExonerateRefineCloneEnds -

=head1 SYNOPSIS

my $clone =
  Bio::EnsEMBL::Analysis::RunnableDB::ExonerateConeEnds->new(
    -db         => $refdb,
    -analysis   => $analysis_obj,
    -database   => $EST_GENOMIC,
    -query_seqs => \@sequences,
  );

$clone->fetch_input();
$clone->run();
$clone->write_output(); #writes to DB

=head1 DESCRIPTION

This object maps clone sequences to a genome,
and writing the results as Features.

=head1 METHODS


=head1 APPENDIX

=cut

package Bio::EnsEMBL::Analysis::RunnableDB::ExonerateRefineCloneEnds;

use warnings;
use strict;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::EnsEMBL::Analysis::RunnableDB;
use Bio::EnsEMBL::Analysis::Runnable::ExonerateCloneEnds;
use Bio::EnsEMBL::Analysis::Config::ExonerateRefinedCloneEnds;

use vars qw(@ISA);

@ISA = qw (Bio::EnsEMBL::Analysis::RunnableDB);

############################################################
sub new {
  my ( $class, @args ) = @_;
  my $self = $class->SUPER::new(@args);

  #Because we dont know whether the sort of adapter (compara, hive, core)
  #we'll be passed, it's better to just remake the core dbadaptor and
  #keep it on ourselves as the dna db - this has to be the intent of the
  #dataadaptor input through the rulemanager / beekeeper / whatever

  $self->read_and_check_config($CLONE_CONFIG);
  return $self;
}

sub fetch_input {
  my ($self) = @_;

  my $logic = $self->analysis->logic_name;

  ##########################################
  # set up the target (genome)
  ##########################################

  my $target = $self->GENOMICSEQS;

  if ( -e $target ) {
    if ( -d $target ) {
      warn("Target $target is a directory of files\n");
    }
    elsif ( -s $target ) {
      warn("Target $target is a whole-genome file\n");
    }
    else {
      throw("'$target' isn't a file or a directory?");
    }
  }
  else {
    throw("'$target' could not be found");
  }

  ##########################################
  # set up the query (dna clone seq)
  ##########################################

  my ( $query_file, $chunk_number, $chunk_total );

  my $query = $self->QUERYSEQS;

  if ( -e $query and -s $query ) {

    # query seqs is a single file; input id will correspond to a chunk number
    $query_file = $query;
    my $iid_regexp = $self->IIDREGEXP;

    if ( not defined $iid_regexp ) {
      throw("You must define IIDREGEXP in config to enable inference of chunk number and total from your single fasta file");
    }

    ( $chunk_number, $chunk_total ) = $self->input_id =~ /$iid_regexp/;
    if ( !$chunk_number || !$chunk_total ) {
      throw "I can't make sense of your input id  using the IIDREGEXP in the config!\n";
    }

    #store this for reference later
    $self->query_file($query_file);

  }
  else {

    throw("'$query'  must refer to a single fasta file with all probe sequences referenced by clone_probe_id\n");

  }

  ##########################################
  # setup the runnable
  ##########################################

  my %parameters = %{ $self->parameters_hash };

  if ( not exists( $parameters{-options} ) and defined $self->OPTIONS ) {
    $parameters{-options} = $self->OPTIONS;
  }

  print STDERR "PROGRAM FILE: " . $self->analysis->program_file . "\n";

  my $runnable =
    Bio::EnsEMBL::Analysis::Runnable::ExonerateCloneEnds->new( -program            => $self->analysis->program_file,
                                                               -analysis           => $self->analysis,
                                                               -target_file        => $target,
                                                               -query_type         => $self->QUERYTYPE,
                                                               -query_file         => $query_file,
                                                               -query_chunk_number => $chunk_number,
                                                               -query_chunk_total  => $chunk_total,
                                                               %parameters, );

  $self->runnable($runnable);

} ## end sub fetch_input

############################################################

sub run {
  my ($self) = @_;
  my @clone_features;

  throw("Can't run - no runnable objects") unless ( $self->runnable );

  my $runnable = @{ $self->runnable }[0];

  $runnable->run;

  @clone_features = @{ $runnable->output };

  #
  #Replace the 'dummy' clone array and probe objects in the
  #CloneFeature objects with the 'real' instances found in
  #the populate... method
  $self->output( \@clone_features );
  $self->clone_features( \@clone_features );
}

############################################################

sub write_output {
  my ( $self, @output ) = @_;

  my $outdb                 = $self->create_output_db;
  my $clone_feature_adaptor = $outdb->get_DnaAlignFeatureAdaptor;

  #Add analysis, slices to DnaAlign_features, and make
  #sure they're pointing at the persistent array instances
  #instead of the fake arrays  they were created with
  $self->clean_clone_features( @{ $self->clone_features } );

  foreach my $clone_feature ( @{ $self->clone_features } ) {

    eval { $clone_feature_adaptor->store($clone_feature) };
    if ($@) {
      $self->throw("Unable to store clone feature!\n $@");
    }
  }

}

############################################################

sub clean_clone_features {
  my ( $self, @clone_features ) = @_;

  my $db            = $self->create_output_db;
  my $slice_adaptor = $db->get_SliceAdaptor;

  my %genome_slices;

  foreach my $clone_feature (@clone_features) {

    $clone_feature->analysis( $self->analysis );

    # get the slice based on the seqname stamped on in the runnable
    my $slice_id = $clone_feature->seqname;

    if ( not exists $genome_slices{$slice_id} ) {
      # assumes genome seqs were named in the Ensembl API Slice naming
      # convention, i.e. coord_syst:version:seq_reg_id:start:end:strand
      $genome_slices{$slice_id} = $slice_adaptor->fetch_by_name($slice_id);
    }
    my $slice = $genome_slices{$slice_id};

    $clone_feature->slice($slice);

  }
  return @clone_features;
} ## end sub clean_clone_features

sub create_output_db {
  my ($self) = @_;

  my $outdb;
  my $dnadb;

  if ( $self->OUTDB && $self->DNADB ) {
    $dnadb = new Bio::EnsEMBL::DBSQL::DBAdaptor( %{ $self->OUTDB } );

    $outdb = new Bio::EnsEMBL::DBSQL::DBAdaptor( %{ $self->OUTDB }, -dnadb => $dnadb );

  }
  elsif ( $self->OUTDB ) {
    $outdb = new Bio::EnsEMBL::DBSQL::DBAdaptor( %{ $self->OUTDB } );
  }
  else {
    $outdb = $self->db;
  }

  return $outdb;
}

sub query_file {
  my ( $self, $value ) = @_;

  if ( defined $value ) {
    $self->{'_query_file'} = $value;
  }

  if ( exists( $self->{'_query_file'} ) ) {
    return $self->{'_query_file'};
  }
  else {
    return undef;
  }
}

#############################################################

sub clone_features {
  my ( $self, $value ) = @_;

  if ( defined $value ) {
    $self->{'_clone_features'} = $value;
  }

  if ( exists( $self->{'_clone_features'} ) ) {
    return $self->{'_clone_features'};
  }
  else {
    return undef;
  }
}

#############################################################
# Declare and set up config variables
#############################################################

sub read_and_check_config {
  my $self = shift;

  $self->SUPER::read_and_check_config($CLONE_CONFIG);

  ##########
  # CHECKS
  ##########
  my $logic = $self->analysis->logic_name;

  # check that compulsory options have values
  foreach my $config_var ( qw(
                           QUERYSEQS
                           QUERYTYPE
                           GENOMICSEQS
                           ) )
  {
    if ( not defined $self->$config_var ) {
      throw("You must define $config_var in config for logic '$logic'");
    }
  }

  # output db does not have to be defined, but if it is, it should be a hash
  if ( $self->OUTDB && ref( $self->OUTDB ) ne "HASH" ) {
    throw("OUTDB in config for '$logic' must be a hash ref of db connection pars.");
  }

  if ( $self->DNADB and ref( $self->DNADB ) ne "HASH" ) {
    throw("DNADB in config for '$logic' must be a hash ref of db connection pars.");
  }
} ## end sub read_and_check_config

sub QUERYSEQS {
  my ( $self, $value ) = @_;

  if ( defined $value ) {
    $self->{'_CONFIG_QUERYSEQS'} = $value;
  }

  if ( exists( $self->{'_CONFIG_QUERYSEQS'} ) ) {
    return $self->{'_CONFIG_QUERYSEQS'};
  }
  else {
    return undef;
  }
}

sub QUERYTYPE {
  my ( $self, $value ) = @_;

  if ( defined $value ) {
    $self->{'_CONFIG_QUERYTYPE'} = $value;
  }

  if ( exists( $self->{'_CONFIG_QUERYTYPE'} ) ) {
    return $self->{'_CONFIG_QUERYTYPE'};
  }
  else {
    return undef;
  }
}

sub GENOMICSEQS {
  my ( $self, $value ) = @_;

  if ( defined $value ) {
    $self->{'_CONFIG_GENOMICSEQS'} = $value;
  }

  if ( exists( $self->{'_CONFIG_GENOMICSEQS'} ) ) {
    return $self->{'_CONFIG_GENOMICSEQS'};
  }
  else {
    return undef;
  }
}

sub IIDREGEXP {
  my ( $self, $value ) = @_;

  if ( defined $value ) {
    $self->{'_CONFIG_IIDREGEXP'} = $value;
  }

  if ( exists( $self->{'_CONFIG_IIDREGEXP'} ) ) {
    return $self->{'_CONFIG_IIDREGEXP'};
  }
  else {
    return undef;
  }
}

sub OUTDB {
  my ( $self, $value ) = @_;

  if ( defined $value ) {
    $self->{'_CONFIG_OUTDB'} = $value;
  }

  if ( exists( $self->{'_CONFIG_OUTDB'} ) ) {
    return $self->{'_CONFIG_OUTDB'};
  }
  else {
    return undef;
  }
}

sub DNADB {
  my ( $self, $value ) = @_;

  if ( defined $value ) {
    $self->{'_CONFIG_DNADB'} = $value;
  }

  if ( exists( $self->{'_CONFIG_DNADB'} ) ) {
    return $self->{'_CONFIG_DNADB'};
  }
  else {
    return undef;
  }
}

sub OPTIONS {
  my ( $self, $value ) = @_;

  if ( defined $value ) {
    $self->{'_CONFIG_OPTIONS'} = $value;
  }

  if ( exists( $self->{'_CONFIG_OPTIONS'} ) ) {
    return $self->{'_CONFIG_OPTIONS'};
  }
  else {
    return undef;
  }
}

###############################################
###     end of config
###############################################

1;
