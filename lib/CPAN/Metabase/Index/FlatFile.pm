# Copyright (c) 2008 by Ricardo Signes. All rights reserved.
# Licensed under terms of Perl itself (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License was distributed with this file or you may obtain a 
# copy of the License from http://dev.perl.org/licenses/

package CPAN::Metabase::Index::FlatFile;
use Moose;
use Moose::Util::TypeConstraints;

use Carp ();
use Fcntl ':flock';
use IO::File ();
use JSON::XS;

our $VERSION = '0.01';
$VERSION = eval $VERSION; # convert '1.23_45' to 1.2345

with 'CPAN::Metabase::Index';

subtype 'File' 
    => as 'Object' 
        => where { $_->isa( "Path::Class::File" ) };

coerce 'File' 
    => from 'Str' 
        => via { Path::Class::file($_) };

has 'index_file' => (
    is => 'ro', 
    isa => 'File',
    coerce => 1,
    required => 1, 
);

sub add {
    my ($self, $fact) = @_;
    Carp::confess( "can't index a Fact without a GUID" ) unless $fact->guid;

    my %metadata = (
      'core.type'           => [ Str => $fact->type            ],
      'core.schema_version' => [ Num => $fact->schema_version  ],
      'core.guid'           => [ Str => $fact->guid            ],
      'core.created_at'     => [ Num => $fact->created_at      ],
    );

    for my $type (qw(content resource)) {
      my $method = "$type\_metadata";
      my $data   = $fact->$method;

      for my $key (keys %$data) {
        # I'm just starting with a strict-ish set.  We can tighten or loosen
        # parts of this later. -- rjbs, 2009-03-28
        die "invalid metadata key" unless $key =~ /\A[-_a-z0-9.]+\z/;
        $metadata{ "$type.$key" } = $data->{$key};
      }
    }
    
    my $line = JSON::XS->new->encode(\%metadata);

    my $filename = $self->index_file;

    my $fh = IO::File->new( $filename, "a+" )
        or Carp::confess( "Couldn't append to '$filename': $!" );
    $fh->binmode(':raw');

    flock $fh, LOCK_EX;
    {   
        seek $fh, 2, 0; # end
        print {$fh} $line, "\n";
    }

    $fh->close;
}

sub search {
    my ($self, %spec) = @_;

    my $filename = $self->index_file;
    
    my $fh = IO::File->new( $filename, "r" )
        or Carp::confess( "Couldn't read from '$filename': $!" );
    $fh->binmode(':raw');

    my @matches;
    flock $fh, LOCK_SH;
    {
        while ( my $line = <$fh> ) {
            my $parsed = JSON::XS->new->decode($line);
            push @matches, $parsed->{'core.guid'}[1] if _match($parsed, \%spec);
        }
    }    
    $fh->close;

    return \@matches;
}

sub exists {
    my ($self, $guid) = @_;
    return scalar @{ $self->search( 'core.guid' => $guid ) };
}

sub _match {
    my ($parsed, $spec) = @_;
    for my $k ( keys %$spec ) {
        return unless  defined($parsed->{$k}) 
                    && defined($spec->{$k}) 
                    && $parsed->{$k}[1] eq $spec->{$k};
    }
    return 1;
}

1;

=head1 NAME

CPAN::Metabase::Index::FlatFile - CPAN::Metabase flat-file index

=head1 SYNOPSIS


=head1 DESCRIPTION

Description...

=head1 USAGE

Usage...

=head1 BUGS

Please report any bugs or feature using the CPAN Request Tracker.  
Bugs can be submitted through the web interface at 
L<http://rt.cpan.org/Dist/Display.html?Queue=CPAN-Metabase>

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

=head1 AUTHOR

=over 

=item *

David A. Golden (DAGOLDEN)

=item *

Ricardo J. B. Signes (RJBS)

=back

=head1 COPYRIGHT AND LICENSE

 Portions copyright (c) 2008 by David A. Golden
 Portions copyright (c) 2008 by Ricardo J. B. Signes

Licensed under terms of Perl itself (the "License").
You may not use this file except in compliance with the License.
A copy of the License was distributed with this file or you may obtain a 
copy of the License from http://dev.perl.org/licenses/

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut
