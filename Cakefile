fs = require 'fs'

{print} = require 'sys'
{spawn, exec} = require 'child_process'

build = (callback) ->
  coffee = spawn 'coffee', ['-c', '-o', '.', '.']
  
  coffee.stderr.on 'data', (data) ->
    process.stderr.write data.toString()
  
  coffee.on 'exit', (code) ->
    callback?() if code is 0

  coffee.on 'exit', (code) ->
    callback?() if code is 0

buildTests = (callback) ->
    coffee = spawn 'coffee', ['-c', '-o', 'test', 'test']
  
    coffee.stderr.on 'data', (data) ->
        process.stderr.write data.toString()
  
    coffee.on 'exit', (code) ->
        callback?() if code is 0

    coffee.on 'exit', (code) ->
        callback?() if code is 0

test = (callback) ->
    console.log "Running tests..."

    exec "mocha --colors --require should --reporter spec --slow 1000 --timeout 3000 --recursive test",
      (err, stdout, stderr) ->
        print stdout if stdout?
        print stderr if stderr?


task 'build', 'Compile *.coffee to *.js', ->
    build()
task 'sbuild', 'Compile *.coffee to *.js using Sublime Text', ->
    build()

task 'test', 'Build and run tests', ->
    build()
    buildTests()
    test()

