#---------------------------------------------------------------------
package Dist::Zilla::Plugin::MatchManifest;
#
# Copyright 2009 Christopher J. Madsen
#
# Author: Christopher J. Madsen <perl@cjmweb.net>
# Created: 17 Oct 2009
#
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either the
# GNU General Public License or the Artistic License for more details.
#
# ABSTRACT: Ensure that MANIFEST is correct
#---------------------------------------------------------------------

our $VERSION = '0.03';
# This file is part of {{$dist}} {{$dist_version}} ({{$date}})

=head1 SYNOPSIS

  [MatchManifest]

=head1 DESCRIPTION

If included, this plugin will ensure that the distribution contains a
F<MANIFEST> file and that its contents match the files collected by
Dist::Zilla.  If not, it will display the differences and (if STDIN &
STDOUT are TTYs) offer to update the F<MANIFEST>.

As I see it, there are 2 problems that a MANIFEST can protect against:

=over

=item 1.

A file I don't want to distribute winds up in the tarball

=item 2.

A file I did want to distribute gets left out of the tarball

=back

By keeping your MANIFEST under source control and using this plugin to
make sure it's kept up to date, you can protect yourself against both
problems.

=cut

use Moose;
use Moose::Autobox;
with 'Dist::Zilla::Role::InstallTool';

use autodie ':io';

sub setup_installer {
  my ($self, $arg) = @_;

  my $files = $self->zilla->files;

  # Find the existing MANIFEST:
  my $manifestFile = $files->grep(sub{ $_->name eq 'MANIFEST' })->head;

  # No MANIFEST; create one:
  unless ($manifestFile) {
    $manifestFile = Dist::Zilla::File::InMemory->new({
      name    => 'MANIFEST',
      content => '',
    });

    $self->add_file($manifestFile);
  } # end unless distribution already contained MANIFEST

  # List the files actually in the distribution:
  my $manifest = $files->map(sub{$_->name})->sort->join("\n") . "\n";

  return if $manifest eq $manifestFile->content;

  # We've got a mismatch.  Report it:
  require Text::Diff;

  my $onDisk = $self->zilla->root->file('MANIFEST');
  my $stat   = $onDisk->stat;

  my $diff = Text::Diff::diff(\$manifestFile->content, \$manifest, {
    FILENAME_A => 'MANIFEST (on disk)       ',
    FILENAME_B => 'MANIFEST (auto-generated)',
    CONTEXT    => 0,
    MTIME_A => $stat ? $stat->mtime : 0,
    MTIME_B => time,
  });

  $diff =~ s/^\@\@.*\n//mg;     # Don't care about line numbers
  chomp $diff;

  $self->log("MANIFEST does not match the collected files!");
  $self->zilla->chrome->logger->log($diff); # No prefix

  # See if the author wants to accept the new MANIFEST:
  $self->log_fatal("Can't prompt about MANIFEST mismatch")
      unless -t STDIN and -t STDOUT;

  $self->log_fatal("Aborted because of MANIFEST mismatch")
      unless $self->ask_yn("Update MANIFEST");

  # Update the MANIFEST in the distribution:
  $manifestFile->content($manifest);

  # And the original on disk:
  open(my $out, '>', $onDisk);
  print $out $manifest;
  close $out;

  $self->log_debug("Updated MANIFEST");
} # end setup_installer

#---------------------------------------------------------------------
sub ask_yn
{
  my ($self, $prompt) = @_;

  local $| = 1;
  print "$prompt? (y/n) ";

  my $response = <STDIN>;
  chomp $response;

  return lc $response eq 'y';
} # end ask_yn

__PACKAGE__->meta->make_immutable;
no Moose;
1;

=for Pod::Coverage
ask_yn
setup_installer
