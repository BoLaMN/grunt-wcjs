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

  # Download the WebChimera binary for a platform
  [
    ['osx', 'x64', 'osx', './wcjs']
    ['linux', 'x64', 'linux', './wcjs']
    ['win', 'ia32', 'win', './wcjs']
  ].forEach (release) ->
    [platformType, arch, dist, outputDir] = release

    grunt.registerTask 'wcjs:vlc:' + dist, 'prebuilt vlc',  ->
      @requiresConfig "wcjs.version", "wcjs.platform.runtime", 'wcjs.platform.version' 
      
      done = @async()

      { runtime, version } = grunt.config('wcjs').platform
      runtimeVersion = version

      { version } = grunt.config 'wcjs'
      
      # Request the assets.
      github = new GitHub repo: 'Ivshti/vlc-prebuilt'
      
      github.getReleases {}, (error, releases) ->
        unless releases?.length > 0
          grunt.log.error "Cannot find prebuilt vlc from GitHub", error
          return done false

        # Find the asset of current platform.
        for asset in releases[0].assets 
          re = new RegExp platformType, 'gi'

          if asset.name.match re
            distVersion = asset.name.split('-')[1]

            outputDir = path.join outputDir, dist
            cacheDir = path.join os.tmpdir(), 'grunt-wcjs', 'vlc'

            versionCacheDir = path.join(cacheDir, distVersion, runtime, dist)

            github.downloadAsset asset, (error, inputStream) ->
              if error?
                grunt.log.error "Cannot download vlc #{distVersion}", error
                return done false

              # Save file to cache.
              grunt.verbose.writeln "Downloading vlc #{distVersion}."
              
              downloadAndUnzip inputStream, path.join(versionCacheDir, asset.name), (error) ->
                if error?
                  grunt.log.error "Failed to download vlc #{distVersion}", error
                  return done false

                grunt.verbose.writeln "Installing vlc #{distVersion}."
                copyDirectory(versionCacheDir, outputDir, true)
                done()
            return

        grunt.log.error "Cannot find vlc #{distVersion} release"
        done false

  # Download the WebChimera binaries for all platforms
  grunt.registerTask 'wcjs:vlc', [
    'wcjs:vlc:osx'
    'wcjs:vlc:linux'
    'wcjs:vlc:win'
  ]
