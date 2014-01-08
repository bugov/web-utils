#!/usr/bin/perl -w

use utf8;
use strict;
use warnings;
use feature ':5.10';

BEGIN {
  # Check required modules.
  my $cmd = $^O =~ /win/i ? 'ppm install' : 'cpan';
  eval("use Mojo::UserAgent; 1") or say(<<"ERROR") && exit;
ERROR:
  Can't find required module "Mojolicious"!
  Please install it by command
    $cmd Mojolicious
ERROR
}

use Mojo::Log;
use Mojo::UserAgent;
our $VERSION = 0.5;
say(<DATA>) && exit unless @ARGV;

my $ua = Mojo::UserAgent->new;
   $ua->transactor->name("wu-find404/$VERSION");

my $url = shift;
   $url .= '/' if $url !~ /\/$/;
my $log = Mojo::Log->new;
   $log->level(lc(shift || 'WARN'));

my ($scheme, $domain) = ($url =~ /^(\w+):\/\/([\w\d\-\.:]+)/);
my $url_chars = '\w\d\.\\\/\+\-_%~#&\?:',
my $schemes = 'http|https|ftp';
my @pool = ($url);
my %visited;

while (my $u = pop @pool) {
  $log->debug("Looking for page $u");
  my ($code, $title, $content, $a_href_list, $img_src_list,
      $link_href_list, $script_src_list, $undef_list) = get_page($u);
  
  $code == 200 ? $log->info("[$code] $u") : $log->warn("[$code] $u");
  
  for my $link (@$a_href_list, @$img_src_list, @$link_href_list, @$script_src_list, @$undef_list) {
    $log->debug("Has link $link");
    next if $visited{$link};
    $visited{$link} = 1;
    push @pool, $link;
    $log->debug("Add page to pool $link");
  }
}

say "[!] Done!";
exit;

# Function: get_page
#   get parsed page content.
# Parameters:
#   $url - Str - Page url
# Returns:
#   $code - Int - HTTP code
#   $title - Str - Page title
#   $content - Str - Page content
#   \@a_href_list - ArrayRef - urls from a[href]
#   \@img_src_list - ArrayRef - urls from img[src]
#   \@link_href_list - ArrayRef - urls from link[href]
#   \@script_src_list - ArrayRef - urls from script[src]
#   \@undef_list - ArrayRef - url from other
sub get_page {
  my $url = shift;
  my $res = $ua->get($url)->res;
  my $code = $res->{code} || 418;
  
  if (exists $res->{error} && @{$res->{error}}) {
    $log->info("$url:\n\t" . join("\n\t", @{$res->{error}}));
    return $code, '', '', [], [], [] ,[], [];
  }
  
  # Skip by content-type
  if ($res->content->{headers}->{headers}->{'content-type'}[0][0] !~ /(?:text|html)/) {
    $log->info("$url looks like non-text/html document");
    return $code, '', '', [], [], [], [], [];
  }
  
  # text/html/etc
  my $content = $res->content->{asset}->{content} || '';
  return parse($res, $code, $content);
}

