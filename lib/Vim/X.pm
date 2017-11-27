package Vim::X;
# ABSTRACT: Candy for Perl programming in Vim

use strict;
use warnings;

use Sub::Attribute;
use Path::Tiny;

use parent 'Exporter';

our @EXPORT = qw/ 
    vim_func vim_prefix vim_msg vim_buffer vim_cursor vim_window
    vim_current_file
    vim_command
    vim_expand
    vim_call
    vim_lines
    vim_append
    vim_eval
    vim_range
    vim_line
    vim_input
vim_delete /;

use Vim::X::Window;
use Vim::X::Buffer;
use Vim::X::Cursor;
use Vim::X::Line;

sub import {
    __PACKAGE__->export_to_level(1, @_);
    my $target_class = caller;


    eval <<"END";
    package $target_class;
    use Sub::Attribute;
    sub Vim :ATTR_SUB { goto &Vim::X::Vim; }
END

}

sub Vim :ATTR_SUB {
    no warnings 'uninitialized';

    my( $class, $sym_ref, undef, undef, $attr_data ) = @_;

    my $name = *{$sym_ref}{NAME};

    my $args = $attr_data =~ 'args' ? '...' : undef;

    my $range = 'range' x ( $attr_data =~ /range/ );

    no strict 'refs';
    VIM::DoCommand(<<END);
function! $name($args) $range
    perl \$Vim::X::RETURN = ${class}::$name( split "\\n", scalar VIM::Eval('a:000'))
    perl \$Vim::X::RETURN =~ s/'/''/g
    perl Vim::X::vim_command( "let g:vimx_return = '\$Vim::X::RETURN'" )
    return g:vimx_return
endfunction
END

    return;
}

=func load_function_dir( $library_dir)

Looks into the given I<$library_dir> and imports the functions in all
files with the extension C<.pl> (non-recursively).
Each file must have the name of its main
function to be imported to Vim-space.

To have good start-up time and to avoid loading all dependencies for
all functions, the different files aren't sourced at start-up, but are
rather using the C<autocmd> function of Vim to trigger the loading
of those files only if used.

E.g.,

    # in ~/.vim/vimx/perlweekly/PWGetInfo.pl
    use Vim::X;

    use LWP::UserAgent;
    use Web::Query;
    use Escape::Houdini;

    sub PWGetInfo :Vim() {
        ...;
    }

    # in .vimrc
    perl use Vim::X;

    autocmd BufNewFile,BufRead **/perlweekly/src/*.mkd 
                \ perl Vim::X::load_function_dir('~/.vim/vimx/perlweekly')
    autocmd BufNewFile,BufRead **/perlweekly/src/*.mkd 
                \ map <leader>pw :call PWGetInfo()<CR>

=cut

sub load_function_dir {
    my $dir = shift;

    my @files = <$dir/*.pl>; 

    for my $f ( @files ) {
        my $name = _func_name($f);
        vim_command( 
            "au FuncUndefined $name perl Vim::X::load_function_file('$f')" 
        );
    }
}

=func source_function_dir( $library_dir )

Like C<load_function_dir>, but if it finds files with the exension C<.pvim>, 
it'll also source them as C<vimL> files at
load-time, allowing to define both the Perl bindings and the vim macros in the
same file. Note that, magically, the Perl code will still only be compiled if the function
is invoked.

For that special type of magic to happen, the C<.pvim> files must follow a certain pattern to
be able to live their double-life as Perl scripts and vim file:

    ""; <<'finish';

    " your vim code goes here

    finish

    # the Perl code goes here


When sourced as a vim script, the first line is considered a comment and
ignored, and the rest is read until it hits C<finish>, which cause Vim to 
stop reading the file. When read as a Perl file, the first line contains a
heredoc that makes all the Vim code into an unused string, so basically ignore
it in a fancy way.

For example, the snippet for C<load_function_dir> could be rewritten as such:

    # in ~/.vim/vimx/perlweekly/PWGetInfo.pvim
    ""; <<'finish';

        map <leader>pw :call PWGetInfo()<CR>

    finish

    use Vim::X;

    use LWP::UserAgent;
    use Web::Query;
    use Escape::Houdini;

    sub PWGetInfo :Vim() {
        ...;
    }

    # in .vimrc
    perl use Vim::X;

    autocmd BufNewFile,BufRead **/perlweekly/src/*.mkd 
                \ perl Vim::X::source_function_dir('~/.vim/vimx/perlweekly')

=cut

sub source_function_dir {
    my $dir = shift;

    my @files = ( <$dir/*.pl>, <$dir/*.pvim> );

    for my $f ( @files ) {
        my $name = _func_name($f);
        vim_command( "source $f" ) if $f =~ /\.pvim$/;
        vim_command( 
            "au FuncUndefined $name perl Vim::X::load_function_file('$f')" 
        );
    }
}

sub _func_name {
    my $name = shift;
    $name =~ s#^.*/##;
    $name =~ s#\.p(?:l|vim)$##;
    return $name;
}

