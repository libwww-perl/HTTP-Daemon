#!/usr/bin/perl

use strict;
use warnings;

use Config;
use HTTP::Daemon;
use Test::More;
# use Time::HiRes qw(sleep);
our $CRLF;
use Socket qw($CRLF);

my $can_fork = $Config{d_fork} ||
  (($^O eq 'MSWin32' || $^O eq 'NetWare') and
   $Config{useithreads} and $Config{ccflags} =~ /-DPERL_IMPLICIT_SYS/);

my $tport = 8333;

my $tsock = IO::Socket::INET->new(LocalAddr => '0.0.0.0',
                                  LocalPort => $tport,
                                  Listen    => 1,
                                  ReuseAddr => 1);
if (!$can_fork) {
  plan skip_all => "This system cannot fork";
}
elsif (!$tsock) {
  plan skip_all => "Cannot listen on 0.0.0.0:$tport";
}
else {
  close $tsock;
  plan tests => 2;
}

sub mywarn ($) {
  my($mess) = @_;
  open my $fh, ">>", "http-daemon.out"
    or die $!;
  my $ts = localtime;
  print $fh "$ts: $mess\n";
  close $fh or die $!;
}


my $pid;
if ($pid = fork) {
  sleep 1;
  use IO::Socket::INET;
  my $sock = IO::Socket::INET->new(
                                   PeerAddr => "127.0.0.1",
                                   PeerPort => $tport,
                                  ) or die;
  print $sock "GET / HTTP/1.1\r\n";
  sleep 3;
  print $sock "Host: 127.0.0.1\r\n\r\n";
  local $/;
  my $resp = <$sock>;
  close $sock;
  my($got) = $resp =~ /\r?\n\r?\nretries=(\d+)/s;
  ok($got, "Trickled request works");
  is($got, "4", "get_request timed 4 times");
  wait;
} else {
  die "cannot fork: $!" unless defined $pid;
  my $d = HTTP::Daemon->new(
                            LocalAddr => '0.0.0.0',
                            LocalPort => $tport,
                            ReuseAddr => 1,
                           ) or die;
  mywarn "Starting new daemon as '$$'";
  my $i;
  LISTEN: while (my $c = $d->accept) {
    $c->timeout(.6);
    my $retries = 0;
    my $r;
    TRY: {
      $r = $c->get_request;
      if (defined $r and not $r) {
        $retries++;
        mywarn "Retry $retries";
        redo TRY;
      }
    }
    mywarn sprintf "headers[%s] content[%s]", $r->headers->as_string, $r->content;
    my $res = HTTP::Response->new(200,undef,undef,"retries=$retries");
    $c->send_response($res);
    $c->force_last_request; # we're just not mature enough
    $c->close;
    undef($c);
    last;
  }
}



# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