# Function: parse
#   parse the content.
# Parameters:
#   $res - Mojo::Agent res
#   $code - Int - HTTP code
#   $content - Str - response
# Returns:
#   $code - Int - HTTP code
#   $content - Str - Page content
#   \@a_href_list - ArrayRef - urls from a[href]
#   \@img_src_list - ArrayRef - urls from img[src]
#   \@link_href_list - ArrayRef - urls from link[href]
#   \@script_src_list - ArrayRef - urls from script[src]
#   \@undef_list - ArrayRef - url from other
sub parse {
  my ($res, $code, $content) = @_;
  my $title = $res->dom('head > title')->pluck('text')->[0] || '';
  
  my (%a_href_list, %img_src_list, %link_href_list,
      %script_src_list, %undef_list);
  
  # a href
  $res->dom->find('a')->map(sub {
    my $href = $_[0]->{href} || return;
    $href = get_link($href) || return;
    $a_href_list{$href}++;
  });
  
  # img src
  $res->dom->find('img')->map(sub {
    my $src = $_[0]->{src} || return;
    $src = get_link($src) || return;
    $img_src_list{$src}++;
  });
  
  # link href
  $res->dom->find('link')->map(sub {
    my $src = $_[0]->{href} || return;
    $src = get_link($src) || return;
    $link_href_list{$src}++;
  });
  
  # script src
  $res->dom->find('script')->map(sub {
    my $src = $_[0]->{href} || return;
    $src = get_link($src) || return;
    $script_src_list{$src}++;
  });
  
  my $abs_url_re = qr/(?:$schemes):\/\/[$url_chars]*/;
  my $rel_url_re = qr/[$url_chars]+/;
  
  # undef
  
  # Only for css.
  # TODO: define type of document.
  if (my @url = ($content =~ /url\s*\(\s*["']?\s*($rel_url_re|$abs_url_re)\s*["']?\s*\)/gi)) {
    for my $url (@url) {
      next if exists $a_href_list{$url} || exists $img_src_list{$url} ||
        exists $link_href_list{$url} || exists $script_src_list{$url};
      $url = get_link($url) || next;
      $undef_list{$url}++;
    }
  }
  
  if (my @url = ($content =~ /($abs_url_re)/gi)) {
    for my $url (@url) {
      next if exists $a_href_list{$url} || exists $img_src_list{$url} ||
        exists $link_href_list{$url} || exists $script_src_list{$url};
      $url = get_link($url) || next;
      $undef_list{$url}++;
    }
  }
  
  return $code, $title, $content, [keys %a_href_list], [keys %img_src_list],
    [keys %link_href_list], [keys %script_src_list], [keys %undef_list];
}

# Function: get_link
#   create absolute link from link for this domain
# Parameters:
#   $href - Str - uri|url
# Returns:
#   $href - Str|undef - url
sub get_link {
  my ($href) = @_;
  $href = [split /#/, $href]->[0];
  return unless defined $href;
  my $abs_url_re = qr/(?:$schemes):\/\/[$url_chars]*/;
  
  if ($href =~ /^$abs_url_re/) {}
  elsif ($href =~ /^mailto:/) { return }     # skip
  elsif ($href =~ /^javascript:/) { return } # skip
  # /hello.jpg
  elsif ($href =~ /^\//) {
    $href = $scheme."://".$domain.$href;
  }
  # ./hello.jpg
  elsif ($href =~ /^\.\//) {
    $href = substr $href, 2;
    my @parts = split /\//, $url, -1;
    pop @parts;
    push @parts, $href;
    $href = join '/', @parts;
  }
  # ../hello.jpg
  elsif ($href =~ /^\.\.\//) {
    $href = substr $href, 3;
    my @parts = split /\//, $url, -1;
    pop @parts;
    pop @parts;
    push @parts, $href;
    $href = join '/', @parts;
  }
  # hello.jpg
  else {
    my @parts = split /\//, $url, -1;
    pop @parts;
    push @parts, $href;
    $href = join '/', @parts;
    $href = $scheme."://".$domain.$href if $href !~ /^$abs_url_re/;
  }
  
  return if $href !~ /$domain/;
  return $href;
}

__DATA__

The "find404" util from package "web-utils".
Use it to find website's pages with bad http status. 

Usage:
  perl ./find404.pl URL [LOG_LEVEL]
  
  URL - simple web URL like "http://example.net/".
  LOG_LEVEL - what should finder show. Default "warn". Case insencetive.
              Valid levels: FATAL|ERROR|WARN|INFO|DEBUG.
  
Example:
  perl ./find404.pl http://bugov.net INFO

__END__

=head1 NAME

find404 - a website's page checker.

=head1 OVERVIEW

Use it to find website's pages with bad http status.

  Usage:
    perl ./find404.pl URL [LOG_LEVEL]
    
    URL - simple web URL like "http://example.net/".
    LOG_LEVEL - what should finder show. Default "warn". Case insencetive.
                Valid levels: FATAL|ERROR|WARN|INFO|DEBUG.
    
  Example:
    perl ./find404.pl http://bugov.net INFO

=head1 SEE

=over

=item Status Code Definitions

L<http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html>

=item GitHub project

L<https://github.com/bugov/web-utils>

=back


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 - 2014, Georgy Bazhukov <bugov@cpan.org>.
 
This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=cut
