# frozen_string_literal: true
require_relative 'settings'
require_relative 'thread_file'
require_relative 'string_helpers'
require_relative 'extensions'

require 'fileutils'

module Genkai
  # 板を表わすクラス。
  class Board
    class << self
      def create(directory_path, title)
        Dir.mkdir(directory_path)
        Dir.mkdir(directory_path / 'dat')
        File.open(directory_path / 'SETTING.TXT', 'w', encoding: 'CP932') do |f|
          f.write("BBS_TITLE=#{title}\n")
        end
        Board.new(directory_path)
      end

      def remove(directory_path)
        FileUtils.rm_rf directory_path
      end

      # 1〜30文字の英小文字アラビア数字からなる。
      def valid_id?(string)
        string != 'admin' && string != 'test' &&
        (string =~ /\A [a-z0-9]{1,30} \z/x).true?
      end
    end

    include StringHelpers

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

    def get_all_threads
      pat = File.join(@path, 'dat', '*.dat')
      Dir.glob(pat).map { |path| ThreadFile.new(path) }
    end

    def dat_path(id)
      File.join(@path, 'dat', "#{id}.dat")
    end

    def find_thread(id)
      path = dat_path(id)

      # XXX: レースがあるので正しくないが、ThreadFile.new がスレッドが
      # 存在しなくてもエラーにしないのでこうしている。
      if File.exist?(path)
        ThreadFile.new(path)
      else
        nil
      end
    end

    def delete_thread(id)
      File.unlink(dat_path(id))
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
      AtomicWriteFile.open(@path / 'head.txt', 'tmp', encoding: 'CP932') do |f|
        f.write(text)
      end
    end

    def thread_stop_message
      unescape_1001 File.read(@path / '1000.txt', encoding: 'CP932').to_utf8
    rescue Errno::ENOENT
      ''
    end

    def thread_stop_message=(text)
      escaped = escape_1001(text)
      AtomicWriteFile.open(@path / '1000.txt', 'tmp', encoding: 'CP932') do |f|
        f.write(escaped)
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
      path = dat_path(unix_time)

      raise ThreadCreateError, 'thread already exists' if File.exist? path
      ThreadFile.new(path)
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

    ID_POLICIES = [:no, :force, :optional].freeze
    def id_policy=(sym)
      raise ArgumentError, 'invalid policy' unless ID_POLICIES.include?(sym)

      case sym
      when :no
        settings['BBS_NO_ID'] = 'checked'
        settings.delete('BBS_FORCE_ID')
      when :force
        settings.delete('BBS_NO_ID')
        settings['BBS_FORCE_ID'] = 'checked'
      when :optional
        settings.delete('BBS_NO_ID')
        settings.delete('BBS_FORCE_ID')
      end
    end

    def emoji_only?
      settings['EMOJI_ONLY_MODE'] == 'true'
    end

    def emoji_only=(value)
      if !!value
        settings['EMOJI_ONLY_MODE'] = 'true'
      else
        settings['EMOJI_ONLY_MODE'] = 'false'
      end
    end

    def reject_same_content?
      settings['REJECT_SAME_CONTENT'] == 'true'
    end

    def reject_same_content=(value)
      if !!value
        settings['REJECT_SAME_CONTENT'] = 'true'
      else
        settings['REJECT_SAME_CONTENT'] = 'false'
      end
    end

    def forbid_nonviewer?
      settings['FORBID_NONVIEWER'] == 'true'
    end

    def forbid_nonviewer=(value)
      if !!value
        settings['FORBID_NONVIEWER'] = 'true'
      else
        settings['FORBID_NONVIEWER'] = 'false'
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

    DEFAULT_DELETE_STRING = '＜削除＞'
    def grave_stone
      Post.new(DEFAULT_DELETE_STRING,
               DEFAULT_DELETE_STRING,
               DEFAULT_DELETE_STRING,
               DEFAULT_DELETE_STRING,
               '')
    end
  end
end
