{BufferedProcess, CompositeDisposable} = require 'atom'
fs = require('fs')
path = require('path')

module.exports =

  config:
    environment:
      type: 'object'
      title: 'Environment'
      order: 1
      properties:
        amentExecutablePath:
          type: 'string'
          title: 'ament Executable path'
          default: 'ament'
    workspace:
      type: 'object'
      title: 'Workspace'
      order: 2
      properties:
        sourceSpace:
          type: 'string'
          title: 'Source space'
          default: 'src'
        isolated:
          type: 'boolean'
          title: 'Isolated layout'
          default: false
        symlinkInstall:
          type: 'boolean'
          title: 'Symlinked installation'
          default: false
    build:
      type: 'object'
      title: '`build` command'
      order: 3
      properties:
        buildTests:
          type: 'boolean'
          title: 'Build tests'
          default: false
        cmakeArgs:
          type: 'string'
          title: 'CMake arguments'
          default: ''
    test:
      type: 'object'
      title: '`test` command'
      order: 4
      properties:
        skipBuild:
          type: 'boolean'
          title: 'Skip build'
          default: false
        skipInstall:
          type: 'boolean'
          title: 'Skip install'
          default: false

  activate: ->
    require('atom-package-deps').install()

    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.config.observe 'build-ament.environment.amentExecutablePath',
      (amentExecutablePath) =>
        @amentExecutablePath = amentExecutablePath

    @subscriptions.add atom.config.observe 'build-ament.workspace.sourceSpace',
      (sourceSpace) =>
        @sourceSpace = sourceSpace
    @subscriptions.add atom.config.observe 'build-ament.workspace.isolated',
      (isolated) =>
        @isolated = isolated
    @subscriptions.add atom.config.observe 'build-ament.workspace.symlinkInstall',
      (symlinkInstall) =>
        @symlinkInstall = symlinkInstall

    @subscriptions.add atom.config.observe 'build-ament.build.buildTests',
      (buildTests) =>
        @buildTests = buildTests
    @subscriptions.add atom.config.observe 'build-ament.build.cmakeArgs',
      (cmakeArgs) =>
        @cmakeArgs = cmakeArgs

    @subscriptions.add atom.config.observe 'build-ament.test.skipBuild',
      (skipBuild) =>
        @skipBuild = skipBuild
    @subscriptions.add atom.config.observe 'build-ament.test.skipInstall',
      (skipInstall) =>
        @skipInstall = skipInstall

  deactivate: ->
    @subscriptions.dispose()

  providingFunction: ->
    return {
      niceName: 'ament'

      isEligable: (cwd) =>
        if path.basename(cwd) is @sourceSpace
          return not fs.existsSync(path.join(cwd, 'package.xml'))
        if fs.existsSync(path.join(cwd, @sourceSpace))
          return not fs.existsSync(path.join(cwd, @sourceSpace, 'package.xml'))
        return false

      settings: (cwd) =>
        promise = new Promise (resolve, reject) =>
          if path.basename(cwd) is @sourceSpace
            cwd = path.dirname(cwd)

          promise = new Promise (resolve2, reject2) =>
            params = ['list_packages', '--names-only', path.join(cwd, @sourceSpace)]
            @exec(@amentExecutablePath, params)
              .then (output) ->
                package_names = output.split /\s+/
                resolve2(package_names)
          promise.then (package_names) =>
            targets = []

            errorMatch = [
              # compiler error
              '(?<file>/[^:\\n]+):(?<line>\\d+):(?<col>\\d+): error:'
              # compiler warning
              # TODO currently disabled since it fails the build
              # '(?<file>/[^:\\n]+):(?<line>\\d+):(?<col>\\d+): warning:'

              # make error
              '^make(\\[\\d+\\])?: \\*\\*\\* \\[.+\\] Error \\d+'

              # CMake parser error
              'CMake Error: Error in cmake code at\\n(?<file>/[^:\\n]+):(?<line>\\d+):'
              # CMake error, the file is relative to the package and
              # therefore can't be identified from the information available
              'CMake Error at ([^:\\n]+):(?<line>\\d+)'
              # CMake warning, the file is relative to the package and
              # therefore can't be identified from the information available
              'CMake Warning( at ([^:\\n]+):(?<line>\\d+))?'
              # CMake configure incomplete
              '-- Configuring incomplete, errors occurred!'
            ]

            # build
            build_args = []
            if @buildTests
              build_args.push '--build-tests'
            if @isolated
              build_args.push '--isolated'
            if @symlinkInstall
              build_args.push '--symlink-install'
            if @cmakeArgs.length > 0
              build_args.push '--cmake-args'
              build_args.push @cmakeArgs

            targets.push {
              name: 'ament build (all)'
              exec: @amentExecutablePath
              args: ['build', path.join(cwd, @sourceSpace)].concat build_args
              cwd: cwd
              errorMatch: errorMatch
            }
            targets.push.apply targets, (
              {
                name: 'ament build --only ' + package_name
                exec: @amentExecutablePath
                args: ['build', path.join(cwd, @sourceSpace), '--only', package_name].concat build_args
                cwd: cwd
                errorMatch: errorMatch
              } for package_name in package_names
            )

            # list packages
            targets.push {
              name: 'ament list_packages (paths)'
              exec: @amentExecutablePath
              args: ['list_packages', path.join(cwd, @sourceSpace)]
              cwd: cwd
            }
            targets.push {
              name: 'ament list_packages (names)'
              exec: @amentExecutablePath
              args: ['list_packages', '--names-only', path.join(cwd, @sourceSpace)]
              cwd: cwd
            }
            targets.push {
              name: 'ament list_packages (names in topological order)'
              exec: @amentExecutablePath
              args: ['list_packages', '--names-only', '--topological-order', path.join(cwd, @sourceSpace)]
              cwd: cwd
            }

            # test
            test_args = []
            test_args.push '--skip-build'
            test_args.push '--skip-install'
            if @isolated
              test_args.push '--isolated'

            targets.push {
              name: 'ament test (all)'
              exec: @amentExecutablePath
              args: ['test', path.join(cwd, @sourceSpace)].concat test_args
              cwd: cwd
            }
            targets.push.apply targets, (
              {
                name: 'ament test --only ' + package_name
                exec: @amentExecutablePath
                args: ['test', path.join(cwd, @sourceSpace), '--only', package_name].concat test_args
                cwd: cwd
              } for package_name in package_names
            )

            # test results
            targets.push {
              name: 'ament test_results'
              exec: @amentExecutablePath
              args: ['test_results', cwd]
              cwd: cwd
            }
            targets.push {
              name: 'ament test_results --verbose'
              exec: @amentExecutablePath
              args: ['test_results', '--verbose', cwd]
              cwd: cwd
            }

            resolve(targets)

        return promise
    }

  exec: (command, args = [], options = {}) ->
    throw new Error 'Nothing to execute.' unless arguments.length
    options.stream ?= 'stdout'
    options.throwOnStdErr ?= true
    return new Promise (resolve, reject) ->
      data = stdout: [], stderr: []
      stdout = (output) -> data.stdout.push(output.toString())
      stderr = (output) -> data.stderr.push(output.toString())
      exit = ->
        if options.stream is 'stdout'
          if data.stderr.length and options.throwOnStdErr
            reject(new Error(data.stderr.join('')))
          else
            resolve(data.stdout.join(''))
        else if options.stream is 'both'
          resolve(stdout: data.stdout.join(''), stderr: data.stderr.join(''))
        else
          resolve(data.stderr.join(''))
      spawnedProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})
      spawnedProcess.onWillThrowError(({error, handle}) ->
        return reject(error) if error and error.code is 'ENOENT'
        handle()
        if error.code is 'EACCES'
          error = new Error(
            "Failed to spawn command `#{command}`. "
            "Make sure it's a file, not a directory and it's executable.")
          error.name = 'BufferedProcessError'
        reject(error)
      )
      if options.stdin
        spawnedProcess.process.stdin.write(options.stdin.toString())
        spawnedProcess.process.stdin.end()  # We have to end it or the programs will keep waiting foreve
