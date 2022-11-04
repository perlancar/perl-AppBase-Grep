package AppBase::Grep::File;

use strict;
use warnings;

our %argspecs_files = (
    files => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'file',
        schema => ['array*', of=>'filename*'],
        pos => 1,
        slurpy => 1,
    },
    recursive => {
        summary => 'Read all files under each directory, recursively, following symbolic links only if they are on the command line',
        schema => 'true*',
        cmdline_aliases => {r => {}},
    },
    dereference_recursive => {
        summary => 'Read all files under each directory, recursively, following all symbolic links, unlike -r',
        schema => 'true*',
        cmdline_aliases => {R => {}},
    },
);

# will set $args->{_source}
sub set_source_arg {
    my $args = shift;

    my @files = @{ $args->{files} // [] };

    # pattern (arg0) can actually be a file or regexp
    if (defined $args->{pattern}) {
        if ($args->{regexps} && @{ $args->{regexps} }) {
            unshift @files, delete $args->{pattern};
        } else {
            unshift @{ $args->{regexps} }, delete $args->{pattern};
        }
    }

    my $show_label = 0;
    if (!@files) {
        $file = "(stdin)";
        $fh = \*STDIN;
    } elsif (@files > 1) {
        $show_label = 1;
    }

    $args->{_source} = sub {
      READ_LINE:
        {
            if (!defined $fh) {
                return unless @files;
                $file = shift @files;
                log_trace "Opening $file ...";
                open $fh, "<", $file or do {
                    warn "abgrep: Can't open '$file': $!, skipped\n";
                    undef $fh;
                };
                redo READ_LINE;
            }

            my $line = <$fh>;
            if (defined $line) {
                return ($line, $show_label ? $file : undef);
            } else {
                undef $fh;
                redo READ_LINE;
            }
        }
    };
}

1;
# ABSTRACT: Resources for AppBase::Grep-based scripts that use file sources

=head1 FUNCTIONS

=head2 set_source_arg
