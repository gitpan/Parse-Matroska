use 5.008;
use strict;
use warnings;

package Parse::Matroska::Element;
{
  $Parse::Matroska::Element::VERSION = '0.001';
}
=head1 NAME

Parse::Matroska::Element

=head1 VERSION

version 0.001

=cut
use Carp;
use List::Util qw{first};

=head1 SYNOPSIS

    use Parse::Matroska::Reader;
    my $reader = Parse::Matroska::Reader->new($path);
    my $elem = $reader->read_element;

    print "ID: $elem->{elid}\n";
    print "Name: $elem->{name}\n";
    print "Length: $elem->{content_len}\n";
    print "Type: $elem->{type}\n";
    print "Child count: ", scalar(@{$elem->all_children}), "\n";
    if ($elem->{type} eq 'sub') {
        while (my $chld = $elem->next_child) {
            print "Child Name: $chld->{name}\n";
        }
    } else {
        print "Value: ", $elem->get_value, "\n";
    }

=head1 DESCRIPTION

Represents a single Matroska element as decoded by
L<Parse::Matroska::Reader>. This is essentially a hash
augmented with functions for delay-loading of binary
values and children elements.

=head1 NOTE

The API of this module is not yet considered stable.

=head1 FIELDS

=over

=item elid

The EBML Element ID, suitable for passing to
L<Parse::Matroska::Definitions/elem_by_hexid>.

=item name

The EBML Element's name.

=item type

The EBML Element's type. Can be 'uint', 'sint',
'float', 'ebml_id', 'str' or 'binary'. See L</value>
for details.

=item value

The EBML Element's value. Should be obtained through
L</get_value>.

Is an unicode string if the L</type> is C<str>, that is,
the string has already been L<Encode/decode>d.

Is undef if the L</type> is C<binary> and the contents
were delay-loaded and not yet read. L</get_type> will
do the delayed load if needed.

Is an arrayref if the L</type> is C<sub>, containing
the children nodes that were already loaded.

Is a hashref if the L</type> is C<ebml_id>, containing
the referred element's information as defined in
L<Parse::Matroska::Definitions>. Calling
C<elem_by_hexid($elem-E<gt>{value}-E<gt>{elid})> will
return the same object as $elem->{value}.

=item full_len

The entire length of this EBML Element, including
the header.

=item size_len

The length of the size marker. Used when calculating
L</full_len> from L</content_len>

=item content_len

The length of the contents of this EBML Element,
excluding the header.

=item reader

A weakened reference to the associated
L<Parse::Matroska::Reader>.

=back

=head1 METHODS

=over

=item new(%hash)

Creates a new Element initialized with the hash
given as argument.

=cut
sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;

    $self->initialize(@_);
    return $self;
}

=item initialize(%hash)

Called by new on initialization.

=cut
sub initialize {
    my ($self, %args) = @_;
    for (keys %args) {
        $self->{$_} = $args{$_};
    }
    $self->{depth} = 0 unless $self->{depth};
}

=item skip

Called by the user to ignore the contents of this EBML node.
Needed when ignoring the children of a node.

=cut
sub skip {
    my ($self) = @_;
    my $reader = $self->{reader};
    return unless $reader; # we don't have to skip if there's no reader
    my $pos = $reader->getpos;
    croak "Too late to skip, reads were already done"
        if $pos ne $self->{data_pos};
    $reader->skip($self->{content_len});
}

=item get_value(keep_bin)

Returns the value contained by this EBML element.

If the element has children, returns an arrayref to
the children elements that were already encountered.

If the element's type is "binary" and the value was
delay-loaded, does the reading now.

=cut
sub get_value {
    my ($self, $keep_bin) = @_;

    return undef if $self->{type} eq 'skip';
    return $self->{value} if $self->{value};

    my $reader = $self->{reader} or
        croak "The associated Reader has been deleted";

    # delay-loaded 'binary'
    if ($self->{type} eq 'binary') {
        croak "Cannot seek in the current Reader" unless $self->{data_pos};
        # seek to the data position...
        $reader->setpos($self->{data_pos});
        # read the data, keeping it in value if requested
        if ($keep_bin) {
            $self->{value} = $reader->readlen($self->{content_len});
            return $self->{value};
        } else {
            return $reader->readlen($self->{content_len});
        }
    }
}

