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

    def size
      if @posts
        @posts.size
      else
        begin
          File.open(path, encoding: 'CP932') do |f|
            f.each_line.count
          end
        rescue Errno::ENOENT
          posts.size
        end
      end
    end

    def bytesize
      if @bytesize
        @bytesize
      else
        posts
        fail 'logic error' unless @bytesize
        @bytesize
      end
    end

    def posts
      unless @posts
        @posts = []
        begin
          File.open(path, encoding: 'CP932') do |f|
            f.each_line.with_index(1) do |line, lineno|
              @posts << Post.from_line(line.to_utf8, lineno)
            end
            @bytesize = f.pos
          end
        rescue Errno::ENOENT
        end
      end

      @posts
    end

    def subject
      res = nil
      begin
        File.open(path, encoding: 'CP932') do |f|
          line = f.gets
          if line
            res = Post.from_line(line.to_utf8).subject
          end
        end
      rescue
      end
      res
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
