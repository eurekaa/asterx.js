fs = require 'fs'
_ = require 'lodash'
_.string = require 'underscore.string'
_.mixin _.string.exports()

ast = {}
ast.parse = require('acorn').parse
ast.format = require('escodegen').generate
ast.walk = require('ast-types').visit
ast.create = require('ast-types').builders
ast.types = require('ast-types').namedTypes
# types reference: https://github.com/benjamn/ast-types/blob/master/def/core.js

source_map = require './source_map.js'



###
   @name: cps
   @description: performs continuous passing style transformation on javascript files.
   @param: input {object}:
      file {string}: path to javascript file.
      code [string]: raw javascript code. wins on options.file.
      ast [object]: valid ast object rappresenting javascript code (with locations if you want source mapping). wins on options.code and options.file.
      source_map [object|string]: if defined will try to generate a Mozilla V3 source map or to update an existing one.
         file {string}: output file path (absolute or relative to source map file).
         sources {array}: an array of source paths involved in mapping.
         sourceRoot [string]: root path prepended to source paths.
         mappings [string]: if not empty will renew the source map, creates a new one otherwise.
      options [object]: additional transformer configurations.
         value_marker [string]: the marker to be replaced with lazy callback (without returning errors).
         error_marker [string]: the marker to be replaced with strict callback (returning errors).
   @param back {function}: asynchronous callback function.
   @return output {object}:
      code {string}: transformed string code.
      source_map {object}: source map if required, null otherwise.
      warnings {array}: transformation warnings.
###

