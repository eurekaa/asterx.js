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

source_map = require "./source_map.js"

exports["transform"] = (code, options, back)->
   try
      options.source_map = JSON.parse options.source_map if _.isString options.source_map
      options.source_map_enabled = _.isObject options.source_map or options.source_map is true
      options.source_map_exists = (options.source_map_enabled is true and _.has(options.source_map, 'mappings') and not _.isEmpty(options.source_map.mappings))
      
      # parse code.
      code = ast.parse code, locations: options.source_map_enabled
      
      # start with continuous passing style transformation.
      callback = {}
      callback.value = ast.create.identifier(options.callback_value)
      callback.error_value = ast.create.identifier(options.callback_error_value)
      callback.null = ast.create.identifier 'null'
      callback.error = ast.create.identifier 'error'
      
      # transform function declarations containing callback marker.
      ast.walk code, visitFunction: (path)->
         declaration = {}
         declaration.statements = path.node.body
         declaration.parameters = path.node.params
         callback.is_lazy = -> _.contains _.pluck(declaration.parameters, 'name'), callback.value.name
         callback.is_strict = -> _.contains _.pluck(declaration.parameters, 'name'), callback.error_value.name
         callback.name = if callback.is_lazy() then callback.value.name else callback.error_value.name
         callback.position = _.findIndex declaration.parameters, (parameter)-> parameter.name is callback.name
         
         if callback.is_strict() or callback.is_lazy()
            
            # rewrite return statement.
            ast.walk path.node, visitReturnStatement: (path)->
               path.get('argument').replace if callback.is_strict()
                  ast.create.callExpression(callback.value, [callback.null, path.node.argument])
               else ast.create.conditionalExpression(callback.value,
                     ast.create.callExpression(callback.value, [callback.null, path.node.argument]),
                     path.node.argument
                  )
               @.traverse path
            
            # when strict replace callback parameter with lazy name and add existence test.
            if callback.is_strict()
               path.get('params', callback.position).replace callback.value
               declaration.statements.body.unshift ast.create.ifStatement(
                  ast.create.binaryExpression('!==', ast.create.unaryExpression('typeof', callback.value), ast.create.literal 'function'),
                  ast.create.returnStatement(ast.create.callExpression(callback.error_value, [
                     ast.create.newExpression(ast.create.identifier('Error'), [ast.create.literal('Missing callback.')])
                  ]))
               )
            
            # inject try catch block.
            if options.inject_try_catch is true
               path.get('body').replace ast.create.blockStatement [ ast.create.tryStatement(
                  declaration.statements,
                  ast.create.catchClause(callback.error, null, ast.create.blockStatement [
                     ast.create.returnStatement(
                        ast.create.conditionalExpression(callback.value,
                           ast.create.callExpression(callback.value, [callback.error]),
                           ast.create.callExpression(callback.error_value, [callback.error])
                        )
                     )
                  ])
               )]
         
         @.traverse path
      
         
      # transform function calls containing callback marker.
      ast.walk code, visitExpression: (path)->
         expression = {}
         expression.is_assigned = -> ast.types.AssignmentExpression.check path.node
         expression.call = if expression.is_assigned() then path.node.right else path.node
         expression.arguments = expression.call.arguments
         expression.is_call = -> ast.types.CallExpression.check expression.call
         callback.is_lazy = -> _.contains _.pluck(expression.arguments, 'name'), callback.value.name
         callback.is_strict = -> _.contains _.pluck(expression.arguments, 'name'), callback.error_value.name
         
         # transform only expression calls with callback marker.
         if expression.is_call() and (callback.is_lazy() or callback.is_strict())
            expression.node = path.parent
            expression.recipient = if expression.is_assigned() then path.node.left else null
            expression.path = if expression.is_assigned() then path.get('right') else path
            expression.position = expression.node.name
            expression.parent = expression.node.parentPath.value
            callback.name = if callback.is_lazy() then callback.value.name else callback.error_value.name
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
                  ast.create.returnStatement(ast.create.conditionalExpression(callback.value,
                     ast.create.callExpression(callback.value, [callback.error]),
                     ast.create.callExpression(callback.error_value, [callback.error])
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
            if options.inject_try_catch is true
               callback.marker.replace ast.create.functionExpression(
                  null, # function name.
                  callback.arguments, # arguments
                  ast.create.blockStatement [ ast.create.tryStatement(
                     ast.create.blockStatement(callback.statements),
                     ast.create.catchClause(callback.error, null, ast.create.blockStatement [
                        ast.create.returnStatement(
                           ast.create.conditionalExpression(callback.value,
                              ast.create.callExpression(callback.value, [callback.error]),
                              ast.create.callExpression(callback.error_value, [callback.error])
                           )
                        )
                     ])
                  )]
               )
            else
               callback.marker.replace ast.create.functionExpression(
                  null, # function name.
                  callback.arguments, # arguments
                  ast.create.blockStatement callback.statements # nested statements.
               )
               
            
            # wrap call in a return statement.
            expression.node.replace ast.create.returnStatement(expression.call)
                     
         @.traverse path
      
      
      # inject callback helper function.
      ast.walk code, visitProgram: (path)->
         path.get('body').unshift ast.create.variableDeclaration('var', [ast.create.variableDeclarator(callback.error_value,
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
                  ast.create.identifier('target.onError'),
                  ast.create.returnStatement(ast.create.callExpression(ast.create.identifier('target.onError'),
                     [callback.error]))
                  ast.create.throwStatement(callback.error)
               )
            ]))
         )])
         # do not continue traversing.
         return false

      # generate code.
      output = {}
      transformed = ast.format code,
         sourceMapWithCode: options.source_map_enabled
         sourceMap: options.source_map.sources[0] if options.source_map_enabled is true
      output.code = transformed.code or transformed
      
      # add escodegen missing properties.
      if options.source_map_enabled is true
         output.source_map = JSON.parse transformed.map
         output.source_map.file = options.source_map.file
         output.source_map.sourceRoot = options.source_map.sourceRoot or ''
         
         # map back to sources if an existing source map is provided.
         if options.source_map_exists is true then output.source_map = source_map.map_back output.source_map, options.source_map
      
      return back null, output
   
   catch err then return back err