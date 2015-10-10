fs       = require 'fs'
path     = require 'path'
os       = require 'os'
GitHub   = require 'github-releases'

{ downloadAndUnzip
  copyDirectory
  dirExistsSync } = require '../utils'

module.exports = (grunt) ->
  # Flags to keep track of downloads
  downloaded =
    darwin64: false
    linux32: false
    linux64: false
    win32: false

  getApmPath = (platform) ->
    apmPath = path.join 'apm', 'node_modules', 'atom-package-manager', 'bin', 'apm'
    apmPath = 'apm' unless grunt.file.isFile apmPath

    if platform is 'win32' then "#{apmPath}.cmd" else apmPath

  getAtomShellVersion = (directory) ->
    versionPath = path.join directory, 'version'
    if grunt.file.isFile versionPath
      grunt.file.read(versionPath).trim()
    else
      null

  rebuildNativeModules = (dist, apm, previousVersion, currentVersion, needToRebuild, callback, appDir) ->
    if currentVersion isnt previousVersion and needToRebuild
      grunt.verbose.writeln "Rebuilding native modules for new electron version #{currentVersion}."
      apm = getApmPath(dist)

      # When we spawn apm, we still want to use the global environment variables
      options = env: {}
      options.env[key] = value for key, value of process.env
      options.env.ATOM_NODE_VERSION = currentVersion.substr(1)

      # If the appDir has been set, then that is where we want to perform the rebuild.
      # it defaults to the current directory
      options.cwd = appDir if appDir
      spawn {cmd: apm, args: ['rebuild'], opts: options}, callback
    else
      callback()

  # Download the Electron binary for a platform
  [
    ['darwin', 'x64', 'darwin64', './electron/darwin64']
    ['linux', 'ia32', 'linux32', './electron/linux32/opt/' + grunt.package.name]
    ['linux', 'x64', 'linux64', './electron/linux64/opt/' + grunt.package.name]
    ['win32', 'ia32', 'win32', './electron/win32']
    ['win32', 'x64', 'win64', './electron/win64']
  ].forEach (release) ->
    [platform, arch, dist, outputDir] = release

    grunt.registerTask 'wcjs:nwjs:' + dist, 'Download nwjs',  ->
      done = @async()

      @requiresConfig "wcjs.platform.runtime", 'wcjs.platform.version' 

      { version, runtime } = grunt.config('wcjs').platform

      if runtime isnt 'nw'
        done()
        return

      downloadDir = path.join os.tmpdir(), 'grunt-nw'
      symbols = false
      rebuild = false
      apm = getApmPath(dist)
      distVersion = "v#{version}"
      versionDownloadDir = path.join(downloadDir, distVersion, dist)
      appDir = process.cwd()

      # Do nothing if the desired version of electron is already installed.
      currentAtomShellVersion = getAtomShellVersion(outputDir)
      return done() if currentAtomShellVersion is distVersion

      # Install a cached download of electron if one is available.
      if getAtomShellVersion(versionDownloadDir)?
        grunt.verbose.writeln("Installing cached electron #{distVersion}.")
        copyDirectory(versionDownloadDir, outputDir)
        rebuildNativeModules dist, apm, currentAtomShellVersion, distVersion, rebuild, done, appDir
        return

      # Request the assets.
      github = new GitHub({repo: 'atom/electron'})
      github.getReleases tag_name: distVersion, (error, releases) ->
        unless releases?.length > 0
          grunt.log.error "Cannot find electron #{distVersion} from GitHub", error
          return done false


        atomShellAssets = releases[0].assets.filter ({name}) -> name.indexOf('atom-shell-') is 0
        if atomShellAssets.length > 0
          projectName = 'atom-shell'
        else
          projectName = 'electron'

        # Which file to download
        filename =
          if symbols
            "#{projectName}-#{distVersion}-#{platform}-#{arch}-symbols.zip"
          else
            "#{projectName}-#{distVersion}-#{platform}-#{arch}.zip"

        # Find the asset of current platform.
        for asset in releases[0].assets when asset.name is filename
          github.downloadAsset asset, (error, inputStream) ->
            if error?
              grunt.log.error "Cannot download electron #{distVersion}", error
              return done false

            # Save file to cache.
            grunt.verbose.writeln "Downloading electron #{distVersion}."
            downloadAndUnzip inputStream, path.join(versionDownloadDir, "#{projectName}.zip"), (error) ->
              if error?
                grunt.log.error "Failed to download electron #{distVersion}", error
                return done false

              grunt.verbose.writeln "Installing electron #{distVersion}."
              copyDirectory(versionDownloadDir, outputDir)

              rebuildNativeModules dist, apm, currentAtomShellVersion, distVersion, rebuild, done, appDir

              if dist is 'darwin64'
                fs.renameSync outputDir + '/Electron.app', outputDir + '/' + grunt.package.productName + '.app'

          return

        grunt.log.error "Cannot find #{filename} in electron #{distVersion} release"
        done false

  # Download the Electron binaries for all platforms
  grunt.registerTask 'wcjs:nwjs', [
    'wcjs:nwjs:darwin64'
    'wcjs:nwjs:linux32'
    'wcjs:nwjs:linux64'
    'wcjs:nwjs:win32'
  ]

  grunt.registerTask 'wcjs', [
    'wcjs:nwjs'
    'wcjs:electron'
    'wcjs:vlc'
    'wcjs:webchimera'
  ]