exports["transform"] = (input, back)->
   
   if not _.isFunction back then return throw new Error('callback is required {function}.')
   if not _.isObject input then return back new Error('input is required {object}.')
   if not _.isString input.file then return back new Error('input.file is required {string}.')
   try
      
      output = {}
      output.code = input.code
      output.source_map = input.source_map
      output.warnings = []
      
      input.source_map = JSON.parse input.source_map if _.isString input.source_map
      input.source_map_enabled = _.isObject input.source_map
      input.source_map_exists = (input.source_map_enabled is true and _.has(input.source_map, 'mappings') and not _.isEmpty(input.source_map.mappings))
      if input.source_map_enabled is true and not _.isString input.source_map.file then return back new Error 'input.source_map.file is required {string}.'
      if input.source_map_enabled is true and not _.isArray input.source_map.sources then return back new Error 'input.source_map.sources is required {array}.'
      
      # read code.
      input.code = fs.readFileSync input.file, 'utf-8' if not _.isString input.code or not _.isObject input.ast
      
      # skip if async markers are not present in code.
      if not _.string.include(input.code, input.options.markers.wait) and
         not _.string.include(input.code, input.options.markers.wait_err) and
         not _.string.include(input.code, input.options.markers.end)
      then return back null, output
      
      # parse code.
      input.ast = ast.parse input.code, locations: input.source_map_enabled if not _.isObject input.ast
      
      # start with continuous passing style transformation.
      callback = {}
      callback.wait = ast.create.identifier(input.options?.markers.wait)
      callback.wait_err = ast.create.identifier(input.options?.markers.wait_err)
      callback.null = ast.create.identifier 'null'
      callback.error = ast.create.identifier 'error'
      
      # transform function declarations containing callback marker.
      ast.walk input.ast, visitFunction: (path)->
         declaration = {}
         declaration.statements = path.node.body
         declaration.parameters = path.node.params
         callback.is_lazy = -> _.contains _.pluck(declaration.parameters, 'name'), callback.wait.name
         callback.is_strict = -> _.contains _.pluck(declaration.parameters, 'name'), callback.wait_err.name
         callback.name = if callback.is_lazy() then callback.wait.name else callback.wait_err.name
         callback.position = _.findIndex declaration.parameters, (parameter)-> parameter.name is callback.name
         
         if callback.is_strict() or callback.is_lazy()
            
            # rewrite return statement.
            ast.walk path.node, visitReturnStatement: (path)->
               path.get('argument').replace if callback.is_strict()
                  ast.create.callExpression(callback.wait, [callback.null, path.node.argument])
               else ast.create.conditionalExpression(callback.wait,
                     ast.create.callExpression(callback.wait, [callback.null, path.node.argument]),
                     path.node.argument
                  )
               @.traverse path
            
            # when strict replace callback parameter with lazy name and add existence test.
            if callback.is_strict()
               path.get('params', callback.position).replace callback.wait
               declaration.statements.body.unshift ast.create.ifStatement(
                  ast.create.binaryExpression('!==', ast.create.unaryExpression('typeof', callback.wait), ast.create.literal 'function'),
                  ast.create.returnStatement(ast.create.callExpression(callback.wait_err, [
                     ast.create.newExpression(ast.create.identifier('Error'), [ast.create.literal('Missing callback.')])
                  ]))
               )
            
            # inject try catch block.
            path.get('body').replace ast.create.blockStatement [ ast.create.tryStatement(
               declaration.statements,
               ast.create.catchClause(callback.error, null, ast.create.blockStatement [
                  ast.create.returnStatement(
                     ast.create.conditionalExpression(callback.wait,
                        ast.create.callExpression(callback.wait, [callback.error]),
                        ast.create.callExpression(callback.wait_err, [callback.error])
                     )
                  )
               ])
            )]
         
         @.traverse path
      
      # transform function calls containing callback marker.
      ast.walk input.ast, visitExpression: (path)->
         expression = {}
         expression.is_assigned = -> ast.types.AssignmentExpression.check path.node
         expression.call = if expression.is_assigned() then path.node.right else path.node
         expression.arguments = expression.call.arguments
         expression.is_call = -> ast.types.CallExpression.check expression.call
         callback.is_lazy = -> _.contains _.pluck(expression.arguments, 'name'), callback.wait.name
         callback.is_strict = -> _.contains _.pluck(expression.arguments, 'name'), callback.wait_err.name
         
         # transform only expression calls with callback marker.
         if expression.is_call() and (callback.is_lazy() or callback.is_strict())
            expression.node = path.parent
            expression.recipient = if expression.is_assigned() then path.node.left else null
            expression.path = if expression.is_assigned() then path.get('right') else path
            expression.position = expression.node.name
            expression.parent = expression.node.parentPath.value
            callback.name = if callback.is_lazy() then callback.wait.name else callback.wait_err.name
            callback.position = _.findIndex expression.arguments, (arg)-> arg.name is callback.name
            callback.marker = expression.path.get('arguments', callback.position)
            callback.arguments = if expression.is_assigned() then [callback.error, expression.recipient] else [callback.error]
            callback.statements = _.rest expression.parent, expression.position + 1
            
            # remove sibling statements.
            while expression.parent.length > (expression.position + 1) then expression.parent.pop()
            
            # if lazy callback automatically bubble error.
            if callback.is_lazy() then callback.statements.unshift(
               ast.create.ifStatement(
                  callback.error,
                  ast.create.returnStatement(ast.create.conditionalExpression(callback.wait,
                     ast.create.callExpression(callback.wait, [callback.error]),
                     ast.create.callExpression(callback.wait_err, [callback.error])
                  ))
               )
            )
            
            # if strict callback simply assign error (user will handle it manually).
            if expression.is_assigned() and callback.is_strict() then callback.statements.unshift(
               ast.create.expressionStatement(
                  ast.create.assignmentExpression('=',
                     expression.recipient,
                     ast.create.objectExpression([
                        ast.create.property 'init', ast.create.identifier('error'), callback.error
                        ast.create.property 'init', ast.create.identifier('value'), expression.recipient
                     ])
                  )
               )
            )
            
            # replace callback marker with callback function and nest siblings.
            callback.marker.replace ast.create.functionExpression(
               null, # function name.
               callback.arguments, # arguments
               ast.create.blockStatement callback.statements # nested statements.
            )
            
            # wrap call in a return statement.
            expression.node.replace ast.create.returnStatement(expression.call)
         
         @.traverse path
      
      
      # inject callback helper function.
      ast.walk input.ast, visitProgram: (path)->
         path.get('body').unshift ast.create.variableDeclaration('var', [ast.create.variableDeclarator(callback.wait_err,
            ast.create.functionExpression(null, [callback.error], ast.create.blockStatement([
               # declare global 'target': window if browser, global if nodejs.
               ast.create.variableDeclaration('var', [ast.create.variableDeclarator(ast.create.identifier('target'),
                  ast.create.conditionalExpression(ast.create.binaryExpression('!==',
                     ast.create.unaryExpression('typeof', ast.create.identifier('window')),
                     ast.create.literal 'undefined'),
                     ast.create.identifier('window'), ast.create.identifier('global')
                  )
               )]),
               # bubble error to 'on_error' function on target if defined, throw it otherwise.
               ast.create.ifStatement(
                  ast.create.identifier('target.on_error'),
                  ast.create.returnStatement(ast.create.callExpression(ast.create.identifier('target.on_error'),
                     [callback.error]))
                  ast.create.throwStatement(callback.error)
               )
            ]))
         )])
         # do not continue traversing.
         return false
      
      # generate code.
      transformed = ast.format input.ast,
         sourceMapWithCode: input.source_map_enabled
         sourceMap: input.source_map.sources[0] if input.source_map_enabled is true
      
      output.code = transformed.code or transformed
      
      # add escodegen missing properties.
      if input.source_map_enabled is true
         output.source_map = JSON.parse transformed.map
         output.source_map.file = input.source_map.file
         output.source_map.sourceRoot = input.source_map.sourceRoot or ''
         
         # map back to sources if an existing source map is provided.
         if input.source_map_exists is true then output.source_map = source_map.map_back output.source_map, input.source_map
      
      return back null, output
   
   catch err then return back err