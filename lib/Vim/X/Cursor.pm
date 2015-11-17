package Vim::X::Cursor;
our $AUTHORITY = 'cpan:YANICK';
# ABSTRACT: A window cursor in Vim
$Vim::X::Cursor::VERSION = '1.3.0';
use strict;
use warnings;

use Vim::X;
use Carp;

use Moo;


has window => (
    is => 'ro',
    required => 1,
);

has line => ( is => 'rw', required => 1 );
has col  => ( is => 'rw', required => 1 );

before line => sub {
    return unless @_ == 2;
    my( $cursor, $line ) = @_;
    $cursor->window->_window->Cursor( $line, $cursor->col );
};

before col => sub {
    return unless @_ == 2;
    my( $cursor, $col ) = @_;
    $cursor->window->_window->Cursor( $cursor->line, $col );
};

sub append {
    my( $self, $stuff ) = @_;

    my $line = $self->line;
    my $content = $line->content;
    substr( $content, $self->col + 1, 0 ) = $stuff;
    $line->content($content);
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Vim::X::Cursor - A window cursor in Vim

=head1 VERSION

version 1.3.0

=head1 FUNCTIONS

=head2 window()

Returns the  L<Vim::X::Window> of the cursor.

=head1 AUTHOR

Yanick Champoux <yanick@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Yanick Champoux.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
