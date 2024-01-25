package AppBase::Grep;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{grep} = {
    v => 1.1,
    summary => 'A base for grep-like CLI utilities',
    description => <<'MARKDOWN',

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

MARKDOWN
    args => {
        pattern => {
            summary => 'Specify *string* to search for',
            schema => 'str*',
            pos => 0,
        },
        regexps => {
            summary => 'Specify additional *regexp pattern* to search for',
            'x.name.is_plural' => 1,
            'x.name.singular' => 'regexp',
            schema => ['array*', of=>'str*'],
            cmdline_aliases => {e=>{code=>sub { $_[0]{regexps} //= []; push @{$_[0]{regexps}}, $_[1] }}},
        },

        ignore_case => {
            summary => 'If set to true, will search case-insensitively',
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
        dash_prefix_inverts => { # not in grep
            summary => 'When given pattern that starts with dash "-FOO", make it to mean "^(?!.*FOO)"',
            schema => 'bool*',
            description => <<'MARKDOWN',

This is a convenient way to search for lines that do not match a pattern.
Instead of using `-v` to invert the meaning of all patterns, this option allows
you to invert individual pattern using the dash prefix, which is also used by
Google search and a few other search engines.

MARKDOWN
            tags => ['category:matching-control'],
        },
        all => { # not in grep
            summary => 'Require all patterns to match, instead of just one',
            schema => 'true*',
            tags => ['category:matching-control'],
        },
        count => {
            summary => 'Supress normal output; instead return a count of matching lines',
            schema => 'true*',
            cmdline_aliases => {c=>{}},
            tags => ['category:general-output-control'],
        },
        files_with_matches => {
            summary => 'Supress normal output; instead return filenames with matching lines; scanning for each file will stop on the first match',
            schema => 'true*',
            cmdline_aliases => {l=>{}},
            tags => ['category:general-output-control'],
        },
        files_without_match => {
            summary => 'Supress normal output; instead return filenames without matching lines',
            schema => 'true*',
            cmdline_aliases => {L=>{}},
            tags => ['category:general-output-control'],
        },
        color => {
            summary => 'Specify when to show color (never, always, or auto/when interactive)',
            schema => ['str*', in=>[qw/never always auto/]],
            default => 'auto',
            tags => ['category:general-output-control'],
        },
        quiet => {
            summary => 'Do not print matches, only return appropriate exit code',
            schema => ['true*'],
            cmdline_aliases => {silent=>{}, q=>{}},
            tags => ['category:general-output-control'],
        },

        line_number => {
            summary => 'Show line number along with matches',
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

        _source => {
            schema => 'code*',
            tags => ['hidden'],
            description => <<'MARKDOWN',

Code to produce lines of text to grep form. Required.

Will be called with these arguments:

    ($instruction*)

where `$instruction` can be 1 to instruct the source to skip to the next "file"
(or source) before retrieving the next line.

Should return the following:

    ($line, $label, $chomp)

Where `$line` is the line (with newline ending, unless `$chomp` is true),
`$label` is source label (e.g. filename without line number if text source is
from files), and `$chomp` is boolean that can be set to true to indicate that
line is already chomped and should not be chomped again.

MARKDOWN
        },
        _highlight_regexp => {
            schema => 're*',
            tags => ['hidden'],
            description => <<'MARKDOWN',

Regexp pattern to capture each pattern for highlighting. Optional.

MARKDOWN
        },
        _filter_code => {
            schema => 'code*',
            tags => ['hidden'],
            description => <<'MARKDOWN',

Custom filtering. If set, then `pattern` and `regexps` arguments are not
required and lines of text will be filtered by this code. Used e.g. for grepping
custom stuffs, e.g. email address or URL from lines of text instead of plain
string or regexp patterns.

Will be called for each line of text with these arguments:

    ($line, \%args)

where `$line` is the line of text and `%args` are the arguments given to the
`grep()` function.

MARKDOWN
        },

    },
    args_rels => {
        'choose_one&' => [
            [qw/quiet count files_with_matches files_without_match/],
            [qw/invert_match files_with_matches/],
            [qw/invert_match files_without_match/],
        ],
    },
};
sub grep {
    require ColorThemeUtil::ANSI;
    require Module::Load::Util;

    my %args = @_;

    my $opt_ci     = $args{ignore_case};
    my $opt_invert = $args{invert_match};
    my $opt_count  = $args{count};
    my $opt_files_with_matches  = $args{files_with_matches};
    my $opt_files_without_match = $args{files_without_match};
    my $opt_quiet  = $args{quiet};
    my $opt_linum  = $args{line_number};

    my $ct = $ENV{APPBASE_GREP_COLOR_THEME} // 'Light';

    require Module::Load::Util;
    my $ct_obj = Module::Load::Util::instantiate_class_with_optional_args(
        {ns_prefixes=>['ColorTheme::Search','ColorTheme','']}, $ct);

    my (@str_patterns, @re_patterns);
    for my $p ( grep {defined} $args{pattern}, @{ $args{regexps} // [] }) {
        if ($args{dash_prefix_inverts} && $p =~ s/\A-//) {
            $p = "^(?!.*$p)";
        }
        push @str_patterns, $p;
        push @re_patterns , $opt_ci ? qr/$p/i : qr/$p/;
    }
    return [400, "Please specify at least one pattern"] unless $args{_filter_code} || @re_patterns;

    my $re_highlight = $args{_highlight_regexp} // join('|', @str_patterns);
    $re_highlight = $opt_ci ? qr/$re_highlight/i : qr/$re_highlight/;

    my $color = $args{color} // 'auto';
    my $use_color =
        ($color eq 'always' ? 1 : $color eq 'never' ? 0 : undef) //
        (defined $ENV{NO_COLOR} ? 0 : undef) //
        ($ENV{COLOR} ? 1 : defined($ENV{COLOR}) ? 0 : undef) //
        (-t STDOUT); ## no critic: InputOutput::ProhibitInteractiveTest

    my $source = $args{_source};

    my $logic = 'or';
    $logic = 'and' if $args{all};

    my $num_matches = 0;
    my ($line, $label, $linum, $chomp);

    my $ansi_highlight = ColorThemeUtil::ANSI::item_color_to_ansi($ct_obj->get_item_color('highlight'));
    my $code_print = sub {
        if (defined $label && length $label) {
            if ($use_color) {
                print ColorThemeUtil::ANSI::item_color_to_ansi($ct_obj->get_item_color('location')) . $label . "\e[0m:"; # XXX separator color?
            } else {
                print $label, ":";
            }
        }

        if ($opt_linum) {
            if ($use_color) {
                print ColorThemeUtil::ANSI::item_color_to_ansi($ct_obj->get_item_color('location')) . $linum . "\e[0m:";
            } else {
                print $linum, ":";
            }
        }

        if ($use_color) {
            $line =~ s/($re_highlight)/$ansi_highlight$1\e[0m/g;
            print $line;
        } else {
            print $line;
        }
        print "\n" if $chomp;
    };

    my ($prevlabel, $is_file_match, $instruction, $has_print_files_without_match);
  LINE:
    while (1) {
        ($line, $label, $chomp) = $source->($instruction);
        last unless defined $line;
        undef $instruction;

        chomp($line) if $chomp;

        $label //= '';

        if (!defined $prevlabel) {
            $prevlabel = $label;
            $linum = 1;
        } else {
            if ($label ne $prevlabel) {
                if ($opt_files_without_match && !$is_file_match) {
                    print $label, "\n";
                }
                undef $is_file_match;
                $prevlabel = $label;
                $linum = 1;
            } else {
                $linum++;
            }
        }

        my $is_line_match;
        if ($args{_filter_code}) {
            $is_line_match = $args{_filter_code}->($line, \%args);
        } elsif ($logic eq 'or') {
            $is_line_match = 0;
            for my $re (@re_patterns) {
                if ($line =~ $re) {
                    $is_line_match = 1;
                    last;
                }
            }
        } else {
            $is_line_match = 1;
            for my $re (@re_patterns) {
                unless ($line =~ $re) {
                    $is_line_match = 0;
                    last;
                }
            }
        }

        if ($is_line_match) {
            $is_file_match = 1;
            if ($opt_files_with_matches) {
                print $label, "\n";
                $instruction = 1;
                next LINE;
            }

            next if $opt_invert;
            if ($opt_quiet || $opt_count) {
                $num_matches++;
            } elsif (!$opt_files_without_match) {
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

    if ($opt_files_without_match && !$is_file_match) {
        print $prevlabel, "\n";
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

=head2 NO_COLOR

If set, will disable color. Takes precedence over L</COLOR> but not C<--color>.

=head2 COLOR

Boolean. If set to true, will set default C<--color> to C<always> instead of
C<auto>. If set to false, will set default C<--color> to C<never> instead of
C<auto>. This behavior is not in GNU grep.

=head2 COLOR_THEME

String. Will search color themes in C<AppBase::Grep::ColorTheme::*> as well as
C<Generic::ColorTheme::*> modules.


=head1 SEE ALSO

Some scripts that use us as a base: L<abgrep> (from L<App::abgrep>),
L<grep-email> (from L<App::grep::email>), L<grep-url> (from L<App::grep::url>),
L<pdfgrep> (a.k.a. L<grep-from-pdf>, from L<App::PDFUtils>).

L<Regexp::From::String> is related to C<--dash-prefix-inverts> option.
