# frozen_string_literal: true
require_relative 'extensions'
require_relative 'post'
require_relative 'atomic_write_file'

module Genkai
  # DATファイルを操作するクラス。
  class ThreadFile
    attr_reader :id, :posts, :path

    def initialize(path)
      @path = path
      begin
        data = File.read(path, encoding: 'CP932').to_utf8
        @posts = data.each_line.map do |line|
          Post.from_line(line)
        end
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

    def created_at
      Time.at(id.to_i).localtime
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
