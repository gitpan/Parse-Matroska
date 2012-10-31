use 5.008;
use strict;
use warnings;

# ABSTRACT: Module collection to parse Matroska files.
package Parse::Matroska;
{
  $Parse::Matroska::VERSION = '0.001';
}
=head1 NAME

Parse::Matroska

=head1 VERSION

version 0.001

=head1 ABSTRACT

Module collection to parse Matroska files.

=head1 DESCRIPTION

C<use>s L<Parse::Matroska::Reader>. See the documentation
of the modules mentioned in L</"SEE ALSO"> for more information
in how to use this module.

=head1 SEE ALSO

L<Parse::Matroska::Reader>, L<Parse::Matroska::Element>,
L<Parse::Matroska::Definitions>.

=cut

use Parse::Matroska::Reader;

1;
