require 'tempfile'

class AtomicWriteFile
  class << self
    def permission(path)
      File.stat(path).mode & 0o777
    rescue
      0o666 & ~File.umask
    end

    def open(path, dir = '/tmp', opts = {}, &block)
      raise 'block required' unless block
      raise TypeError, 'path must be a String' unless path.is_a? String
      raise TypeError, 'dir must be a String' unless dir.is_a? String
      raise TypeError, 'opts must be a Hash' unless opts.is_a? Hash

      perm = AtomicWriteFile.permission(path)
      temp = Tempfile.new('atomic-write-file', dir, opts)
      yield(temp)
      temp.close
      File.chmod(perm, temp.path)
      File.rename(temp.path, path)
    end
  end
end