=item next_child(read_bin)

Builtin iterator; reads and returns the next child element.
Returns undef if the type isn't 'sub'; returns undef at
the end of the iterator and resets itself to point to the
first element.

The optional C<read_bin> parameter has the children elements
not delay-load their value if their type is 'binary'.

If all children elements have already been read, return
the elements in-order as would be given by L</all_children>.

=cut
sub next_child {
    my ($self, $read_bin) = @_;
    return unless $self->{type} eq 'sub';

    if ($self->{_all_children_read}) {
        my $idx = $self->{_last_child} ||= 0;
        if ($idx == @{$self->{value}}) {
            # reset the iterator, returning undef once
            $self->{_last_child} = 0;
            return;
        }
        my $ret = $self->{value}->[$idx];

        ++$idx;
        $self->{_last_child} = $idx;
        return $ret;
    }

    my $len = defined $self->{remaining_len}
        ? $self->{remaining_len}
        : $self->{content_len};

    if ($len == 0) {
        # we've read all children; switch into $self->{value} iteration mode
        $self->{_all_children_read} = 1;
        # return undef since the iterator will reset
        return;
    }

    $self->{pos_offset} ||= 0;
    my $pos = $self->{data_pos};
    my $reader = $self->{reader} or croak "The associated reader has been deleted";
    $reader->setpos($pos);
    $reader->{fh}->seek($self->{pos_offset}, 1) if $pos;

    my $chld = $reader->read_element($read_bin);
    return undef unless defined $chld;
    $self->{pos_offset} += $chld->{full_len};

    $self->{remaining_len} = $len - $chld->{full_len};

    if ($self->{remaining_len} < 0) {
        croak "Child elements consumed $self->{remaining_len} more bytes than parent $self->{name} contained";
    }

    $chld->{depth} = $self->{depth} + 1;
    $self->{value} ||= [];

    push @{$self->{value}}, $chld;

    return $chld;
}

=item all_children(recurse,read_bin)

Calls L</populate_children(recurse,read_bin)> on self
and returns an arrayref with the children nodes.

Both C<recurse> and C<read_bin> are optional and default
to false.

=cut
sub all_children {
    my ($self, $recurse, $read_bin) = @_;
    $self->populate_children($recurse, $read_bin);
    return $self->{value};
}

=item children_by_name(name)

Searches in the already read children elements for all
elements with the EBML name C<name>. Returns the found
element if only one was found, or an arrayref containing
all found elements. If no elements are found, an empty
arrayref is returned.

=cut
sub children_by_name {
    my ($self, $name) = @_;
    my $ret = [grep { $_->{name} eq $name } @{$self->{value}}];
    return unless @$ret;
    return $ret->[0] if @$ret == 1;
    return $ret;
}

=item populate_children(recurse,read_bin)

Populates the internal array of children elements, that is,
requests that the associated L<Matroska::Parser::Reader> reads
all children elements.

If C<recurse> is provided and is true, the method will call
itself in the children elements with the same parameters it
received; this will build a full EBML children tree.

If C<read_bin> is provided and is true, disables delay-loading
of the contents of 'binary'-type nodes, reading the contents
to memory.

If both C<recurse> and C<read_bin> are true, entire EBML trees
can be loaded without requiring seeks, thus behaving correctly
on unseekable streams. If C<read_bin> is false, the entire EBML
tree is still loaded, but calling L</get_value> on 'binary'-type
nodes will produce an error on unseekable streams.

=cut
sub populate_children {
    my ($self, $recurse, $read_bin) = @_;

    return unless $self->{type} eq 'sub';

    if (@{$self->{value}} && $recurse) {
        # only recurse
        foreach (@{$self->{value}}) {
            $_->populate_children($recurse, $read_bin);
        }
        return @{$self->{value}};
    }

    while (my $chld = $self->next_child($read_bin)) {
        $chld->populate_children($recurse, $read_bin) if $recurse;
    }

    return @{$self->{value}};
}

1;

=back

=head1 AUTHOR

Diogo Franco <diogomfranco@gmail.com>, aka Kovensky.

=head1 SEE ALSO

L<Parse::Matroska::Reader>, L<Parse::Matroska::Definitions>.

=head1 LICENSE

The FreeBSD license, equivalent to the ISC license.
