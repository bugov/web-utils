#!/usr/bin/perl

# Copyright (C) 2013, Georgy Bazhukov.
# 
# This program is free software, you can redistribute it and/or modify it under
# the terms of the Artistic License version 2.0.

use utf8;
use strict;
use warnings;
use feature ':5.10';
our $VERSION = 0.2;

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

use Mojo::UserAgent;
my $ua = Mojo::UserAgent->new(name => "wu-find404/$VERSION");

say(<<"HELP") && exit unless @ARGV;
The find404 util from package "web-utils".
Use it to find website's pages with bad http status. 

Usage:
  perl ./find404.pl URL [LOG_LEVEL]
  
  URL - simple web URL like "http://example.net/".
  LOG_LEVEL - what should finder show. Default "warn". Case insencetive.
  
Example:
  perl ./find404.pl http://bugov.net INFO
HELP

my $url = shift;
my $log_level = lc (shift || 'WARN');
my $log_level_list = {
  debug => 00,
  info  => 20,
  warn  => 40,
  error => 60,
  fatal => 80,
  off   => 99,
};

say(<<"ERROR") && exit unless exists $log_level_list->{$log_level};
ERROR:
  Can't find log level "$log_level"!
ERROR

my ($scheme, $domain) = ($url =~ /^(\w+):\/\/([\w\d\-\.:]+)/);
my $url_chars = '\w\d\.\\\/\+\-_%~#&\?:',
my $schemes = 'http|https|ftp';
my @links = ($url);
my %parsed;


say qq{[!] Start parsing with log level "$log_level".};

while (my $u = pop @links) {
  my ($code, $title, $content, $a_href_list, $img_src_list,
      $link_href_list, $script_src_list, $undef_list) = get_page($u);
  
  if ($code == 200) {
    log_info('[%d] %s', $code, $u);
  } else {
    log_warn('[%d] %s', $code, $u);
  }
  
  for my $link (@$a_href_list, @$img_src_list, @$link_href_list, @$script_src_list, @$undef_list) {
    next if $parsed{$link};
    $parsed{$link} = 1;
    push @links, $link;
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
  my $code = $res->{code};
  
  if (exists $res->{error} && @{$res->{error}}) {
    log_error("%s:\n\t%s", $url, join "\n\t", @{$res->{error}});
    return $code, '', '', [], [], [] ,[], [];
  }
  
  # Skip by content-type
  if ($res->content->{headers}->{headers}->{'content-type'}[0][0] !~ /(?:text|html)/) {
    log_info('%s looks like non-text/html document', $url);
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
  }
  
  return if $href !~ /$domain/;
  return $href;
}

### Log

# Function: write_log
#   Write messages into log
# Parameters:
#   $level - log level name
#   @content - Array - log info (sprintf)
sub write_log {
  my ($level, @content) = @_;
  my $format = shift @content;
  
  printf "[%5s] %s\n", $log_level,
    ( @content ? sprintf $format, @content : sprintf $format );
}

# Function: log_debug
#   Log debug message
# Parameters:
#   @content - Array - message for write_log
sub log_debug {
  my @content = @_;
  return if $log_level_list->{debug} < $log_level_list->{$log_level};
  write_log('debug', @content);
}

# Function: log_info
#   Log info message
# Parameters:
#   @content - Array - message for write_log
sub log_info {
  my @content = @_;
  return if $log_level_list->{info} < $log_level_list->{$log_level};
  write_log('info', @content);
}

# Function: log_warn
#   Log warning message
# Parameters:
#   @content - Array - message for write_log
sub log_warn {
  my @content = @_;
  return if $log_level_list->{warn} < $log_level_list->{$log_level};
  write_log('warn', @content);
}

# Function: log_error
#   Log error message
# Parameters:
#   @content - Array - message for write_log
sub log_error {
  my @content = @_;
  return if $log_level_list->{error} < $log_level_list->{$log_level};
  write_log('error', @content);
}

# Function: log_fatal
#   Log fatal message
# Parameters:
#   @content - Array - message for write_log
sub log_fatal {
  my @content = @_;
  return if $log_level_list->{fatal} < $log_level_list->{$log_level};
  write_log('fatal', @content);
}

