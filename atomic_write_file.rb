require 'tempfile'

class AtomicWriteFile
  class << self
    def permission(path)
      File.stat(path).mode & 0o777
    rescue
      0o666 & ~File.umask
    end

    def open(path, dir, opts = {}, &block)
      raise 'block required' unless block

      perm = AtomicWriteFile.permission(path)
      temp = Tempfile.new('atomic-write-file', dir, opts)
      yield(temp)
      temp.close
      File.chmod(perm, temp.path)
      File.rename(temp.path, path)
    end
  end
end
