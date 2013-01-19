fs = require 'fs'

{print} = require 'sys'
{spawn} = require 'child_process'

build = (callback) ->
  coffee = spawn 'coffee', ['-c', '-o', '.', '.']
  
  coffee.stderr.on 'data', (data) ->
    process.stderr.write data.toString()
  
  coffee.on 'exit', (code) ->
    callback?() if code is 0

  coffee.on 'exit', (code) ->
    callback?() if code is 0

task 'build', 'Compile *.coffee to *.js', ->
  build()
task 'sbuild', 'Compile *.coffee to *.js using Sublime Text', ->
  build()

