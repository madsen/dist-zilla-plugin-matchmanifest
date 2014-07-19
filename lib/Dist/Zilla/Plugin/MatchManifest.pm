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

our $VERSION = '4.02';
# This file is part of {{$dist}} {{$dist_version}} ({{$date}})

=head1 SYNOPSIS

  [MatchManifest]
  require_builder = 1 ; this is the default and should seldom be changed

=head1 DESCRIPTION

If included, this plugin will ensure that the distribution contains a
F<MANIFEST> file and that its contents match the files collected by
Dist::Zilla.  If not, it will display the differences and offer to
update the F<MANIFEST>.

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

MatchManifest must come after your MakeMaker or ModuleBuild plugin, so
that it can see any F<Makefile.PL> or F<Build.PL> generated.

=cut

use Moose 0.65;                 # attr fulfills requires
use Moose::Autobox 0.09;        # flattten
with 'Dist::Zilla::Role::InstallTool';

use autodie ':io';

=attr require_builder

For safety, MatchManifest aborts if it doesn't see a F<Makefile.PL> or
F<Build.PL> in your dist.  If C<[MatchManifest]> is listed before
C<[MakeMaker]> in your F<dist.ini>, then the manifest will be checked
before F<Makefile.PL> has been added, which is bad.

If you really want to create a dist with no F<Makefile.PL> or
F<Build.PL>, you can set C<require_builder> to 0 to skip this check.

=cut

has require_builder => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

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
  my $builder_found;

  my $manifest = $files->map(sub {
    my $name = $_->name;
    ++$builder_found if $name eq 'Makefile.PL' or $name eq 'Build.PL';
    return $name unless $name =~ /[ '\\]/;
    $name =~ s/\\/\\\\/g;
    $name =~ s/'/\\'/g;
    return qq{'$name'};
  })->sort->join("\n") . "\n";

  if (not $builder_found and $self->require_builder) {
    $self->log_fatal(<<'END ERROR');
No Makefile.PL or Build.PL found!
[MatchManifest] must come after [MakeMaker] or [ModuleBuild].
Otherwise, the files they generate won't be listed in MANIFEST.
Set require_builder = 0 if you really want a dist with no Makefile.PL.
END ERROR
  }

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
  $self->log_fatal("Aborted because of MANIFEST mismatch")
      unless $self->zilla->chrome->prompt_yn("Update MANIFEST?",
                                             { default => 0 });

  # Update the MANIFEST in the distribution:
  $manifestFile->content($manifest);

  # And the original on disk:
  open(my $out, '>:raw:utf8', $onDisk);
  print $out $manifest;
  close $out;

  $self->log_debug("Updated MANIFEST");
} # end setup_installer

#---------------------------------------------------------------------
__PACKAGE__->meta->make_immutable;
no Moose;
1;

=for Pod::Coverage
setup_installer
