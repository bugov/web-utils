# web-utils

Some utils for web developers.

## find404.pl

The find404 util from package "web-utils".
Use it to find website's pages with bad http status. 

### Usage

```
perl ./find404.pl URL [LOG_LEVEL]
```
  
* URL - simple web URL like "http://example.net/".
* LOG_LEVEL - what should finder show. Default "warn". Case insencetive.

### Example

```
perl ./find404.pl http://bugov.net INFO
```

## sitemap-xml.pl

The sitemap-xml util from package "web-utils".
sitemap-xml - a sitemap generator.

### Overview

`sitemap-xml` helps you generate xml sitemap for your website. It defines C<last-modified> date
base on server response (or local time if can't use server header).

```
  Usage:
    perl ./sitemap-xml.pl URL [FILE]
    
    URL - simple web URL like "http://example.net/".
    FILE - path to file where it should be. Default 'sitemap.xml'.
    
  Example:
    perl ./sitemap-xml.pl http://bugov.net ./sitemap.xml
```

### SEE

* [Sitemap format defenition](http://www.sitemaps.org/ru/protocol.html)
* [GitHub project](https://github.com/bugov/web-utils)

## spellcheck.pl

The "spellcheck" util from package "web-utils".
Use it to find grammatical mistakes. 

### Usage

```
perl ./spellcheck.pl URL [LOCALE] [LOG_LEVEL]
```
  
* URL - some web URL like "http://example.net/".
* LOCALE - required locale (for example "en_US"). Use system LOCALE by default ($default_lang).
* LOG_LEVEL - what should finder show. Default "warn". Case insencetive. Valid levels: DEBUG|TRACE|ALL|FATAL|ERROR|WARN|INFO|OFF.
  
### Example

```
perl ./spellcheck.pl http://bugov.net
```

## bot.pl

The "bot" util from package "web-utils".
Use it to check website's behavior. 

### Usage

```
perl ./bot.pl BOT_SCRIPT
```

* BOT_SCRIPT - list of checks (file).
  
### Example

```
perl ./bot.pl ./path/to/testme_config.json
```

### See

example/bot.json - config example.

# Copyright and License

Copyright (C) 2013, Georgy Bazhukov.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.
