require 'sinatra'

class String
  def to_utf8
    encode('UTF-8')
  end

  def to_sjis
    encode('CP932')
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
  end

  class ThreadFile
    attr_reader :name, :id

    def initialize(path)
      @path = path
      @data = File.read(path, encoding: 'CP932').to_utf8

      @name = @data.each_line.first.chomp.split('<>')[4]
      @id = path.split('/')[-1].gsub('.dat', '')
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
      @no = no.to_i
      @name = name
      @mail = mail
      @date = date
      @body = body
    end

    # 削除された時のフィールドの値は、掲示板の設定によるなぁ。
    # def deleted?
    #   @date == '＜削除＞'
    # end

    def to_s
      [no, name, mail, date, body].join('<>')
    end
  end

  class Application < Sinatra::Base
    SJIS_HTML = 'text/html;charset=Shift_JIS'
    SJIS_PLAIN = 'text/plain;charset=Shift_JIS'

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
    end

    get '/' do
      @itas = Dir.glob('public/*/').map { |path| path.split('/')[1] }

      content_type SJIS_HTML
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

      content_type SJIS_HTML
      sjis erb :ita_top
    end

    get '/test/read.cgi/:ita/:sure/:cmd' do
      "#{params['ita']}, #{params['sure']}, #{params['cmd']}"
    end

    get '/test/read.cgi/:ita/:sure' do |ita, sure|
      halt 404, "そんな板ないです。(#{ita})" unless File.directory? board_path(ita)
      halt 404, "そんなスレないです。(#{sure})" unless File.readable? dat_path(ita, sure)

      @board = Board.new(ita)
      @thread = ThreadFile.new(dat_path(ita, sure))

      content_type SJIS_HTML
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

      content_type SJIS_PLAIN
      sjis body.encode('CP932')
    end

    get '/:ita/SETTING.TXT' do |ita|
      halt 404, "そんな板ないです。(#{ita})" unless File.directory? board_path(ita)

      content_type SJIS_PLAIN
      sjis "BBS_TITLE=集落板\n"
    end

    get '/admin/*' do
      authenticate!
      'admin'
    end

    require 'tempfile'

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

    def create_new_post(name, mail, message)
      date = format_date(Time.now.localtime)
      Post.new('n/a',
               escape_field(name),
               escape_field(mail),
               date,
               escape_body(message))
    end

    def dat_path(board, thread_id)
      File.join('public', board, 'dat', "#{thread_id}.dat")
    end

    def board_path(board)
      File.join('public', board)
    end

    def blank?(obj)
      case obj
      when String then obj.empty?
      when nil then true
      else false
      end
    end

    # bbs: 板名
    # key: スレ番号
    # FROM: 名前
    # mail: メールアドレス
    # MESSAGE: 本文
    post '/test/bbs.cgi' do
      sure_path = dat_path(params['bbs'], params['key'])

      halt 400, 'name required' if blank? params['FROM']
      halt 400, 'message body required' if blank? params['MESSAGE']

      t = Tempfile.new(['genkai', '.dat'], 'tmp')
      t.write(File.read(sure_path))

      name, mail, body = params
                         .values_at('FROM', 'mail', 'MESSAGE')
                         .map { |s| s.force_encoding('CP932') }
      post = create_new_post(name, mail, body)
      line = [post.name, post.mail, post.date, post.body, ''].join('<>') + "\n"

      t.puts(line.encode('CP932'))

      t.close

      File.rename(t.path, sure_path)

      @head = "<meta http-equiv=\"refresh\" content=\"1; url=#{h back}\">"
      @title = '書きこみました'

      content_type SJIS_HTML
      sjis erb :posted
    end
  end
end

require 'rack/mount'

run Genkai::Application
