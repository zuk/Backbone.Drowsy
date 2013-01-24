fs = require 'fs'

{print} = require 'sys'
{spawn, exec} = require 'child_process'

build = (callback) ->
    exec "coffee -c -o . .",
        (err, stdout, stderr) ->
            if stdout?
                print stdout
                callback() if callback
            print stderr if stderr?

buildTests = (callback) ->
    exec "coffee -c -o test test",
        (err, stdout, stderr) ->
            if stdout?
                print stdout
                callback() if callback
            print stderr if stderr?

test = (callback) ->
    console.log "Running tests..."

    exec "mocha --colors --require should --reporter spec --slow 1000 --timeout 3000 --recursive test",
        (err, stdout, stderr) ->
            if stdout?
                print stdout
                callback() if callback 
            print stderr if stderr?


task 'build', 'Compile *.coffee to *.js', ->
    build()
task 'sbuild', 'Compile *.coffee to *.js using Sublime Text', ->
    build()

task 'test', 'Build and run tests', ->
    build ->
        buildTests ->
            test()

