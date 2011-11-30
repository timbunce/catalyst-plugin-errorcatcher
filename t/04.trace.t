#!perl

use strict;
use warnings;

use FindBin::libs;
use Test::More;

#plan tests => 25;
use Catalyst::Test 'TestApp';

open STDERR, '>/dev/null';

# test that a normal action executes ok
{
    ok( my $res = request('http://localhost/foo/ok'), 'request ok' );
    is( $res->content, 'ok', 'response ok' );
}

# test that a crashed action prints the appropriate debug screen
{
    ok( my $res = request('http://localhost/foo/not_ok'), 'request ok' );
    like( $res->content, qr{Caught exception.+TestApp::Controller::Foo::three}, 'error ok' );
    like( $res->content, qr{Stack Trace}, 'trace ok' );
    like( $res->content, qr{<td>30</td>}, 'line number ok' );
    like( $res->content, qr{<strong class="line">   30:     three\(\);}, 'context ok' );
}

TestApp->config->{stacktrace}{enable} = 0;
{
    ok( my $res = request('http://localhost/foo/not_ok'), 'request ok' );
    like( $res->content, qr{Caught exception.+TestApp::Controller::Foo::three}, 'error ok' );
    unlike( $res->content, qr{Stack Trace}, 'trace disable' );
}

# check output with stacktrace
TestApp->config->{stacktrace}{enable} = 1;
TestApp->config->{"Plugin::ErrorCatcher"}{enable} = 1;
{
    ok( my ($res,$c) = ctx_request('http://localhost/foo/not_ok'), 'request ok' );
    my $ec_msg;
    eval{ $ec_msg = $c->_errorcatcher_msg };
    ok( defined $ec_msg, 'parsed error message ok' );

    # make sure the parsed error looks sane
    like(
        $ec_msg,
        qr{Error: Undefined subroutine &TestApp::Controller::Foo::three called},
        'parsed error content ok'
    );

    # the caller stacktrace frame
    like(
        $ec_msg,
        qr{Package: TestApp::Controller::Foo\n\s+Line:\s+18},
        'caller Package/Line ok'
    );
    like( $ec_msg, qr{-->\s+18:\s+\$c->forward\( 'crash' \);}, 'caller line number ok' );

    # the actual error stacktrace frame
    like(
        $ec_msg,
        qr{Package: TestApp::Controller::Foo\n\s+Line:\s+30},
        'error Package/Line ok'
    );
    like( $ec_msg, qr{-->\s+30:\s+three\(\);}, 'error line number ok' );

    # RT-72781 - we shouldn't have any referer information in this stacktrace
    unlike(
        $ec_msg,
        qr{Referer: },
        'no referer information in stacktrace'
    );
}

# check output with no stacktrace
TestApp->config->{stacktrace}{enable} = 0;
TestApp->config->{"Plugin::ErrorCatcher"}{enable} = 1;
{
    ok( my ($res,$c) = ctx_request('http://localhost/foo/not_ok'), 'request ok' );
    my $ec_msg;
    eval{ $ec_msg = $c->_errorcatcher_msg };
    ok( defined $ec_msg, 'parsed error message ok' );

    # make sure the parsed error looks sane
    like(
        $ec_msg,
        qr{Error: Undefined subroutine &TestApp::Controller::Foo::three called},
        'parsed error content ok'
    );

    # the caller stacktrace frame
    unlike(
        $ec_msg,
        qr{Package: TestApp::Controller::Foo\n\s+Line:\s+18},
        'caller Package/Line ok'
    );
    unlike( $ec_msg, qr{-->\s+18:\s+\$c->forward\( 'crash' \);}, 'caller line number ok' );

    # the actual error stacktrace frame
    unlike(
        $ec_msg,
        qr{Package: TestApp::Controller::Foo\n\s+Line:\s+30},
        'error Package/Line ok'
    );
    unlike( $ec_msg, qr{-->\s+30:\s+three\(\);}, 'error line number ok' );

    # we should have a note about lack of stacktrace
    like(
        $ec_msg,
        qr{Stack trace unavailable - use and enable Catalyst::Plugin::StackTrace},
        'stacktrace hint ok'
    );
}


# check output with stacktrace
TestApp->config->{stacktrace}{enable} = 1;
TestApp->config->{"Plugin::ErrorCatcher"}{enable} = 1;
{
    ok( my ($res,$c) = ctx_request('http://localhost/foo/crash_user'), 'request ok' );
    my $ec_msg;
    eval{ $ec_msg = $c->_errorcatcher_msg };
    ok( defined $ec_msg, 'parsed error message ok' );

    # we should have some user information
    like(
        $ec_msg,
        qr{User: buffy \[id\] \(Catalyst::Authentication::User::Hash\)},
        'user details ok'
    );

    like(
        $ec_msg,
        qr{Error: Vampire\n},
        'Buffy staked the vampire'
    );
}

