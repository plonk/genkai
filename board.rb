require_relative 'settings'
require_relative 'thread'

module Genkai
  class Board
    attr_reader :settings

    class NotFoundError < StandardError; end

    def initialize(path)
      unless File.directory?(path)
        raise NotFoundError, "directory #{path} does not exist"
      end
      @path = path
      setting_path = File.join(path, 'SETTING.TXT')
      unless File.exist?(setting_path)
        raise NotFoundError, "#{setting_path} does not exist"
      end
      @settings = SettingsFile.new(setting_path)
    end

    def threads
      pat = File.join(@path, 'dat', '*.dat')
      Dir.glob(pat).map { |path| ThreadFile.new(path) }
    end

    def id
      File.split(@path)[-1]
    end

    def local_rules
      path = File.join(@path, 'head.txt')
      File.read(path, encoding: 'CP932').to_utf8
    rescue Errno::ENOENT
      ''
    end

    def local_rules=(text)
      AtomicWriteFile.new(@path / 'head.txt', encoding: 'CP932') do |f|
        f.write(text)
      end
    end

    def thread_stop_message
      File.read(@path / '1000.txt', encoding: 'CP932').to_utf8
    rescue Errno::ENOENT
      ''
    end

    def thread_stop_message=(text)
      AtomicWriteFile.new(@path / '1000.txt', encoding: 'CP932') do |f|
        f.write(text)
      end
    end

    def title
      settings['BBS_TITLE']
    end

    def to_2ch_dat_line(post, thread_title = '')
      [post.name, post.mail, post.date, post.body, thread_title]
        .join('<>')
        .concat("\n")
        .to_sjis
    end

    class ThreadCreateError < StandardError; end

    def create_thread
      unix_time = Time.now.to_i
      dat_path = File.join('public', id, 'dat', "#{unix_time}.dat")

      if File.exist? dat_path
        raise ThreadCreateError, 'thread already exists'
      end
      ThreadFile.new(dat_path)
    end

    # ID表示に関するポリシー。
    # :no, :force, :optional のいずれかを返す。
    def id_policy
      if settings['BBS_NO_ID'] == 'checked'
        :no
      elsif settings['BBS_FORCE_ID'] == 'checked'
        :force
      else
        :optional
      end
    end

    def default_name
      name = settings['BBS_NONAME_NAME']
      if name.blank?
        '＜名無し＞'
      else
        name
      end
    end
  end
end
