package AppBase::Grep;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

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
            default => 'auto',
            tags => ['category:general-output-control'],
        },
        quiet => {
            schema => ['true*'],
            cmdline_aliases => {silent=>{}, q=>{}},
            tags => ['category:general-output-control'],
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
    my $pat        = $opt_ci ? qr/$args{pattern}/i : qr/$args{pattern}/;

    my $color = $args{color} // 'auto';
    my $use_color;
    if ($color eq 'always') {
        $use_color = 1;
    } elsif ($color eq 'never') {
        $use_color = 0;
    } else {
        $use_color = (-t STDOUT);
    }
    my $source = $args{_source};

    my $linum = 0;
    my $num_matches = 0;
    my ($line, $label);

    my $code_print = sub {
        my $highlight = shift;
        if ($highlight) {
            $line =~ s/($pat)/\e[1;31m$1\e[0m/g;
            print $line;
        } else {
            print $line;
        }
    };

    while (1) {
        ($line, $label) = $source->();
        last unless defined $line;
        $linum++;

        my $is_match = 0;
        if ($line =~ $pat) {
            $is_match = 1;
            next if $opt_invert;
            if ($opt_quiet || $opt_count) {
                $num_matches++;
            } else {
                $code_print->($use_color);
            }
        } else {
            next unless $opt_invert;
            if ($opt_quiet || $opt_count) {
                $num_matches++;
            } else {
                $code_print->(0);
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
