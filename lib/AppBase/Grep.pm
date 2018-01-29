package AppBase::Grep;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

our %Colors = (
    label     => "\e[35m",   # magenta
    separator => "\e[36m",   # cyan
    linum     => "\e[32m",   # green
    match     => "\e[1;31m", # bold red
);

$SPEC{grep} = {
    v => 1.1,
    summary => 'A base for grep-like CLI utilities',
    description => <<'_',

This routine provides a base for grep-like CLI utilities. It accepts coderef as
source of lines, which in the actual utilities can be from files or other
sources. It provides common options like `-i`, `-v`, highlighting, and so on.

_
    args => {
        pattern => {
            schema => 're*',
            req => 1,
            pos => 0,
        },

        ignore_case => {
            schema => 'bool*',
            cmdline_aliases => {i=>{}},
            tags => ['category:matching-control'],
        },
        invert_match => {
            summary => 'Invert the sense of matching',
            schema => 'bool*',
            cmdline_aliases => {v=>{}},
            tags => ['category:matching-control'],
        },
        count => {
            summary => 'Supress normal output, return a count of matching lines',
            schema => 'true*',
            cmdline_aliases => {c=>{}},
            tags => ['category:general-output-control'],
        },
        color => {
            schema => ['str*', in=>[qw/never always auto/]],
            tags => ['category:general-output-control'],
        },
        quiet => {
            schema => ['true*'],
            cmdline_aliases => {silent=>{}, q=>{}},
            tags => ['category:general-output-control'],
        },

        line_number => {
            schema => ['true*'],
            cmdline_aliases => {n=>{}},
            tags => ['category:output-line-prefix-control'],
        },
        # XXX max_count
        # word_regexp (-w) ?
        # line_regexp (-x) ?
        # --after-context (-A)
        # --before-context (-B)
        # --context (-C)
    },
};
sub grep {
    my %args = @_;

    my $opt_ci     = $args{ignore_case};
    my $opt_invert = $args{invert_match};
    my $opt_count  = $args{count};
    my $opt_quiet  = $args{quiet};
    my $opt_linum  = $args{line_number};
    my $pat        = $opt_ci ? qr/$args{pattern}/i : qr/$args{pattern}/;

    my $color = $args{color} //
        (defined $ENV{COLOR} ? ($ENV{COLOR} ? 'always' : 'never') : undef) //
        'auto';

    my $use_color;
    if ($color eq 'always') {
        $use_color = 1;
    } elsif ($color eq 'never') {
        $use_color = 0;
    } else {
        $use_color = (-t STDOUT);
    }
    my $source = $args{_source};

    my $num_matches = 0;
    my ($line, $label, $linum);

    my $code_print = sub {
        if (defined $label && length $label) {
            if ($use_color) {
                print "$Colors{label}$label\e[0m$Colors{separator}:\e[0m";
            } else {
                print $label, ":";
            }
        }

        if ($opt_linum) {
            if ($use_color) {
                print "$Colors{linum}$linum\e[0m$Colors{separator}:\e[0m";
            } else {
                print $linum, ":";
            }
        }

        if ($use_color && !$opt_invert) {
            $line =~ s/($pat)/$Colors{match}$1\e[0m/g;
            print $line;
        } else {
            print $line;
        }
    };

    my $prevlabel;
    while (1) {
        ($line, $label) = $source->();
        last unless defined $line;

        $label //= '';

        if ($opt_linum) {
            if (!defined $prevlabel) {
                $prevlabel = $label;
                $linum = 1;
            } else {
                if ($label ne $prevlabel) {
                    $prevlabel = $label;
                    $linum = 1;
                } else {
                    $linum++;
                }
            }
        }

        my $is_match = 0;
        if ($line =~ $pat) {
            $is_match = 1;
            next if $opt_invert;
            if ($opt_quiet || $opt_count) {
                $num_matches++;
            } else {
                $code_print->();
            }
        } else {
            next unless $opt_invert;
            if ($opt_quiet || $opt_count) {
                $num_matches++;
            } else {
                $code_print->();
            }
        }
    }

    return [
        200,
        "OK",
        $opt_count ? $num_matches : "",
        {"cmdline.exit_code"=>$num_matches ? 0:1},
    ];
}

1;
# ABSTRACT:


=head1 ENVIRONMENT

=head2 COLOR

Boolean. If set to true, will set default C<--color> to C<always> instead of
C<auto>. If set to false, will set default C<--color> to C<never> instead of
C<auto>. This behavior is not in GNU grep.