=func load_function_file( $file_path )

Loads the code within I<$file_path> under the namespace
I<Vim::X::Function::$name>, where name is the basename of the I<$file_path>,
minus the C<.pl>/C<.pvim> extension. Not that useful by itself, but used by 
C<load_function_dir>.

=cut

sub load_function_file {
    my $file = shift;

    my $name = _func_name($file);

    eval "{ package Vim::X::Function::$name;\n" 
       . "no warnings;\n"
       . Path::Tiny::path($file)->slurp
       . "\n}"
       ;

    vim_msg( "ERROR: $@" ) if $@;

    return '';

}

unless ( $main::curbuf ) {
    package 
        VIM;
    no strict;
    sub AUTOLOAD {
        # warn "calling $AUTOLOAD";
    }
}

=func vim_msg( @text )

Display the strings of I<@text> concatenated as a vim message.

    vim_msg "Hello from Perl";

=cut

sub vim_msg {
    VIM::Msg( join " ", @_ );
}

sub vim_prefix {
    my( $prefix ) = @_;

    $Vim::X::PREFIX = $prefix; 
}

=func vim_buffer( $i )

Returns the L<Vim::X::Buffer> object associated with the I<$i>th buffer. If
I<$i> is not given or set to '0', it returns the current buffer.

=cut

sub vim_buffer {
    my $buf = shift // $::curbuf->Number;

    return Vim::X::Buffer->new( index => $buf, _buffer => $::curbuf );
}

=func vim_current_file($local)

Returns the file associated with the current buffer as a L<Path::Tiny>
object. If C<$local> is true the path will be relative to the directory
where C<vim> was launched, otherwise it'll be absolute.

=cut

sub vim_current_file {
    my $symbol = '%' . ( ':p' x ! shift );

    my $r = vim_expand( $symbol ) or return;

    return Path::Tiny::path( $r ); 
}

=func vim_lines( @indexes )

Returns the L<Vim::X::Line> objects for the lines in I<@indexes> of the
current buffer. If no index is given, returns all the lines of the buffer.

=cut

sub vim_lines {
    vim_buffer->lines(@_);
}

=func vim_line($index) 

Returns the L<Vim::X::Line> object for line I<$index> of the current buffer.
If I<$index> is not given, returns the line at the cursor.

=cut

sub vim_line {
    @_ ? vim_buffer->line(shift) : vim_cursor()->line;
}

=func vim_append(@lines) 

Appends the given lines after the line under the cursor.

If carriage returns are present in the lines, they will be split in
consequence.

=cut

sub vim_append {
    vim_cursor()->line->append(@_);
}

=func vim_eval(@expressions)

Evals the given C<@expressions> and returns their results.

=cut

sub vim_eval {
    my @results = map { scalar VIM::Eval($_) } @_;
    return wantarray ? @results : $results[0];
}

=func vim_range($from, $to)

=func vim_range($line)

=func vim_range()

Returns a L<Vim::X::Range> object for the given lines, or single line,
in the current buffer. The lines can be passed as indexes, or L<Vim::X::Line>
objects.

If no line whatsoever is passed, the range will be the one on 
which the command has been called (i.e.: C<:afirstline> and C<a:lastline>).

=cut

sub vim_range {
    my @range = map { 0 + $_ } @_ == 2 ? @_
                             : @_ == 1 ? ( @_ ) x 2
                             : map { vim_eval($_) } qw/ a:firstline a:lastline /;

    return vim_buffer->range( @range );
}

=func vim_command( @commands )

