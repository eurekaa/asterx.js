# Asterx

Asterx is a [Continuation-Passing Style](http://en.wikipedia.org/wiki/Continuation-passing_style) transformation batch useful for writing asynchronous javascript code in a standard, synchronous style. It takes care to compile [coffee-script](http://coffeescript.org/) files, generate source-maps and compress your code too.

For example, writing 3 asynchronous operations without Asterx results in such code:
```javascript
fs.readFile('path/to/file1.txt', function(err, content1){
    console.log(content1);
        
    fs.readFile('path/to/file2.txt', function(err, content2){    
        console.log(content2);
        
        fs.readFile('path/to/file3.txt', function(err, content3){
            console.log(content3);
        });
    });
});
```
As you can see the code slides diagonally, making it unreadable as far as the program grows.

## Installation
``` npm install -g asterx ```

## Usage: Function Calls
With Asterx you can use the `!!` or `!!!` marker in place of a callback and just call functions as if they are synchronous.
CPS transformation takes care to refactor your code nesting callbacks correctly!

```javascript

/*** your code: ***/
content1 = fs.readFile('path/to/file1.txt', !!);
console.log(content1);

content2 = fs.readFile('path/to/file2.txt', !!);
console.log(content2);

content3 = fs.readFile('path/to/file3.txt', !!);
console.log(content3);

/*** asterx transformed code: ***/
var $BACK_ERR = function (err) {
    var target = typeof window !== 'undefined' ? window : global;
    if (target.onError) return target.onError(err);
    else throw err;
};
return fs.readFile('path/to/file1.txt', function(err, content1){
    if (err) return $BACK_ERR(err);
    console.log(content1);    

    return fs.readFile('path/to/file2.txt', function(err, content2){
        if (err) return $BACK_ERR(err);
        console.log(content2);        

        return fs.readFile('path/to/file3.txt', function(err, content3){
            if (err) return $BACK_ERR(err);
            console.log(content3);
        });
    });
});

```

## Usage: Error Handling
With the `!!!` marker you can simply handle errors accessing the `error` property of the returned object. 
`value` property is assigned to the value returned by the callback.
```javascript
/*** your code: ***/
content = fs.readFile('path/to/file.txt', !!!);
if(content.error != null){
    console.error(content.error);
} else {
    console.log(content.value);
}


/*** asterx transformed code: ***/
return fs.readFile('path/to/file.txt', function (err, content) {
    content = {
        error: err,
        value: content
    };
    if(content.error != null){
        console.error(content.error);
    } else {
        console.log(content.value);
    }
});
```

## Usage: Function Declaration
You can also use the `!!` marker in place of a callback in a function declaration and simply return value with a `return`.
Asterx takes care to wrap the returned valued (or error) in the created callback.
```javascript
/*** your code: ***/
test = function(file, !!){
   exist = fs.exists(file, !!);
   return exist;
}

/*** asterx transformed code: ***/
test = function(file, $BACK){
    return fs.exists(file, function(error, exist){
        if (error) return $BACK(error);
        return $BACK(null, exist);
    });
}
```

## Try Catch Injection
As you know every callback has its own context, so if you want to catch throwed errors you have to write try-catch in every callback body.
Asterx automatically injects try-catch blocks in every generated callback, redirecting errors in the global `onError` function.
If you want to disable this feature simply set `inject_try_catch: false` in the configuration file.

## Run Batch
You can run Asterx in a shell with the following command (omitting input/output makes the batch reading and writing in the current directory):
``` asterx -i /src -o /bin ```
Here is a list of available options:
``` 
    -h, --help          output usage information
    -V, --version       output the version number
    -i, --input <dir>   defines input directory for processing files.
    -o, --output <dir>  defines output directory for procesed files.
    -m, --map [dir]     enables source maps generation and defines their directory.
    -c, --cache [dir]   enables files caching and defines directory.
    -w, --watch         enables files watching.
    -p, --compression   enables output compression.
    -l, --log           defines logging level [ALL, TRACE, DEBUG, INFO, WARNING, ERROR, FATAL].
```

## Configuration
You can setup Asterx configuration adding an `asterx.json` file in the root of your project, or where the batch is launched.
```javascript
{
   /* define input, output, source map and caching directories */
   input: ".",
   output: ".",
   map: "", /* null or empty to disable */
   cache: "", /* null or empty to disable */
   
   /* enable output compression */
   compression: false,
   
   /* enable file watching for change/add */
   watch: false,
   
   /* define logging level */
   log: "DEBUG", /* [ALL, TRACE, DEBUG, INFO, WARNING, ERROR, FATAL]. */
   
   /* define your own callback markers. */
   callback_value: "!!", 
   callback_error_value: "!!!",
   
   /* injects try-catch in every callback body.
   (errors are automatically sent to the global `onError` function). */
   inject_try_catch: true
   
}
```