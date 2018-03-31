(function() {
  // Company: Eureka²
  // Developer: Stefano Graziato
  // Email: stefano.graziato@eurekaa.it
  // Homepage: http://www.eurekaa.it
  // GitHub: https://github.com/eurekaa

  // File Name: source_map
  // Created: 18/09/2014 11:24
  var source_map;

  source_map = require('source-map');

  exports['create'] = function() {
    return new source_map.SourceMapGenerator();
  };

  exports['parse'] = function(map) {
    return new source_map.SourceMapConsumer(map);
  };

  exports['map_back'] = function(generated, original) {
    var renewed;
    renewed = this.create();
    generated = this.parse(generated);
    original = this.parse(original);
    original.eachMapping(function(original_mapping) {
      var generated_mapping;
      generated_mapping = generated.generatedPositionFor({
        source: original_mapping.source,
        line: original_mapping.generatedLine,
        column: original_mapping.generatedColumn
      });
      if (generated_mapping.line !== null && generated_mapping !== null) {
        return renewed.addMapping({
          original: {
            line: original_mapping.originalLine,
            column: original_mapping.originalColumn
          },
          generated: {
            line: generated_mapping.line,
            column: generated_mapping.column
          },
          source: original_mapping.source,
          name: original_mapping.name
        });
      }
    });
    renewed = JSON.parse(renewed.toString());
    renewed.file = original.file;
    return renewed;
  };

  exports['get_original_position'] = function(map, position) {
    map = this.parse(map);
    return map.originalPositionFor(position);
  };

}).call(this);


//# sourceMappingURL=source_map.js.map
//# sourceURL=coffeescript