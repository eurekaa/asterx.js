commander = require "commander"
fs = require "fs"
fs_tools = require "fs-tools"
path = require "path"
string = require "string"
async = require "async"
_ = require "lodash"
_.mixin require("underscore.string").exports()
log4js = require "log4js"
coffeescript = require "coffee-script"
asterx = require "./asterx.js"
info = require "../package.json"


exports["info"] = ->
   name: info.name
   version: info.version
   author: info.author
   description: info.description
   license: info.license
   repository: info.repository.url
   bugs: info.bugs.url


config = null
exports["setup"] = (options)->
   
   try # load asterx config.
      config = fs.readFileSync __dirname + "\\..\\asterx.json", "utf8"
      config = config.replace /\/\*[^\/\*]*\*\//igm, "" # strip multi-line comments.
      config = config.replace /\/\/.+/igm, "" # strip single-line comments.
      config = JSON.parse config
   catch err then throw new Error + " asterx.json: " + err
   
   try # load and merge with user config.
      user_dir = path.resolve process.cwd()
      if fs.existsSync(user_dir + "\\asterx.json")
         user_config = fs.readFileSync user_dir + "\\asterx.json", "utf8"
         user_config = user_config.replace /\/\*[^\/\*]*\*\//igm, "" # strip multi-line comments.
         user_config = user_config.replace /\/\/.+/igm, "" # strip single-line comments.
         user_config = JSON.parse user_config
         config = _.merge config, user_config
   catch err then throw new Error + " asterx.json: " + err
   
   # merge config with (eventually) provided options.
   config = _.merge config, (options or {})
   
   # init logs.
   log4js.configure appenders: [
      type: "logLevelFilter"
      level: config.log
      appender:
         type: "console"
         layout:
            type: "pattern", pattern: "%[[%p]%] %m"
   ]
   