Run the given 'ex' commands and return their results.

    vim_command 'normal 10G', 'normal iHi there!';

=cut

sub vim_command {
    my @results = map { VIM::DoCommand($_) } @_;
    return wantarray ? @results : $results[0];
}

=func vim_call( $function, @args )

Calls the vim-space function I<$function> with the 
provided arguments.

    vim_call( 'SetVersion', '1.23' )

    # equivalent of doing 
    #    :call SetVersion( '1.23' )
    # in vim

=cut

sub vim_call {
    my( $func, @args ) = @_;
    my $cmd = join ' ', 'call', $func . '(', map( { "'$_'" } @args ), ')';
    vim_command( $cmd );
}

=func vim_expand( @expressions )

Returns the expansion of the passed expression(s).

    my $current_file = vim_expand( '%' );
    my ( $local, $absolute) = vim_expand( '%', '%:p' );

=cut

sub vim_expand {
    my @mapped = map { vim_eval( "expand('$_')" ) } @_;
    return wantarray ? @mapped : $mapped[0];
}

=func vim_input( $prompt, $default, $completion_arg )

Prompts the user for some value. The arguments are the same
as for vim's own C<input>.

=cut

sub vim_input {
    my @args = @_;
    s/"/\\"/g for @args;

    my $args = join ',', map { qq{"$_"} } @args;

    vim_command( "let l = input($args)" );
    return vim_eval("l");
}

=func vim_window( $i )

Returns the L<Vim::X::Window> associated with the I<$i>th window. If I<$i>
is not provided or is zero, returns the object for the current window.

=cut

sub vim_window {
    return Vim::X::Window->new( _window => shift || $::curwin);
}

=func vim_cursor

Returns the L<Vim::X::Cursor> associated with the position of the cursor
in the current window.

=cut

sub vim_cursor {
    my $w = vim_window();
    return $w->cursor;
}

=func vim_delete( @lines ) 

Deletes the given lines from the current buffer.

=cut

sub vim_delete {
    vim_buffer->delete(@_);
}

1;

=head1 SYNOPSIS

    package Vim::X::Plugin::MostUsedVariable;

    use strict;
    use warnings;

    use Vim::X;

    sub MostUsedVariable :Vim {
        my %var;

        for my $line ( vim_lines ) {
            $var{$1}++ while $line =~ /[$@%](\w+)/g;
        }

        my ( $most_used ) = reverse sort { $var{$a} <=> $var{$b} } keys %var;

        vim_msg "variable name $most_used used $var{$most_used} times";
    }

and then in your C<.vimrc>:

    perl push @INC, '/path/to/plugin/lib';
    perl use Vim::X::Plugin::MostUsedVariable;

    map <leader>m :call MostUsedVariable()

=head1 DESCRIPTION

I<Vim::X> provides two tools to make writing Perl functions for Vim a little
easier: it auto-exports functions tagged by the attribute C<:Vim> in
Vim-space, and it defines a slew of helper functions and objects that are a
little more I<Do What I Mean> than the I<VIM> API module that comes with Vim
itself.

Obviously, for this module to work, Vim has to be compiled with Perl interpreter
support.

=head2 Import Perl function in Vim-space

Function labeled with the C<:Vim> attribute are automatically exported to Vim.

The C<:Vim> attribute accepts two optional parameters: C<args> and C<range>. 

=head3 :Vim(args)

If C<args> is present, the function will be exported expecting arguments, that
will be passed to the function via the usual C<@_> way.

    sub Howdie :Vim(args) {
        vim_msg( "Hi there, ", $_[0] );
    }

    # and then in vim:
    call Howdie("buddy")

=head3 :Vim(range)

If C<range> is present, the function will be called only once when invoked
over a range, instead than once per line (which is the default behavior).


    sub ReverseLines :Vim(range) {
        my @lines = reverse map { "$_" } vim_range();
        for my $line ( vim_range ) {
            $line <<= pop @lines;
        }
    }

    # and then in vim:
    :5,15 call ReverseLines()

=head3 Loading libraries

If your collection of functions is growing, 
C<load_function_dir()> can help with their management. See that function below
for more details.



=head1 SEE ALSO

The original blog entry: L<http://techblog.babyl.ca/entry/vim-x>

=head3 CONTRIBUTORS

Hernan Lopes


