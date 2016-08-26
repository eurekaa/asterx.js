# asterx.js

Continuum.js is a multi-compiler for web projects with AST transformations, including 
[Continuation-Passing Style](http://en.wikipedia.org/wiki/Continuation-passing_style) transformation
useful for writing asynchronous javascript code in a standard, synchronous style.

For example, writing 3 asynchronous operations without CPS will result in such code

```javascript
# (coffeescripted)
fs.readFile 'path/to/file_1.ext', (err, content_1)->
    if err then console.error err
    console.log content_1
    fs.readFile 'path/to/file_2.ext', (err, content_2)->
        if err then console.error err
        console.log content_2
        fs.readFile 'path/to/file_3.ext', (err, content_3)->
            if err then console.error err
            console.log content_3
            ...
```

As you can see the code slides diagonally, making it unreadable as far as the program grows.
With continuum.js CPS transformation you can use the `!!` marker in place of a callback and just call functions as 
if they are synchronous.

```javascript
# (coffeescripted)
try
    content_1 = fs.readFile 'path/to/file_1.ext', !!
    console.log content_1
    content_2 = fs.readFile 'path/to/file_2.ext', !!
    console.log content_2
    content_3 = fs.readFile 'path/to/file_3.ext', !!
    console.log content_3
    ...
catch err then console.error err
```

CPS transformation takes care to refactor your code nesting callbacks and automatically including error handling too.

Continuum.js is a growing project, actually it does:

- compilation: 
    from coffeescript and livescript to javascript.
    from sass, stylus and less to css3.
    from jade to html5.

- cps transformation from javascript to javascript.

- code analysis for javascript, css and html.

- code compression for javascript, css and images too.

- source map generation for javascript and css.

- caching files to avoid processing unchanged files.

- copying non processable files to output directory.

- More is coming, including pluggable AST to AST transformations with source map support for javascript and css, etc..
