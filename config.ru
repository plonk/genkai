require 'sinatra'
require 'digest/md5'

class String
  def to_utf8
    encode('UTF-8')
  end

  def to_sjis
    encode('CP932')
  end

  def as_sjis
    dup.force_encoding('CP932')
  end
end

class Object
  def blank?
    case self
    when String then empty?
    when nil then true
    else false
    end
  end
end


module Genkai
  class BoardSettings < Hash
    def initialize(string)
      parse_settings(string)
    end

    def to_s
      each_pair { |key, value| "#{key}=#{value}\n" }.join
    end

    def parse_settings(string)
      replace string.each_line.map { |line| line.chomp.split(/=/, 2) }.to_h
    end

    # ID表示に関するポリシー。
    # :no, :force, :optional のいずれかを返す。
    def id_policy
      if self['BBS_NO_ID'] == 'checked'
        :no
      elsif self['BBS_FORCE_ID'] == 'checked'
        :force
      else
        :optional
      end
    end

    def default_name
      name = self['BBS_NONAME_NAME']
      if name.blank?
        '＜名無し＞'
      else
        name
      end
    end
  end

  class Board
    attr_reader :id, :settings

    def initialize(id)
      @id = id
      setting_path = File.join('public', id, 'SETTING.TXT')
      @settings = BoardSettings.new(File.read(setting_path, encoding: 'CP932').to_utf8)
    end

    def local_rules
      path = File.join('public', id, 'head.txt')
      File.read(path, encoding: 'CP932').to_utf8
    end

    def title
      settings['BBS_TITLE']
    end

    def create_new_post(name, mail, message, opts = {})
      date = format_date(Time.now.localtime)
      case settings.id_policy
      when :no
        add_id = false
      when :force
        raise 'remote_addr option required' unless opts[:remote_addr]
        add_id = true
      when :optional
        if mail.nil? || mail.empty?
          raise 'remote_addr option required' unless opts[:remote_addr]
          add_id = true
        else
          add_id = false
        end
      else raise 'panic'
      end

      if add_id
        id = Digest::MD5.new.base64digest(opts[:remote_addr])[0,8]
        date = "#{date} ID:#{id}"
      end
      Post.new('n/a',
               escape_field(name),
               escape_field(mail),
               date,
               escape_body(message))
    end

    class ThreadCreateError < StandardError; end

    def create_thread(title, post)
      # TODO: なんらかのロック

      unix_time = Time.now.to_i      
      dat_path = File.join('public', id, 'dat', "#{unix_time}.dat")

      if File.exist? dat_path
        raise ThreadCreateError, 'thread already exists'
      end

      File.open(dat_path, 'w') do |f|
        f.write(to_2ch_dat_line(post, title))
      end

      ThreadFile.new(dat_path)
    end

    private

    def to_2ch_dat_line(post, thread_title = '')
      [post.name, post.mail, post.date, post.body, thread_title]
        .join('<>')
        .concat("\n")
        .encode('CP932')
    end

    def format_date(time)
      time.strftime('%Y/%m/%d(%%s) %H:%M:%S') % '日月火水木金土'[time.wday]
    end

    ESCAPE_TABLE = { '<' => 'lt;', '>' => 'gt;', '&' => '&amp;' }.freeze
    def escape_field(str)
      str.gsub(/[<>&]/) { |char| ESCAPE_TABLE[char] }
    end

    def escape_body(body)
      ' ' + escape_field(body).each_line.map(&:chomp).join(' <br> ') + ' '
    end
  end

  class ThreadFile
    attr_reader :name, :id, :data

    def initialize(path)
      @path = path
      @data = File.read(path, encoding: 'CP932').to_utf8

      @name = @data.each_line.first.chomp.split('<>')[4]
      @id = path.split('/')[-1].gsub('.dat', '')
    end

    def title
      name
    end

    def mtime
      File.mtime(@path)
    end

    def number_posts
      @data.each_line.count
    end

    def posts(range)
      ary = []
      @data.each_line.with_index(1) do |line, res_no|
        next unless range.include?(res_no)

        name, mail, date, body, _title = line.chomp.split('<>', 5)
        post = Post.new(res_no.to_s, name, mail, date, body)
        ary << post
      end
      ary
    end
  end

  class Post
    class << self
      def from_s(str)
        Post.new(*str.split('<>', 5))
      end
    end

    attr_reader :no, :name, :mail, :body, :date

    def initialize(no, name, mail, date, body)
      @no = no
      @name = name
      @mail = mail
      @date = date
      @body = body
    end

    def id
      fields = @date.split
      if fields.size == 3 && fields[2] =~ %r{ID:([A-Za-z0-9+/]+)}
        $1
      else
        nil
      end
    end

    def date_without_id
      @date.sub(%r{ID:[A-Za-z0-9+/]+}, '')
    end

    def to_s
      [no, name, mail, date, body].join('<>')
    end
  end

  class Application < Sinatra::Base
    HTML_SJIS = 'text/html;charset=Shift_JIS'
    PLAIN_SJIS = 'text/plain;charset=Shift_JIS'

    set :add_charset, []

    helpers do
      def authenticate!
        auth = Rack::Auth::Basic::Request.new(request.env)
        unless auth.provided? &&
               auth.basic? &&
               auth.credentials == %w(admin 1234)
          response['WWW-Authenticate'] = 'Basic realm="Admin area"'
          halt 401, 'Not Authorized'
        end
      end

      # HTML エスケープ略記。
      def h(text)
        Rack::Utils.escape_html(text)
      end

      def sjis(text)
        text.to_sjis
      end

      def check_non_blank!(*keys)
        keys.each do |key|
          if params[key].blank?
            halt 400, "#{key} must not be blank"
          end
        end
      end
    end
    
    before do
      @site_settings = BoardSettings.new(File.read("SETTING.TXT", encoding: 'CP932').to_utf8)
    end

    get '/' do
      @itas = Dir.glob('public/*/').map { |path| path.split('/')[1] }

      @title = @site_settings['SITE_NAME']

      content_type HTML_SJIS
      sjis erb :index
    end

    # 板トップ
    get '/:ita/' do |ita|
      unless File.directory? File.join('public', ita)
        halt 404, "そんな板ないです。(#{ita})"
      end

      @threads = Dir.glob("public/#{ita}/dat/*.dat")
                    .map { |dat| ThreadFile.new(dat) }
                    .sort_by(&:mtime)
                    .reverse

      @board = Board.new(ita)
      @title = @board.settings['BBS_TITLE']

      content_type HTML_SJIS
      sjis erb :ita_top
    end

    get '/test/read.cgi/:ita/:sure/:cmd' do |ita, sure, cmd|
      halt 404, "そんな板ないです。(#{ita})" unless File.directory? board_path(ita)
      halt 404, "そんなスレないです。(#{sure})" unless File.readable? dat_path(ita, sure)

      @board = Board.new(ita)
      @thread = ThreadFile.new(dat_path(ita, sure))
      @title = @thread.title

      all_posts = @thread.posts(1..Float::INFINITY)

      require_first_post = false
      case cmd
      when /^l(\d+)$/
        @posts = all_posts.reverse[0, $1.to_i].reverse
        require_first_post = true
      when /^(\d+)-(\d+)$/
        @posts = all_posts[($1.to_i-1)..($2.to_i-1)]
        require_first_post = true
      when /^(\d+)-$/
        @posts = all_posts[($1.to_i-1)..-1]
        require_first_post = true
      when /^-(\d+)$/
        @posts = all_posts[0..($1.to_i-1)]
        require_first_post = true
      when /^(\d+)$/
        @posts = [*all_posts[$1.to_i-1]]
        if @posts.empty?
          halt 404, "レス#{$1}はまだありません。"
        end
      else
        halt 400, 'わかりません。'
      end

      if require_first_post && @posts.first.no != '1'
        # 1レス目が含まれていなかったら、先頭に追加する。
        @posts.unshift(all_posts.first)
      end

      content_type HTML_SJIS
      sjis erb :timeline
    end

    get '/test/read.cgi/:ita/:sure' do |ita, sure|
      halt 404, "そんな板ないです。(#{ita})" unless File.directory? board_path(ita)
      halt 404, "そんなスレないです。(#{sure})" unless File.readable? dat_path(ita, sure)

      @board = Board.new(ita)
      @thread = ThreadFile.new(dat_path(ita, sure))
      @posts = @thread.posts(1..Float::INFINITY)
      @title = @thread.title

      content_type HTML_SJIS
      sjis erb :timeline
    end

    get '/:ita/subject.txt' do |ita|
      halt 404, "そんな板ないです。(#{ita})" unless File.directory? board_path(ita)

      body = Dir.glob("public/#{ita}/dat/*.dat")
             .map { |path| ThreadFile.new(path) }
             .sort_by(&:mtime)
             .reverse
             .map { |t| "#{t.id}.dat<>#{t.name} (#{t.number_posts})\n" }
             .join

      content_type PLAIN_SJIS
      sjis body.encode('CP932')
    end

    get '/:ita/SETTING.TXT' do |ita|
      halt 404, "そんな板ないです。(#{ita})" unless File.directory? board_path(ita)

      content_type PLAIN_SJIS
      sjis "BBS_TITLE=集落板\n"
    end

    get '/admin/*' do
      authenticate!
      'admin'
    end

    require 'tempfile'

    def dat_path(board, thread_id)
      File.join('public', board, 'dat', "#{thread_id}.dat")
    end

    def board_path(board)
      File.join('public', board)
    end


    # パラメーター
    # bbs: 板名
    # key: スレ番号
    # FROM: 名前
    # mail: メールアドレス
    # MESSAGE: 本文
    def post_message
      halt 400, 'message body required' if params['MESSAGE'].blank?

      board = Board.new(params['bbs'])
      thread = ThreadFile.new(dat_path(params['bbs'], params['key']))
      if thread.number_posts >= 1000
        @title = "ＥＲＲＯＲ！"
        @reason = "ＥＲＲＯＲ：スレッドストップです。"
        content_type HTML_SJIS
        return sjis erb :post_error
      end

      name, mail, body = params
                         .values_at('FROM', 'mail', 'MESSAGE')
                         .map { |s| s.force_encoding('CP932').to_utf8 }
      if name.blank?
        name = board.settings.default_name
      end
      post = board.create_new_post(name, mail, body, remote_addr: env['REMOTE_ADDR'])
      line = [post.name, post.mail, post.date, post.body, ''].join('<>') + "\n"

      t = Tempfile.new(['genkai', '.dat'], 'tmp')
      t.write(thread.data.encode('CP932'))
      t.puts(line.encode('CP932'))

      if thread.number_posts == 999
        t.puts '<><><> このスレッドは１０００を超えました。 <br> もう書けないので、新しいスレッドを立ててくださいです。。。 <>'.encode('CP932')
      end
      t.close

      File.rename(t.path, dat_path(params['bbs'], params['key']))

      @head = "<meta http-equiv=\"refresh\" content=\"1; url=#{h back}\">"
      @title = '書きこみました'

      content_type HTML_SJIS
      sjis erb :posted
    end

    def convert_params_to_utf8!
      new_params = params.to_a.map { |key, value| [key.as_sjis.to_utf8, value.as_sjis.to_utf8] }.to_h
      params.replace(new_params)
    end

    def meta_refresh_tag(seconds, url)
      "<meta http-equiv=\"refresh\" content=\"#{seconds}; url=#{url}\">"
    end

    # パラメーター
    # subject: スレタイトル
    # bbs: 板名
    # FROM: 名前
    # mail: メールアドレス
    # MESSAGE: 本文
    def create_thread
      convert_params_to_utf8!
      check_non_blank!('subject', 'bbs', 'MESSAGE')

      board = Board.new params['bbs']
      name, mail, body = params.values_at('FROM', 'mail', 'MESSAGE')
      post = board.create_new_post(name, mail, body, remote_addr: env['REMOTE_ADDR'])

      begin
        thread = board.create_thread(params['subject'], post)
      rescue Board::ThreadCreateError => e
        # FIXME: ＥＲＲＯＲ！をタイトルとしたHTMLに変更する。
        halt 500, e.message
      end

      @head = meta_refresh_tag(1, "/test/read.cgi/#{board.id}/#{thread.id}")
      @title = "書き込みました"
      content_type HTML_SJIS
      sjis erb :posted
    end

    post '/test/bbs.cgi' do
      mode = params['submit'].as_sjis.to_utf8
      case mode
      when '書き込む'
        post_message
      when '新規スレッド作成'
        # halt 403, 'unimplemented'
        create_thread
      else
        halt 400, 'Unknown command'
      end
    end
  end
end

require 'rack/mount'

run Genkai::Application
