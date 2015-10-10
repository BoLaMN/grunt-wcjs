wrench   = require 'wrench'
Progress = require 'progress'
fs       = require 'fs'
path     = require 'path'
tar      = require 'tar'
zlib     = require "zlib"

dirExistsSync = (d) ->
  try
    fs.statSync d
    return true
  catch er
    return false
  return

spawn = (options, callback) ->
  childProcess = require 'child_process'
  
  stdout = []
  stderr = []
  
  error = null
  
  proc = childProcess.spawn options.cmd, options.args, options.opts
  
  proc.stdout.on 'data', (data) -> stdout.push data.toString()
  proc.stderr.on 'data', (data) -> stderr.push data.toString()
  
  proc.on 'error', (processError) -> error = processError
  
  proc.on 'exit', (code, signal) ->
    error ?= new Error(signal) if code != 0
    results = stderr: stderr.join(''), stdout: stdout.join(''), code: code
    console.error results.stderr if code != 0
    callback error, results, code

copyDirectory = (fromPath, toPath, force = false) ->
  wrench.mkdirSyncRecursive toPath 

  wrench.copyDirSyncRecursive fromPath, toPath,
    forceDelete: force
    excludeHiddenUnix: false
    inflateSymlinks: false

tarGzzStream = (directory) ->
  stream1 = zlib.createGunzip()
  
  stream2 = tar.Extract path: directory

  stream1.pipe stream2
  stream1

extractTar = (tarStream, tarPath, callback) ->
  directoryPath = path.dirname tarPath

  newStream = tarGzzStream directoryPath

  newStream.on('error', callback).on 'close', ->
    callback null

  tarStream.pipe newStream

  return

unzipFile = (zipPath, callback) ->
  directoryPath = path.dirname zipPath

  if process.platform is 'darwin'
    # The zip archive of darwin build contains symbol links, only the "unzip"
    # command can handle it correctly.
    spawn {cmd: 'unzip', args: [zipPath, '-d', directoryPath]}, (error) ->
      fs.unlinkSync zipPath
      callback error
  else
    DecompressZip = require 'decompress-zip'
    
    unzipper = new DecompressZip zipPath
    unzipper.on 'error', callback
    
    unzipper.on 'extract', ->
      fs.closeSync unzipper.fd
      fs.unlinkSync zipPath
      callback null

    unzipper.extract path: directoryPath

downloadAndUnzip = (inputStream, zipFilePath, callback) ->
  wrench.mkdirSyncRecursive path.dirname(zipFilePath)

  unless process.platform is 'win32'
    len = parseInt(inputStream.headers['content-length'], 10)
    progress = new Progress('downloading and extracting [:bar] :percent :etas', {complete: '=', incomplete: ' ', width: 20, total: len})

  inputStream.on 'error', callback
    
  extname = path.extname zipFilePath

  if extname in [ '.gz', '.tar', '.tar.gz' ]
    extractTar inputStream, zipFilePath, callback
  else
    outputStream = fs.createWriteStream(zipFilePath)
    inputStream.pipe outputStream

    outputStream.on 'error', callback
    outputStream.on 'close', unzipFile.bind this, zipFilePath, callback
  
  inputStream.on 'data', (chunk) ->
    return if process.platform is 'win32'

    process.stdout.clearLine?()
    process.stdout.cursorTo?(0)
    progress.tick(chunk.length)

module.exports = 
  downloadAndUnzip: downloadAndUnzip
  unzipFile: unzipFile
  copyDirectory: copyDirectory
  spawn: spawn
  dirExistsSync: dirExistsSync