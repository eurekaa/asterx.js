# Company: Eureka²
# Developer: Stefano Graziato
# Email: stefano.graziato@eurekaa.it
# Homepage: http://www.eurekaa.it
# GitHub: https://github.com/eurekaa

# File Name: source_map
# Created: 18/09/2014 11:24

source_map = require 'source-map'


exports['create'] = -> new source_map.SourceMapGenerator()


exports['parse'] = (map)-> new source_map.SourceMapConsumer map


exports['map_back'] = (generated, original)->
   renewed = @.create()
   generated = @.parse generated
   original = @.parse original
   original.eachMapping (original_mapping)->
      generated_mapping = generated.generatedPositionFor 
         source: original_mapping.source
         line: original_mapping.generatedLine
         column: original_mapping.generatedColumn
         
      if generated_mapping.line isnt null and generated_mapping isnt null
         renewed.addMapping
            original: line: original_mapping.originalLine, column: original_mapping.originalColumn
            generated: line: generated_mapping.line, column: generated_mapping.column
            source: original_mapping.source
            name: original_mapping.name
   renewed = JSON.parse renewed.toString()
   renewed.file = original.file
   return renewed

exports['get_original_position'] = (map, position)->
   map = @.parse map
   return map.originalPositionFor position