exports["run"] = ->
   
   # setup with command line arguments
   commander.version @.info().version
   commander.usage "[options]"
   commander.option "-i, --input <dir>", "defines input directory for processing files."
   commander.option "-o, --output <dir>", "defines output directory for procesed files."
   commander.option "-s, --source_map [dir]", "enables source maps generation and defines directory."
   commander.option "-c, --cache [dir]", "enables files caching and defines directory."
   commander.option "-l, --log", "enables logging and optionally defines level."
   commander.parse process.argv
   args = {}
   args.input = path.normalize commander.input if _.isString commander.input
   args.output = path.normalize commander.output if _.isString commander.output
   args.source_map = path.normalize commander.source_map if _.isString commander.source_map
   args.cache = path.normalize commander.cache if _.isString commander.cache
   args.log = commander.log if _.isString commander.log
   @.setup args
   
   # init stats.
   batch = {}
   batch.directory = path.resolve process.cwd()
   batch.processed = 0
   batch.skipped = 0
   batch.failures = 0
   batch.successes = 0
   batch.started = Date.now()
      
   # walk through input and process each file.
   log = log4js.getDefaultLogger()
   log.info "*********** ASTERX " + info.version + " **********"
   log.debug "[input: " + config.input + ", output: " + config.output + "]\n"
   fs_tools.walk config.input, (input_file, input_info, next)->
      
      input = {}
      input.extension = path.extname(input_file).replace(".", "").toLowerCase()
      input.file = input_file
      input.directory = path.dirname input.file
      input.code = ""
      
      output = {}
      output.extension = "js"
      output.file = input.file.replace(config.input, config.output).replace "." + input.extension, "." + output.extension
      output.directory = config.output + "\\" + path.dirname path.relative(config.output, output.file)
      output.code = ""
      
      source_map = {}
      source_map.extension = "map"
      source_map.file = input.file.replace(config.input, config.source_map).replace("." + input.extension, "." + output.extension + "." + source_map.extension)
      source_map.directory = config.source_map + "\\" + path.dirname path.relative(config.source_map, source_map.file)
      source_map.link = '/*# sourceMappingURL=' + path.relative(output.directory, source_map.directory) + "\\" + path.basename(source_map.file) + " */"
      source_map.code =
         file: path.resolve(output.file),
         sources: [path.relative(source_map.directory, input.file)]
               
      cache = {}
      cache.extension = "cache"
      cache.file = input.file.replace(config.input, config.cache).replace("." + input.extension, "." + cache.extension)
      cache.directory = config.cache + "\\" + path.dirname path.relative(config.cache, cache.file)
      cache.code = ""
      
      # skip output, cache and source_map directories.
      if config.input isnt config.output and string(input.directory).contains(config.output) then return next()
      if config.input isnt config.cache and string(input.directory).contains(config.cache) then return next()
      if config.input isnt config.source_map and string(input.directory).contains(config.source_map) then return next()
      
      # read from cache and skip if source file is not changed.
      if fs.existsSync(cache.file) and (input_info.mtime <= fs.lstatSync(cache.file).mtime) then batch.skipped++; return next()
      
      # start processing input file.
      batch.processed++
      log = log4js.getBufferedLogger ""
      log.info "processing file: " + input.file
      failed = false
      async.series [
         
         # read input file.
         (back)->
            fs.readFile input.file, (err, result)->
               if err
                  failed = true
                  log.error err.message
                  log.trace err.stack
                  log.error "reading input: FAILED!"
               else
                  input.code = result
                  log.debug "reading input: DONE!"
               return back()
         
         
         # replace callback markers with safer ones.
         (back)->
            if failed is true then return back()
            output.code = string(input.code)
            .replaceAll config.callback_error_value, "$BACK_ERR"
            .replaceAll config.callback_value, "$BACK"
            .toString()
            return back()
         
         
         # coffee-script compilation.
         (back)->
            if failed is true then return back()
            if input.extension isnt "coffee" then return back()
            try
               compiled = coffeescript.compile output.code,
                  filename: input.file
                  sourceMap: true
                  sourceRoot: ""
                  sourceFiles: source_map.sources
                  generatedFile: source_map.file
               output.code = compiled.js or compiled
               output.source_map = JSON.parse compiled.v3SourceMap if compiled.v3SourceMap
               log.debug "coffee-script compilation: DONE!"
            catch err
               failed = true
               log.error err.message
               log.trace err.stack
               log.error "coffee-script compilation: FAILED!"
            return back()
         
         
         # callback transformation.
         (back)->
            if failed is true then return back()
            if not (string(output.code).contains "$BACK_ERR" or string(output.code).contains "$BACK") then return back()
            asterx.transform
               file: output.file
               code: output.code
               source_map: source_map.code
               options:
                  callback_value: "$BACK",
                  callback_error_value: "$BACK_ERR"
            , (err, result)->
               if err
                  failed = true
                  log.error err.message
                  log.trace err.stack
                  log.error "callback transformation: FAILED!"
               else
                  output.code = result.code
                  source_map.code = result.source_map
                  log.debug "callback transformation: DONE!"
               return back()
         
                  
         # write output file.
         (back)->
            if failed is true then return back()
            # add source map reference to output.
            if _.has source_map.code, 'mappings' then output.code += "\n" + source_map.link
            async.series [
               (back)-> fs_tools.mkdir output.directory, back
               (back)-> fs.writeFile output.file, output.code, back
            ], (err)->
               if err
                  failed = true
                  log.error err.message
                  log.trace err.stack
                  log.error "writing output: FAILED!"
               return back()
         
         
         # write source map.
         (back)->
            if failed is true then return back()
            # skip if source map is not present.
            if not _.has source_map.code, 'mappings' then return back()
            # stringify and write source maps.
            if _.isObject source_map.code then source_map.code = JSON.stringify source_map.code, null, 4
            async.series [
               (back)-> fs_tools.mkdir source_map.directory, back
               (back)-> fs.writeFile source_map.file, source_map.code, back
            ], (err)->
               if err
                  failed = failed # do not stop processing.
                  log.error err.message
                  log.trace err.stack
                  log.warn "source mapping: FAILED!"
               else log.debug "source mapping: DONE!"
               return back()
         
         
         # write cache file.
         (back)->
            if failed is true then return back()
            async.series [
               (back)-> fs_tools.mkdir cache.directory, back
               (back)-> fs.writeFile cache.file, cache.code, back
            ], (err)->
               if err
                  failed = failed # do not stop processing.
                  log.error err.message
                  log.trace err.stack
                  log.warn "caching: FAILED!"
               else log.debug "caching: DONE!"
               return back()
         
         
         # log end processing file.
         (back)->
            if failed is true
               batch.failures++
               log.error "processing file: FAILED!\n"
            else
               batch.successes++
               log.info "processing file: DONE!\n"
            log.flush()
            return back()
      
      ], next
   
   , -> # end of input walk (errors are self printed by each file).
      batch.ended = Date.now()
      batch.duration = ((batch.ended - batch.started) / 1000) + "s"
      log = log4js.getDefaultLogger()
      log.debug """[processed: #{batch.processed}, skipped: #{batch.skipped}]"""
      log.debug """[successes: #{batch.successes}, failures: #{batch.failures}]"""
      log.debug """[duration: #{batch.duration}]"""
      log.info '********** ASTERX DONE! **********'
      