package Bio::PanGenome::ExtractProteomeFromGFF;

# ABSTRACT: Take in a GFF file and create protein sequences in FASTA format

=head1 SYNOPSIS

Take in GFF files and create protein sequences in FASTA format
   use Bio::PanGenome::ExtractProteomeFromGFF;
   
   my $obj = Bio::PanGenome::ExtractProteomeFromGFF->new(
       gff_file        => $fasta_file,
     );
   $obj->fasta_file();

=cut

use Moose;
use Cwd;
use Bio::PanGenome::Exceptions;
use File::Basename;
use File::Temp;

has 'gff_file' => ( is => 'ro', isa => 'Str', required => 1 );
has 'fasta_file' => ( is => 'ro', isa => 'Str', lazy => 1, builder => '_build_fasta_files' );

has '_working_directory' =>
  ( is => 'ro', isa => 'File::Temp::Dir', default => sub { File::Temp->newdir( DIR => getcwd, CLEANUP => 1 ); } );
has '_working_directory_name' => ( is => 'ro', isa => 'Str', lazy => 1, builder => '_build__working_directory_name' );


sub _build_fasta_files
{
  my ($self) = @_;
  $self->_extract_nucleotide_regions;
  $self->_convert_nucleotide_to_protein;
  return $self->_output_filename;
}

sub _build__working_directory_name {
    my ($self) = @_;
    return $self->_working_directory->dirname();
}

sub _output_filename {
    my ( $self ) = @_;
    my ( $filename, $directories, $suffix ) = fileparse( $self->gff_file, qr/\.[^.]*/ );
    return join( '/', ( $self->_working_directory_name, $filename . '.faa' ) );
}

sub _bed_output_filename {
    my ($self) = @_;
    return join( '.', ( $self->_output_filename, 'intermediate.bed' ) );
}

sub _nucleotide_fasta_file_from_gff_filename {
    my ($self) = @_;
    return join( '.', ( $self->_output_filename, 'intermediate.fa' ) );
}

sub _extracted_nucleotide_fasta_file_from_bed_filename {
    my ($self) = @_;
    return join( '.', ( $self->_output_filename, 'intermediate.extracted.fa' ) );
}

sub _create_bed_file_from_gff {
    my ($self) = @_;
    my $cmd =
        'sed -n \'/##gff-version 3/,/##FASTA/p\' '
      . $self->gff_file
      . ' | grep -v \'^#\' | awk \'{print $1"\t"($4-1)"\t"($5)"\t"$9"\t1\t"$7}\' | sed \'s/ID=//\' | sed \'s/;[^\t]*\t/\t/g\' > '
      . $self->_bed_output_filename;
    system($cmd);
}

sub _create_nucleotide_fasta_file_from_gff {
    my ($self) = @_;
    my $cmd =
        'sed -n \'/##FASTA/,//p\' '
      . $self->gff_file
      . ' | grep -v \'##FASTA\' > '
      . $self->_nucleotide_fasta_file_from_gff_filename;
    system($cmd);
}

sub _extract_nucleotide_regions {
    my ($self) = @_;

    $self->_create_nucleotide_fasta_file_from_gff;
    $self->_create_bed_file_from_gff;

    my $cmd =
        'bedtools getfasta -fi '
      . $self->_nucleotide_fasta_file_from_gff_filename
      . ' -bed '
      . $self->_bed_output_filename
      . ' -fo '
      . $self->_extracted_nucleotide_fasta_file_from_bed_filename
      . ' -name > /dev/null 2>&1';
      system($cmd);
      unlink($self->_nucleotide_fasta_file_from_gff_filename);
      unlink($self->_bed_output_filename);
      unlink($self->_nucleotide_fasta_file_from_gff_filename.'.fai');
}

sub _fastatranslate_filename {
    my ($self) = @_;
    return join( '.', ( $self->_output_filename, 'intermediate.translate.fa' ) );
}

sub _fastatranslate_cmd
{
  my ($self) = @_;
  return 'fastatranslate --geneticcode 11  -f '. $self->_extracted_nucleotide_fasta_file_from_bed_filename.' >> '.$self->_fastatranslate_filename;
}

sub _convert_nucleotide_to_protein
{
  my ($self) = @_;
  system($self->_fastatranslate_cmd(1));
  # Only keep sequences which have a start and stop codon.
  my $cmd = 'fasta_grep -f '.$self->_fastatranslate_filename.' > '.$self->_output_filename;
  unlink($self->_extracted_nucleotide_fasta_file_from_bed_filename);
  system($cmd);
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;

