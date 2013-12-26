#!/usr/bin/perl

# Copyright (C) 2013, Georgy Bazhukov.
# 
# This program is free software, you can redistribute it and/or modify it under
# the terms of the Artistic License version 2.0.

use utf8;
use strict;
use warnings;
use feature ':5.10';
our $VERSION = 0.1;

BEGIN {
  # Check required modules.
  my $cmd = $^O =~ /win/i ? 'ppm install' : 'cpan';
  eval("use Mojo::UserAgent; 1") && eval("use Log::Log4perl; 1") && eval("use DateTime; 1") or say(<<"ERROR") && exit;
ERROR:
  Can't find required module "Mojolicious" or "Log::Log4perl" or "DateTime"!
  Please install it by command
    $cmd Mojolicious Log::Log4perl DateTime
ERROR
}

use Mojo::UserAgent;
use Log::Log4perl;
use DateTime;

my $ua = Mojo::UserAgent->new;
$ua->transactor->name("wu-sitemap-xml/$VERSION");

say(<<"HELP") && exit unless @ARGV;
The "sitemap-xml" util from package "web-utils".
Use it to find website's pages with bad http status. 

Usage:
  perl ./sitemap-xml.pl [-f] URL FILE [LOG_LEVEL]
  
  -f - force (ignore files and other strange situations).
  URL - simple web URL like "http://example.net/".
  FILE - path to file where it should be.
  LOG_LEVEL - what should finder show. Default "off". Case insencetive.
              Valid levels: DEBUG|TRACE|ALL|FATAL|ERROR|WARN|INFO|OFF.
  
Example:
  perl ./sitemap-xml.pl http://bugov.net ./sitemap.xml INFO
HELP

my $url = shift;
$url .= '/' if $url !~ /\/$/;
my $path = shift;
say(<<"HELP") && exit if -e $path;
File $path already exists!
Use -f key to ignore this message.
HELP

my $log_level = uc(shift || 'OFF');

eval { # try to init logger
  Log::Log4perl::init(\qq(
     log4perl.rootLogger              = $log_level, LOG1
     log4perl.appender.LOG1           = Log::Log4perl::Appender::Screen
     log4perl.appender.SCREEN.stderr  = 0
     log4perl.appender.LOG1.mode      = append
     log4perl.appender.LOG1.layout    = Log::Log4perl::Layout::PatternLayout
     log4perl.appender.LOG1.layout.ConversionPattern = %d %p %m %n
  ))
} or say("Invalid log level '$log_level'! Run ./sitemap-xml.pl for more information.") && exit;

my $log = Log::Log4perl->get_logger();
my ($scheme, $domain) = ($url =~ /^(\w+):\/\/([\w\d\-\.:]+)/);
my $url_chars = '\w\d\.\\\/\+\-_%~#&\?:',
my $schemes = 'http|https|ftp';
my @links = ($url);
my %parsed;

open(my $fh, '>', $path) or $log->fatal("Can't write to file $path") && exit;
say $fh '<urlset>';
while (my $u = pop @links) {
  $log->debug("Looking for page $u");
  my ($code, $title, $content, $a_href_list, $img_src_list,
      $link_href_list, $script_src_list, $undef_list) = get_page($u);
  
  $code == 200 ? $log->info("[$code] $u") : $log->warn("[$code] $u");
  say $fh "<url><loc>$u</loc><lastmod>" . '</lastmod></url>' if $code == 200;
  
  for my $link (@$a_href_list) {
    $log->debug("Has link $link");
    next if $parsed{$link};
    $parsed{$link} = 1;
    push @links, $link;
    $log->debug("Add page to pool $link");
  }
}
say $fh '</urlset>';
close $fh;

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
  my $code = $res->{code};
  
  if (exists $res->{error} && @{$res->{error}}) {
    $log->error("$url:\n\t" . join("\n\t", @{$res->{error}}));
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