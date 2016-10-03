require_relative 'extensions'
require_relative 'atomic_write_file'

module Genkai
  class SettingsFile
    attr_reader :dictionary

    def initialize(path)
      @path = path
      @dictionary = parse_settings(File.read(@path, encoding: 'CP932').to_utf8)
    rescue Errno::ENOENT
      @dictionary = {}
    end

    def save
      AtomicWriteFile.open(@path, 'tmp', encoding: 'CP932') do |f|
        f.write(hash_to_string(@dictionary))
      end
    end

    def [](key)
      @dictionary[key.to_s]
    end

    def []=(key, value)
      @dictionary[key.to_s] = value
    end

    def delete(key)
      @dictionary.delete(key.to_s)
    end

    private

    def hash_to_string(dict)
      dict.each_pair.map { |key, value| "#{key}=#{value}\n" }.join
    end

    def parse_settings(string)
      string.each_line.map { |line| line.chomp.split(/=/, 2) }.to_h
    end
  end
end
