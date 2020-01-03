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
sources. It provides common options like `-i`, `-v`, `-c`, color highlighting,
and so on.

Examples of CLI utilities that are based on this: <prog:abgrep>,
<prog:grep-coin> (from <pm:App::CryptoCurrencyUtils>).

Why? For grepping lines from files or stdin, <prog:abgrep> is no match for the
standard grep (or its many alternatives): it's orders of magnitude slower and
currently has fewer options. But AppBase::Grep is a quick way to create
grep-like utilities that grep from a custom sources but have common/standard
grep features.

Compared to the standard grep, AppBase::Grep also has these unique features:

* `--all` option to match all patterns instead of just one;
* observe the `COLOR` environment variable to set `--color` default;

_
    args => {
        pattern => {
            schema => 're*',
            pos => 0,
        },
        regexps => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'regexp',
            schema => ['array*', of=>'re*'],
            cmdline_aliases => {e=>{code=>sub { $_[0]{regexps} //= []; push @{$_[0]{regexps}}, $_[1] }}},
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
        all => { # not in grep
            summary => 'Require all patterns to match, instead of just one',
            schema => 'true*',
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

    if ($ENV{COLOR_THEME}) {
        require Color::Theme::Util;
        my $theme = Color::Theme::Util::get_color_theme(
            {module_prefixes => [qw/AppBase::Grep::ColorTheme Generic::ColorTheme/]}, $ENV{COLOR_THEME});
        require Color::Theme::Util::ANSI;
        if ($theme->{colors}{label}) {
            for my $c (keys %Colors) {
                $Colors{$c} = Color::Theme::Util::ANSI::theme_color_to_ansi($theme, $c);
            }
        } elsif ($theme->{colors}{color1}) {
            my %map = (
                label     => 'color1',
                separator => 'color2',
                linum     => 'color3',
                match     => 'color4',
            );
            for my $c (keys %Colors) {
                $Colors{$c} = Color::Theme::Util::ANSI::theme_color_to_ansi(
                    $theme, $map{$c});
            }
        } else {
            warn "Unsuitable color theme '$ENV{COLOR_THEME}', ignored";
        }
    }

    my (@str_patterns, @re_patterns);
    for my $p ( grep {defined} $args{pattern}, @{ $args{regexps} // [] }) {
        push @str_patterns, $p;
        push @re_patterns , $opt_ci ? qr/$p/i : qr/$p/;
    }
    return [400, "Please specify at least one pattern"] unless @re_patterns;
    my $re_pat = join('|', @str_patterns);
    $re_pat = $opt_ci ? qr/$re_pat/i : qr/$re_pat/;

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

    my $logic = 'or';
    $logic = 'and' if $args{all};

    my $num_matches = 0;
    my ($line, $label, $linum, $chomp);

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

        if ($use_color) {
            $line =~ s/($re_pat)/$Colors{match}$1\e[0m/g;
            print $line;
        } else {
            print $line;
        }
        print "\n" if $chomp;
    };

    my $prevlabel;
    while (1) {
        ($line, $label, $chomp) = $source->();
        last unless defined $line;

        chomp($line) if $chomp;

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

        my $is_match;
        if ($logic eq 'or') {
            $is_match = 0;
            for my $re (@re_patterns) {
                if ($line =~ $re) {
                    $is_match = 1;
                    last;
                }
            }
        } else {
            $is_match = 1;
            for my $re (@re_patterns) {
                unless ($line =~ $re) {
                    $is_match = 0;
                    last;
                }
            }
        }

        if ($is_match) {
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

=head2 COLOR_THEME

String. Will search color themes in C<AppBase::Grep::ColorTheme::*> as well as
C<Generic::ColorTheme::*> modules.
