(function() {
  var _, ast, fs, source_map;

  fs = require('fs');

  _ = require('lodash');

  _.string = require('underscore.string');

  _.mixin(_.string.exports());

  ast = {};

  ast.parse = require('acorn').parse;

  ast.format = require('escodegen').generate;

  ast.walk = require('ast-types').visit;

  ast.create = require('ast-types').builders;

  ast.types = require('ast-types').namedTypes;

  // types reference: https://github.com/benjamn/ast-types/blob/master/def/core.js
  source_map = require("./source_map.js");

  exports["transform"] = function(code, options, back) {
    var callback, err, output, transformed;
    try {
      if (_.isString(options.source_map)) {
        options.source_map = JSON.parse(options.source_map);
      }
      options.source_map_enabled = _.isObject(options.source_map || options.source_map === true);
      options.source_map_exists = options.source_map_enabled === true && _.has(options.source_map, 'mappings') && !_.isEmpty(options.source_map.mappings);
      
      // parse code.
      code = ast.parse(code, {
        locations: options.source_map_enabled
      });
      
      // start with continuous passing style transformation.
      callback = {};
      callback.value = ast.create.identifier(options.callback_value);
      callback.error_value = ast.create.identifier(options.callback_error_value);
      callback.null = ast.create.identifier('null');
      callback.error = ast.create.identifier('error');
      
      // transform function declarations containing callback marker.
      ast.walk(code, {
        visitFunction: function(path) {
          var declaration;
          declaration = {};
          declaration.statements = path.node.body;
          declaration.parameters = path.node.params;
          callback.is_lazy = function() {
            return _.contains(_.pluck(declaration.parameters, 'name'), callback.value.name);
          };
          callback.is_strict = function() {
            return _.contains(_.pluck(declaration.parameters, 'name'), callback.error_value.name);
          };
          callback.name = callback.is_lazy() ? callback.value.name : callback.error_value.name;
          callback.position = _.findIndex(declaration.parameters, function(parameter) {
            return parameter.name === callback.name;
          });
          if (callback.is_strict() || callback.is_lazy()) {
            
            // rewrite return statement.
            ast.walk(path.node, {
              visitReturnStatement: function(path) {
                path.get('argument').replace(callback.is_strict() ? ast.create.callExpression(callback.value, [callback.null, path.node.argument]) : ast.create.conditionalExpression(callback.value, ast.create.callExpression(callback.value, [callback.null, path.node.argument]), path.node.argument));
                return this.traverse(path);
              }
            });
            
            // when strict replace callback parameter with lazy name and add existence test.
            if (callback.is_strict()) {
              path.get('params', callback.position).replace(callback.value);
              declaration.statements.body.unshift(ast.create.ifStatement(ast.create.binaryExpression('!==', ast.create.unaryExpression('typeof', callback.value), ast.create.literal('function')), ast.create.returnStatement(ast.create.callExpression(callback.error_value, [ast.create.newExpression(ast.create.identifier('Error'), [ast.create.literal('Missing callback.')])]))));
            }
            
            // inject try catch block.
            if (options.inject_try_catch === true) {
              path.get('body').replace(ast.create.blockStatement([ast.create.tryStatement(declaration.statements, ast.create.catchClause(callback.error, null, ast.create.blockStatement([ast.create.returnStatement(ast.create.conditionalExpression(callback.value, ast.create.callExpression(callback.value, [callback.error]), ast.create.callExpression(callback.error_value, [callback.error])))])))]));
            }
          }
          return this.traverse(path);
        }
      });
      
      // transform function calls containing callback marker.
      ast.walk(code, {
        visitExpression: function(path) {
          var expression;
          expression = {};
          expression.is_assigned = function() {
            return ast.types.AssignmentExpression.check(path.node);
          };
          expression.call = expression.is_assigned() ? path.node.right : path.node;
          expression.arguments = expression.call.arguments;
          expression.is_call = function() {
            return ast.types.CallExpression.check(expression.call);
          };
          callback.is_lazy = function() {
            return _.contains(_.pluck(expression.arguments, 'name'), callback.value.name);
          };
          callback.is_strict = function() {
            return _.contains(_.pluck(expression.arguments, 'name'), callback.error_value.name);
          };
          
          // transform only expression calls with callback marker.
          if (expression.is_call() && (callback.is_lazy() || callback.is_strict())) {
            expression.node = path.parent;
            expression.recipient = expression.is_assigned() ? path.node.left : null;
            expression.path = expression.is_assigned() ? path.get('right') : path;
            expression.position = expression.node.name;
            expression.parent = expression.node.parentPath.value;
            callback.name = callback.is_lazy() ? callback.value.name : callback.error_value.name;
            callback.position = _.findIndex(expression.arguments, function(arg) {
              return arg.name === callback.name;
            });
            callback.marker = expression.path.get('arguments', callback.position);
            callback.arguments = expression.is_assigned() ? [callback.error, expression.recipient] : [callback.error];
            callback.statements = _.rest(expression.parent, expression.position + 1);
            
            // remove sibling statements.
            while (expression.parent.length > (expression.position + 1)) {
              expression.parent.pop();
            }
            
            // if lazy callback automatically bubble error.
            if (callback.is_lazy()) {
              callback.statements.unshift(ast.create.ifStatement(callback.error, ast.create.returnStatement(ast.create.conditionalExpression(callback.value, ast.create.callExpression(callback.value, [callback.error]), ast.create.callExpression(callback.error_value, [callback.error])))));
            }
            
            // if strict callback simply assign error (user will handle it manually).
            if (expression.is_assigned() && callback.is_strict()) {
              callback.statements.unshift(ast.create.expressionStatement(ast.create.assignmentExpression('=', expression.recipient, ast.create.objectExpression([ast.create.property('init', ast.create.identifier('error'), callback.error), ast.create.property('init', ast.create.identifier('value'), expression.recipient)]))));
            }
            
            // replace callback marker with callback function and nest siblings.
            if (options.inject_try_catch === true) {
              callback.marker.replace(ast.create.functionExpression(null, callback.arguments, ast.create.blockStatement([ast.create.tryStatement(ast.create.blockStatement(callback.statements), ast.create.catchClause(callback.error, null, ast.create.blockStatement([ast.create.returnStatement(ast.create.conditionalExpression(callback.value, ast.create.callExpression(callback.value, [callback.error]), ast.create.callExpression(callback.error_value, [callback.error])))])))]))); // function name. // arguments
            } else {
              callback.marker.replace(ast.create.functionExpression(null, callback.arguments, ast.create.blockStatement(callback.statements))); // function name. // arguments // nested statements.
            }
            
            // wrap call in a return statement.
            expression.node.replace(ast.create.returnStatement(expression.call));
          }
          return this.traverse(path);
        }
      });
      
      // inject callback helper function.
      ast.walk(code, {
        visitProgram: function(path) {
          path.get('body').unshift(ast.create.variableDeclaration('var', [
            ast.create.variableDeclarator(callback.error_value,
            ast.create.functionExpression(null,
            [callback.error],
            ast.create.blockStatement([
              // declare global 'target': window if browser, global if nodejs.
              ast.create.variableDeclaration('var',
              [ast.create.variableDeclarator(ast.create.identifier('target'),
              ast.create.conditionalExpression(ast.create.binaryExpression('!==',
              ast.create.unaryExpression('typeof',
              ast.create.identifier('window')),
              ast.create.literal('undefined')),
              ast.create.identifier('window'),
              ast.create.identifier('global')))]),
              // bubble error to 'on_error' function on target if defined, throw it otherwise.
              ast.create.ifStatement(ast.create.identifier('target.onError'),
              ast.create.returnStatement(ast.create.callExpression(ast.create.identifier('target.onError'),
              [callback.error])),
              ast.create.throwStatement(callback.error))
            ])))
          ]));
          // do not continue traversing.
          return false;
        }
      });
      // generate code.
      output = {};
      transformed = ast.format(code, {
        sourceMapWithCode: options.source_map_enabled,
        sourceMap: options.source_map_enabled === true ? options.source_map.sources[0] : void 0
      });
      output.code = transformed.code || transformed;
      
      // add escodegen missing properties.
      if (options.source_map_enabled === true) {
        output.source_map = JSON.parse(transformed.map);
        output.source_map.file = options.source_map.file;
        output.source_map.sourceRoot = options.source_map.sourceRoot || '';
        
        // map back to sources if an existing source map is provided.
        if (options.source_map_exists === true) {
          output.source_map = source_map.map_back(output.source_map, options.source_map);
        }
      }
      return back(null, output);
    } catch (error) {
      err = error;
      return back(err);
    }
  };

}).call(this);


//# sourceMappingURL=asterx.js.map
//# sourceURL=coffeescript