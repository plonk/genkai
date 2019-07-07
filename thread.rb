# frozen_string_literal: true
require_relative 'extensions'
require_relative 'post'
require_relative 'atomic_write_file'

module Genkai
  # DATファイルを操作するクラス。
  class ThreadFile
    attr_reader :id, :path

    def initialize(path)
      @path = path
      @id = path.split('/')[-1].gsub('.dat', '')
    end

    def posts
      unless @posts
        @posts = []
        begin
          File.open(path, encoding: 'CP932') do |f|
            while line = f.gets
              @posts << Post.from_line(line.to_utf8)
            end
          end
        rescue Errno::ENOENT
        end
      end

      @posts
    end

    def subject
      posts[0]&.subject
    end

    def mtime
      File.mtime(@path)
    end

    def created_at
      Time.at(id.to_i).localtime
    end

    def save
      AtomicWriteFile.open(@path, 'tmp', encoding: 'CP932') do |f|
        posts.each do |post|
          f.write post.to_line
        end
      end
    end
  end
end