# RT-64492 - check no session data in default report
TestApp->config->{stacktrace}{enable} = 1;
TestApp->config->{"Plugin::ErrorCatcher"}{enable} = 1;
{
    ok( my ($res,$c) = ctx_request('http://localhost/foo/not_ok'), 'request ok' );
    my $ec_msg;
    eval{ $ec_msg = $c->_errorcatcher_msg };
    ok( defined $ec_msg, 'parsed error message ok' );
    foreach my $session_key (qw/__created __updated/) {
        unlike(
            $ec_msg,
            qr{__created},
            "no instances of '$session_key' in report"
        );
    }
}

# helper methods for RT-72781 testing
sub _has_referer_ok {
    # we should have some referer information
    like(
        shift,
        qr{Referer:\s+http://garlic-weapons.tv},
        'referer information exists'
    );
}
sub _has_GET_output {
    _has_param_section('GET',@_);
}
sub _has_POST_output {
    _has_param_section('POST',@_);
}
sub _has_param_section {
    my $type = shift;
    like(
        shift,
        qr{Params \(${type}\):},
        'GET params block exists'
    );
}
sub _has_keys_for_section {
    my ($type, $keys, $msg) = @_;
    return
        unless (ref $keys eq 'ARRAY');
    foreach my $key (@{$keys}) {
        like(
            $msg,
            qr{
                Params\s+\(\Q$type\E\): # section header
                .+?                     # non-greedy anything-ness
                ^\s+\Q$key\E:.+?$       # the line with our key on it
                .+?                     # non-greedy anything-ness
                ^$                      # blank line at end of section
            }xms,
            "'$key' exists in $type section"
        );
    }
}

# RT-72781 - show the parameters that were sent with the request and where the request came from
TestApp->config->{stacktrace}{enable} = 1;
TestApp->config->{"Plugin::ErrorCatcher"}{enable} = 1;
# test referer information is output
{
    ok( my ($res,$c) = ctx_request('http://localhost/foo/referer'), 'request ok' );
    my $ec_msg;
    eval{ $ec_msg = $c->_errorcatcher_msg };
    ok( defined $ec_msg, 'parsed error message ok' );

    # we should have some referer information
    _has_referer_ok($ec_msg);
}
# test output with GET params
{
    # make a request with params
    ok( my ($res,$c) =
        ctx_request('http://localhost/foo/referer?one=man&went=to&mow=1&long_thingy=2'), 'request ok' );
    my $ec_msg;
    eval{ $ec_msg = $c->_errorcatcher_msg };
    ok( defined $ec_msg, 'parsed error message ok' );

    # we should have some referer information
    _has_referer_ok($ec_msg);
    # we should have the get header and lines with the key-value pairs
    _has_GET_output($ec_msg);
    # we should have keys and values for each query param
    _has_keys_for_section('GET', [qw(one went long_thingy)], $ec_msg);
}
# test output with POST params
{
    # we still need to get to $c
    ok ( my (undef,$c) = ctx_request('http://localhost/ok'), 'setup $c for POST');
    # make a request with POST data
    use HTTP::Request::Common;
    my $response = request POST '/foo/referer', [
        bar         => 'baz',
        something   => 'else'
    ];

    my $ec_msg;
    eval{ $ec_msg = $c->_errorcatcher_msg };
    ok( defined $ec_msg, 'parsed error message ok' );

    # we should have some referer information
    _has_referer_ok($ec_msg);
    # we should have the get header and lines with the key-value pairs
    _has_POST_output($ec_msg);
    # we should have keys and values for each query param
    _has_keys_for_section('POST', [qw(bar something)], $ec_msg);
}
# test output with both GET and POST params
{
    # we still need to get to $c; this appears to be the only way
    ok ( my (undef,$c) = ctx_request('http://localhost/ok'), 'setup $c for POST');
    # make a request with POST data
    use HTTP::Request::Common;
    my $response = request POST '/foo/referer?fruit=banana&animal=kangaroo', [
        vampire     => 'joe random',
        slayer      => 'kendra'
    ];

    my $ec_msg;
    eval{ $ec_msg = $c->_errorcatcher_msg };
    ok( defined $ec_msg, 'parsed error message ok' );

    # we should have some referer information
    _has_referer_ok($ec_msg);

    # GET
    # we should have the get header and lines with the key-value pairs
    _has_GET_output($ec_msg);
    # we should have keys and values for each query param
    _has_keys_for_section('GET', [qw(fruit animal)], $ec_msg);

    # POST
    # we should have the get header and lines with the key-value pairs
    _has_POST_output($ec_msg);
    # we should have keys and values for each query param
    _has_keys_for_section('POST', [qw(vampire slayer)], $ec_msg);
}

done_testing;
