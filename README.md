# web-utils

Some utils for web developers.

## find404.pl

The find404 util from package "web-utils".
Use it to find website's pages with bad http status. 

### Usage

```
perl ./find404.pl URL [LOG_LEVEL]
```
  
URL - simple web URL like "http://example.net/".
LOG_LEVEL - what should finder show. Default "warn". Case insencetive.

### Example

```
perl ./find404.pl http://bugov.net INFO
```

# Copyright and License

Copyright (C) 2013, Georgy Bazhukov.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.
