fs = require "fs"

test = (!!)->
   exist = fs.exists "../readme.md", !!
   return exist

exist = fs.exists "../readme.md", !!
if exist
   readme = fs.readFile "../readme.md", !!
   console.log readme
   
readme2 = fs.readFile "../readme.md", !!

