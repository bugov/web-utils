#!/usr/bin/perl

# Copyright (C) 2013, Georgy Bazhukov.
# 
# This program is free software, you can redistribute it and/or modify it under
# the terms of the Artistic License version 2.0.

use utf8;
use strict;
use warnings;
use feature ':5.10';
use Data::Dumper;
use Encode;
our $VERSION = 0.1;

BEGIN {
  # Check required modules.
  my $cmd = $^O =~ /win/i ? 'ppm install' : 'cpan';
  eval("use Mojo::UserAgent; 1") && eval("use Text::Aspell; 1")
    && eval("use Log::Log4perl; 1") or say(<<"ERROR") && exit;
ERROR:
  Can't find required module "Mojolicious" or "Text::Aspell" or "Log::Log4perl"!
  Please install it by command
    $cmd Mojolicious Text::Aspell Log::Log4perl
  
  See also http://aspell.net/win32/ - for Windows or
    your package manager (search by word "aspell") - for other systems.
ERROR
}

use Log::Log4perl;
use Mojo::UserAgent;
use Text::Aspell;

my $ua = Mojo::UserAgent->new;
$ua->transactor->name("wu-spellcheck/$VERSION");
my $speller = Text::Aspell->new;
my $default_lang = [split /\./, $ENV{LANG}]->[0];

say(<<"HELP") && exit unless @ARGV;
The "spellcheck" util from package "web-utils".
Use it to find grammatical mistakes. 

Usage:
  perl ./spellcheck.pl URL [LOCALE] [LOG_LEVEL]
  
  URL - some web URL like "http://example.net/".
  LOCALE - required locale (for example "en_US"). Use system LOCALE by default ($default_lang).
  LOG_LEVEL - what should finder show. Default "warn". Case insencetive.
              Valid levels: DEBUG|TRACE|ALL|FATAL|ERROR|WARN|INFO|OFF.
  
Example:
  perl ./spellcheck.pl http://bugov.net
HELP

my $url = shift;
$url .= '/' if $url !~ /\/$/;
my $lang = shift || $default_lang;
my $log_level = uc(shift || 'WARN');
my ($scheme, $domain) = ($url =~ /^(\w+):\/\/([\w\d\-\.:]+)/);
my $url_chars = '\w\d\.\\\/\+\-_%~#&\?:',
my $schemes = 'http|https|ftp';
my @links = ($url);
my %parsed;
my $lang_regexp = {
  en_US => 'a-zA-Z\-',
  ru_RU => 'а-яёЁА-Я\-',
};

eval { # try to init logger
  Log::Log4perl::init(\qq(
     log4perl.rootLogger              = $log_level, LOG1
     log4perl.appender.LOG1           = Log::Log4perl::Appender::Screen
     log4perl.appender.SCREEN.stderr  = 0
     log4perl.appender.LOG1.mode      = append
     log4perl.appender.LOG1.layout    = Log::Log4perl::Layout::PatternLayout
     log4perl.appender.LOG1.layout.ConversionPattern = %d %p %m %n
  ))
} or say("Invalid log level '$log_level'! Run ./find404.pl for more information.") && exit;
my $log = Log::Log4perl->get_logger();
$speller->set_option('lang', $lang);

while (my $u = pop @links) {
  $log->debug("Looking for page $u");
  my ($code, $title, $content, $a_href_list, $img_src_list,
      $link_href_list, $script_src_list, $undef_list) = get_page($u);
  
  $code == 200 ? $log->debug("[$code] $u") : $log->warn("[$code] $u");
  check_spell($u, $title, decode('utf8', $content));
  
  for my $link (@$a_href_list) {
    next if $parsed{$link};
    $parsed{$link} = 1;
    push @links, $link;
    $log->debug("Add page to pool $link");
  }
}

say "[!] Done!";
exit;

# Function: check_spell
#   Check text for grammatical mistakes.
# Parameters:
#   $url - page url
#   $title - page title
#   $content - page content
sub check_spell {
  my ($url, $title, $content) = @_;
  $speller->set_option('lang', $lang);
  my $re = $lang_regexp->{$lang};
  for my $token (split(/\s+/, $title), split(/\s+/, $content)) {
    next unless $token;
    $token =~ s/^(?:[^$re]|-)+//;
    $token =~ s/(?:[^$re]|-)+$//;
    next if $token !~ /^[$re]+$/;
    $speller->check($token) ? $log->info("[+] $token @ $url") : $log->warn("[-] $token @ $url");
  }
}

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
