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
our $VERSION = 0.1;

BEGIN {
  # Check required modules.
  my $cmd = $^O =~ /win/i ? 'ppm install' : 'cpan';
  eval("use Mojo::UserAgent; 1") && eval("use Mojo::JSON; 1")
    or say(<<"ERROR") && exit;
ERROR:
  Can't find required module "Mojolicious"!
  Please install it by command
    $cmd Mojolicious Test::More
ERROR
}

use Test::More;
use Mojo::UserAgent;
use Mojo::JSON 'j';

my $ua = Mojo::UserAgent->new(name => "wu-bot/$VERSION");

say(<<"HELP") && exit if @ARGV != 1;
The bot util from package "web-utils".
Use it to check website's behavior. 

Usage:
  perl ./bot.pl BOT_SCRIPT
  
  BOT_SCRIPT - list of checks (file).
  
Example:
  perl ./bot.pl ./path/to/testme_config.json

See:
  example/bot.json - config example.
HELP

my $file_path = shift;
open(my $fh, $file_path) or die "Can't find file $file_path\n";
local $/;
my $config = j <$fh>;
close $fh;

for my $rule (@$config) {
  my $body = do_request(normalize_rule($rule));
  write_log($_) for check($rule, $body);
}

say "[!] Done!";
exit;

# Function: fill_rule
#   Add default fields, make role's structure normal.
#   Full rule structure:
#   {
#     "url": "http://bugov.net/login",
#     "method": "POST",
#     "data": {
#       "email": "admin@bugov.net",
#       "password": "secret"
#     },
#     "like": ["Welcome", "Admin"],
#     "unlike": ["Access", "denied"]
#   }
# Parameters:
#   $rule - HashRef
# Returns:
#   $rule - HashRef
sub normalize_rule {
  my $rule = shift;
  
  $rule->{unlike} = []    unless $rule->{unlike};
  $rule->{like}   = []    unless $rule->{like};
  $rule->{data}   = {}    unless $rule->{data};
  $rule->{method} = 'GET' unless $rule->{method};
  
  $rule->{unlike} = [$rule->{unlike}] unless ref $rule->{unlike};
  $rule->{like}   = [$rule->{like}]   unless ref $rule->{like};
  
  return $rule;
}

# Function: do_request
#   Make request
# Parameters:
#   $rule - HashRef
# Returns:
#   $body - Str
sub do_request {
  my $rule = shift;
  my $body = '';
  
  if ('get' eq lc $rule->{method}) {
    $body = $ua->get($rule->{url})->res->body;
  }
  elsif ('post' eq lc $rule->{method}) {
    my $tx = $ua->post($rule->{url}, form => $rule->{data});
    
    if (my $res = $tx->success) {
      $body = $res->body
    } else {
      my ($err, $code) = $tx->error;
      # TODO: make error handling better.
      say $code ? '[!] '.$rule->{method}.' '.$rule->{url}." $code response: $err" :
        '[!] '.$rule->{method}.' '.$rule->{url}. " connection error: $err";
    }
  }
  
  return $body;
}

# Function: check
#   Check content of this page.
# Parameters:
#   $rule - HashRef
#   $text - Str
# Returns:
#   Array of (Bool, Str)
sub check {
  my ($rule, $text) = @_;
  my @ret;
  
  push @ret, {is => 0+($text =~ /$_/), message => ($rule->{method}.' '.$rule->{url}." LIKE '$_'")} for @{$rule->{like}};
  push @ret, {is => 0+($text !~ /$_/), message => ($rule->{method}.' '.$rule->{url}." UNLIKE '$_'")} for @{$rule->{unlike}};
  
  return @ret;
}

# Function: write_log
#   Print result.
# Parameters:
#   @log_list - Array
sub write_log {
  say ($_->{is} ? '[+] '.$_->{message} : '[-] '.$_->{message}) for @_;
}

