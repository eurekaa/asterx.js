(function() {
  var _, asterx, async, chokidar, coffeescript, commander, config, fs, fs_tools, info, log4js, path, stats, string, uglify;

  commander = require("commander");

  fs = require("fs");

  fs_tools = require("fs-tools");

  path = require("path");

  string = require("string");

  async = require("async");

  _ = require("lodash");

  _.mixin(require("underscore.string").exports());

  log4js = require("log4js");

  coffeescript = require("coffee-script");

  chokidar = require("chokidar");

  uglify = require("uglify-js");

  asterx = require("./asterx.js");

  info = require("../package.json");

  config = {
    input: "./src/test",
    output: "./src/test",
    map: "./src/test",
    cache: "",
    watch: false,
    log: "DEBUG",
    callback_value: "!!",
    callback_error_value: "!!!",
    inject_try_catch: true,
    compression: false
  };

  stats = {
    processed: 0,
    skipped: 0,
    failures: 0,
    successes: 0,
    started: null,
    ended: null,
    duration: 0
  };

  exports["info"] = function() {
    return {
      name: info.name,
      version: info.version,
      author: info.author,
      description: info.description,
      license: info.license,
      repository: info.repository.url,
      bugs: info.bugs.url
    };
  };

  exports["api"] = {
    transform: asterx.transform
  };

  exports["setup"] = function(options) { // load and merge with user config.
    var err, user_config, user_dir;
    try {
      user_dir = path.resolve(process.cwd());
      if (fs.existsSync(user_dir + "\\asterx.json")) {
        user_config = fs.readFileSync(user_dir + "\\asterx.json", "utf8");
        user_config = user_config.replace(/\/\*([\s\S]*?)\*\//igm, ""); // strip multi-line comments.
        user_config = user_config.replace(/\/\/.+/igm, ""); // strip single-line comments.
        user_config = JSON.parse(user_config);
        config = _.merge(config, user_config);
      }
    } catch (error) {
      err = error;
      throw new Error + " asterx.json: " + err;
    }
    
    // merge config with (eventually) provided options.
    config = _.merge(config, options || {});
    
    // init logs.
    return log4js.configure({
      appenders: [
        {
          type: "logLevelFilter",
          level: config.log,
          appender: {
            type: "console",
            layout: {
              type: "pattern",
              pattern: "%[[%p]%] %m"
            }
          }
        }
      ]
    });
  };

  exports["run"] = function(input, done) {
    var args, logger, self;
    self = this;
    
    // setup with command line arguments
    commander.version(this.info().version);
    commander.usage("[options]");
    commander.option("-i, --input <dir>", "defines input directory for processing files.");
    commander.option("-o, --output <dir>", "defines output directory for procesed files.");
    commander.option("-m, --map [dir]", "enables source maps generation and defines their directory.");
    commander.option("-c, --cache [dir]", "enables files caching and defines directory.");
    commander.option("-w, --watch", "enables files watching.");
    commander.option("-p, --compression", "enables output compression.");
    commander.option("-l, --log", "defines logging level [ALL, TRACE, DEBUG, INFO, WARNING, ERROR, FATAL].");
    commander.parse(process.argv);
    args = {};
    if (_.isString(commander.input)) {
      args.input = path.normalize(commander.input);
    }
    if (_.isString(commander.output)) {
      args.output = path.normalize(commander.output);
    }
    if (_.isString(commander.map)) {
      args.map = path.normalize(commander.map);
    }
    if (_.isString(commander.cache)) {
      args.cache = path.normalize(commander.cache);
    }
    if (commander.watch) {
      args.watch = true;
    }
    if (commander.compression) {
      args.compression = true;
    }
    if (_.isString(commander.log)) {
      args.log = commander.log;
    }
    this.setup(args);
    
    // init stats.
    stats.processed = 0;
    stats.skipped = 0;
    stats.failures = 0;
    stats.successes = 0;
    stats.started = Date.now();
    logger = log4js.getDefaultLogger();
    logger.info("*********** ASTERX " + info.version + " **********");
    logger.debug("[input: " + config.input + ", output: " + config.output + "]\n");
    
    // walk through input and process each file.
    return fs_tools.walk(config.input, function(file, info, next) {
      return self.process_file(file, next);
    }, function(err) {
      var watcher;
      
      // keep watching for files changes
      if (config.watch === true) {
        watcher = chokidar.watch(config.input, {
          persistent: true
        });
        watcher.on("add", function(file) {
          return self.process_file(file, function() {});
        });
        watcher.on("change", function(file) {
          return self.process_file(file, function() {});
        });
      }
      
      // log stats.
      stats.ended = Date.now();
      stats.duration = ((stats.ended - stats.started) / 1000) + "s";
      logger.debug(`[processed: ${stats.processed}, skipped: ${stats.skipped}]`);
      logger.debug(`[successes: ${stats.successes}, failures: ${stats.failures}]`);
      logger.debug(`[duration: ${stats.duration}]`);
      if (config.watch === false) {
        logger.info("********** ASTERX DONE! **********\n");
      }
      if (done) {
        return done(err, stats);
      }
    });
  };

  exports["process_file"] = function(file, done) {
    var cache, failed, input, log, output, source_map;
    input = {};
    input.extension = path.extname(file).replace(".", "").toLowerCase();
    input.file = path.normalize(file);
    input.directory = path.normalize(path.dirname(input.file));
    input.code = "";
    output = {};
    output.extension = "js";
    output.file = path.normalize(config.output + "/" + path.basename(input.file, path.extname(input.file)) + "." + output.extension);
    output.directory = path.normalize(path.dirname(output.file));
    output.code = "";
    source_map = {};
    source_map.is_enabled = config.map !== "" && config.map !== null;
    if (source_map.is_enabled) {
      source_map.extension = "map";
      source_map.file = path.normalize(config.map + "/" + path.basename(input.file, path.extname(input.file)) + "." + output.extension + "." + source_map.extension);
      source_map.directory = path.normalize(path.dirname(source_map.file));
      source_map.link = '/*# sourceMappingURL=' + path.normalize(path.relative(output.directory, source_map.directory) + "/" + path.basename(source_map.file)) + " */";
      source_map.code = {
        file: path.normalize(path.relative(source_map.directory, output.file)),
        sources: [path.normalize(path.relative(source_map.directory, input.file))]
      };
    }
    cache = {};
    cache.is_enabled = config.cache !== "" && config.cache !== null;
    if (cache.is_enabled) {
      cache.extension = "cache";
      cache.file = path.normalize(config.cache + "/" + path.basename(input.file, path.extname(input.file)) + "." + cache.extension);
      cache.directory = path.normalize(path.dirname(cache.file));
      cache.code = "";
    }
    
    // skip non javascript files.
    if (input.extension.toLowerCase() !== "coffee" && input.extension.toLowerCase() !== "js") {
      stats.skipped++;
      return done();
    }
    
    // read from cache and skip if source file is not changed.
    if (cache.is_enabled && fs.existsSync(cache.file) && (fs.lstatSync(input.file).mtime <= fs.lstatSync(cache.file).mtime)) {
      stats.skipped++;
      return done();
    }
    
    // start processing input file.
    stats.processed++;
    log = log4js.getBufferedLogger("");
    log.info("processing file: " + input.file);
    failed = false;
    return async.series([
      
      // read input file.
      function(back) {
        return fs.readFile(input.file,
      function(err,
      result) {
          if (err) {
            failed = true;
            log.error(err.message);
            log.trace(err.stack);
            log.error("reading input: FAILED!");
          } else {
            output.code = result;
            log.debug("reading input: DONE!");
          }
          return back();
        });
      },
      
      // pre-compilation stuffs.
      function(back) {
        if (failed === true) {
          return back();
        }
        
        // strip coffee comments.
        if (input.extension === "coffee") {
          output.code = string(output.code).replace(/\/\*(?:(?!\*\/)[\s\S])*\*\//igm,
      "").replace(/^\s*#{3}(?:(?!#)[\s\S])*#{3}/igm,
      "").replace(/^#{1}[^#{2,}][^\n|\r]*/igm,
      "").replace(/\/\/[^\n|\r]*/igm,
      "").toString();
        }
        
        // strip javascript comments.
        if (input.extension === "js") {
          output.code = string(output.code).replace(/\/\*([\s\S]*?)\*\//igm,
      "").replace(/\/\/.+/igm,
      "").toString();
        }
        
        // replace callback markers with safer ones.
        output.code = string(output.code).replaceAll(config.callback_error_value,
      "$BACK_ERR").replaceAll(config.callback_value,
      "$BACK").toString();
        return back();
      },
      
      // coffee-script compilation.
      function(back) {
        var compiled,
      err,
      options;
        if (failed === true) {
          return back();
        }
        if (input.extension.toLowerCase() !== "coffee") {
          return back();
        }
        try {
          options = {};
          options.filename = input.file;
          if (source_map.is_enabled) {
            options.sourceMap = true;
            options.sourceRoot = "";
            options.sourceFiles = source_map.sources;
            options.generatedFile = source_map.file;
          }
          compiled = coffeescript.compile(output.code,
      options);
          output.code = compiled.js || compiled;
          if (compiled.v3SourceMap) {
            compiled.v3SourceMap = JSON.parse(compiled.v3SourceMap);
            compiled.v3SourceMap.sources = source_map.code.sources;
            compiled.v3SourceMap.file = source_map.code.file;
            source_map.code = compiled.v3SourceMap;
          }
          log.debug("coffee-script compilation: DONE!");
          return back();
        } catch (error) {
          err = error;
          failed = true;
          log.error(err.message);
          log.trace(err.stack);
          log.error("coffee-script compilation: FAILED!");
          return back();
        }
      },
      
      // callback transformation.
      function(back) {
        var options;
        if (failed === true) {
          return back();
        }
        if (!(string(output.code).contains("$BACK_ERR") || string(output.code).contains("$BACK"))) {
          return back();
        }
        options = {};
        if (source_map.is_enabled) {
          options.source_map = source_map.code;
        }
        options.callback_value = "$BACK";
        options.callback_error_value = "$BACK_ERR";
        options.inject_try_catch = config.inject_try_catch;
        return asterx.transform(output.code,
      options,
      function(err,
      result) {
          if (err) {
            failed = true;
            log.error(err.message);
            log.trace(err.stack);
            log.error("callback transformation: FAILED!");
          } else {
            output.code = result.code;
            source_map.code = result.source_map;
            log.debug("callback transformation: DONE!");
          }
          return back();
        });
      },
      
      // compression.
      function(back) {
        var ast,
      compressor,
      err,
      options,
      stream;
        try {
          if (failed === true) {
            return back();
          }
          if (config.compression !== true) {
            return back();
          }
          // parse code.
          ast = uglify.parse(output.code);
          // compress ast.
          ast.figure_out_scope();
          compressor = uglify.Compressor({
            warnings: false
          });
          ast = ast.transform(compressor);
          // mangle names.
          ast.figure_out_scope();
          ast.compute_char_frequency();
          ast.mangle_names();
          // generate compressed code.
          options = {};
          if (source_map.is_enabled === true) {
            options.source_map = uglify.SourceMap({
              file: source_map.code.file || "",
              root: source_map.code.sourceRoot || "",
              // if a source map is present map back to source file.
              orig: _.has(source_map.code,
      "mappings") ? source_map.code : void 0
            });
          }
          stream = uglify.OutputStream(options);
          ast.print(stream);
          output.code = stream.toString();
          if (source_map.is_enabled === true) {
            options.source_map = JSON.parse(options.source_map.toString());
            options.source_map.sources = source_map.code.sources || [];
            source_map.code = options.source_map;
          }
          log.debug("compression: DONE!");
          return back();
        } catch (error) {
          err = error;
          failed = true;
          log.error(err.message);
          log.trace(err.stack);
          log.error("compression: FAILED!");
          return back();
        }
      },
      
      // write output file.
      function(back) {
        if (failed === true) {
          return back();
        }
        // add source map reference to output.
        if (_.has(source_map.code,
      "mappings")) {
          output.code += "\n" + source_map.link;
        }
        return async.series([
          function(back) {
            return fs_tools.mkdir(output.directory,
          back);
          },
          function(back) {
            return fs.writeFile(output.file,
          output.code,
          back);
          }
        ],
      function(err) {
          if (err) {
            failed = true;
            log.error(err.message);
            log.trace(err.stack);
            log.error("writing output: FAILED!");
          } else {
            log.debug("writing output: DONE!");
          }
          return back();
        });
      },
      
      // write source map.
      function(back) {
        if (failed === true) {
          return back();
        }
        if (source_map.is_enabled !== true) {
          return back();
        }
        // skip if source map is not present.
        if (!_.has(source_map.code,
      'mappings')) {
          return back();
        }
        // stringify and write source maps.
        if (_.isObject(source_map.code)) {
          source_map.code = JSON.stringify(source_map.code,
      null,
      4);
        }
        return async.series([
          function(back) {
            return fs_tools.mkdir(source_map.directory,
          back);
          },
          function(back) {
            return fs.writeFile(source_map.file,
          source_map.code,
          back);
          }
        ],
      function(err) {
          if (err) {
            failed = failed; // do not stop processing.
            log.error(err.message);
            log.trace(err.stack);
            log.warn("source mapping: FAILED!");
          } else {
            log.debug("source mapping: DONE!");
          }
          return back();
        });
      },
      
      // write cache file.
      function(back) {
        if (failed === true) {
          return back();
        }
        if (cache.is_enabled !== true) {
          return back();
        }
        return async.series([
          function(back) {
            return fs_tools.mkdir(cache.directory,
          back);
          },
          function(back) {
            return fs.writeFile(cache.file,
          cache.code,
          back);
          }
        ],
      function(err) {
          if (err) {
            failed = failed; // do not stop processing.
            log.error(err.message);
            log.trace(err.stack);
            log.warn("caching: FAILED!");
          } else {
            log.debug("caching: DONE!");
          }
          return back();
        });
      },
      
      // log end processing file.
      function(back) {
        if (failed === true) {
          stats.failures++;
          log.error("processing file: FAILED!\n");
        } else {
          stats.successes++;
          log.info("processing file: DONE!\n");
        }
        log.flush();
        return back();
      }
    ], function(err) {
      if (done) {
        return done(err, stats);
      }
    });
  };

  this.run();

}).call(this);


//# sourceMappingURL=index.js.map
//# sourceURL=coffeescript