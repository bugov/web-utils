#!/usr/bin/perl -w

use utf8;
use strict;
use warnings;
use feature ':5.10';
use Carp 'croak';

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
our $VERSION = '0.02';
say(<DATA>), exit unless @ARGV;

# Get input data
my @pool= (my $url = shift);
my $fn  = shift || 'sitemap.xml';

# Init UA
my $ua = Mojo::UserAgent->new;
   $ua->transactor->name("wu-sitemap-xml/$VERSION");

my %visited;
# Parse url
my ($scheme, $domain) = ($url =~ /^(\w+):\/\/([\w\d\-\.:]+)/);
my $url_chars = '\w\d\.\\\/\+\-_%~#&\?:',
my $schemes = 'http|https|ftp';
my $abs_url_re = qr/(?:$schemes):\/\/[$url_chars]*/;
my %mon_str_to_num = qw(Jan 01 Feb 02 Mar 03 Apr 04 May 05 Jun 06 Jul 07 Aug 08 Sep 09 Oct 10 Nov 11 Dec 12);

# MainLoop
my $fh = *STDOUT;
open($fh, ">$fn") or croak("Can't write to file $fn") if lc($fn) ne 'stdout';
say $fh '<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">';
while (my $url = shift @pool) {
  say STDERR "Looking for $url";
  my $res = $ua->get("$url")->res;
  
  # Skip by content-type, http code
  next if $res->content->{headers}->{headers}->{'content-type'}[0][0] !~ /(?:text|html)/;
  next if $res->{code} != 200;
  
  # Get refs
  $res->dom->find('a')->map(sub {
    my $href = $_[0]->{href} || return;
    $href = get_url($url, $href) || return;
    push @pool, $href unless $visited{$href};
    $visited{$href}++;
  });
  
  # Last modify
  my ($s, $i, $h, $d, $m, $y) = map { $_ < 10 ? "0$_" : $_ } localtime;
  $y += 1900; $m++;
  my $last_modify = $res->content->{headers}->{headers}->{'last-modified'}[0][0] || "$y-$m-$d";
  $last_modify = join '-', $3, $mon_str_to_num{$2}, $1 if $last_modify =~ /\w+,\s+(\d\d)\s+(\w+)\s+(\d{4})/;
  
  say $fh "<url><loc>$url</loc><lastmod>$last_modify</lastmod></url>";
}
say $fh '</urlset>';
close $fh;

# Function: get_link
#   create absolute link from link for this domain
# Parameters:
#   $url - Str - current url
#   $href - Str - uri|url
# Returns:
#   $href - Str|undef - url
sub get_url {
  my ($url, $href) = @_;
  $href = [split /#/, $href]->[0];
  return unless defined $href;
  
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

The "sitemap-xml" util from package "web-utils".
Use it to generate xml sitemap for your website. 

Usage:
  perl ./sitemap-xml.pl URL [FILE]
  
  URL  - simple web URL like "http://example.net/".
  FILE - path to file where it should be.
         Default 'sitemap.xml'. Set "STDOUT" to get result on STDOUT (console).
  
Example:
  perl ./sitemap-xml.pl http://bugov.net ./sitemap.xml
or
  perl ./sitemap-xml.pl http://bugov.net stdout > ./sitemap.xml

__END__

=head1 NAME

sitemap-xml - a sitemap generator.

=head1 OVERVIEW

C<sitemap-xml> helps you generate xml sitemap for your website. It defines C<last-modified> date
base on server response (or local time if can't use server header).

  Usage:
    perl ./sitemap-xml.pl URL [FILE]
    
    URL  - simple web URL like "http://example.net/".
    FILE - path to file where it should be.
           Default 'sitemap.xml'. Set "STDOUT" to get result on STDOUT (console).
    
  Example:
    perl ./sitemap-xml.pl http://bugov.net ./sitemap.xml
  or
    perl ./sitemap-xml.pl http://bugov.net stdout > ./sitemap.xml

=head1 SEE

=over

=item Sitemap format defenition

L<http://www.sitemaps.org/ru/protocol.html>

=item GitHub project

L<https://github.com/bugov/web-utils>

=back


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 - 2014, Georgy Bazhukov <bugov@cpan.org>.
 
This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=cut
