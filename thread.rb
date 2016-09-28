require_relative 'extensions'
require_relative 'post'
require_relative 'atomic_write_file'

module Genkai
  class ThreadFile
    attr_reader :id, :posts, :path

    def initialize(path)
      @path = path
      begin
        data = File.read(path, encoding: 'CP932').to_utf8
        @posts = data.each_line.map { |line|
          Post.from_line(line)
        }
      rescue Errno::ENOENT
        @posts = []
      end
      @id = path.split('/')[-1].gsub('.dat', '')
    end

    def subject
      @posts[0]&.subject
    end

    def mtime
      File.mtime(@path)
    end

    def save
      # FIXME: アトミックなデータの置き換え。
      AtomicWriteFile.open(@path, 'tmp', encoding: 'CP932') do |f|
        @posts.each do |post|
          f.write post.to_line
        end
      end
    end
  end
end
