require_relative 'settings'
require_relative 'board'
require_relative 'thread'
require_relative 'post_builder'
require_relative 'numbered_element'

require 'ostruct'

module Genkai
  class Application < Sinatra::Base
    HTML_SJIS = 'text/html;charset=Shift_JIS'
    PLAIN_SJIS = 'text/plain;charset=Shift_JIS'

    # 静的ファイルを提供するときにcharsetを指定しない。SJISのテキスト
    # ファイルがUTF8指定になることを防ぐ。
    set :add_charset, []

    # delete や patch などのメソッドが使えるようにする
    use Rack::MethodOverride

    configure do
      mime_type :dat, PLAIN_SJIS
    end

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
      @site_settings = SettingsFile.new('SETTING.TXT')
      @client = OpenStruct.new
      @client.remote_addr = env['REMOTE_ADDR']
    end

    get '/' do
      @boards = Dir.glob('public/*/SETTING.TXT').map { |path|
        Board.new(File.dirname(path))
      }
      @title = @site_settings['SITE_NAME']

      content_type HTML_SJIS
      sjis erb :index
    end

    get '/:ita' do |ita|
      redirect to("/#{ita}/")
    end

    # 板トップ
    get '/:ita/' do |ita|
      @board = Board.new(File.join('public', ita))
      @threads = @board.threads
      @title = @board.title

      content_type HTML_SJIS
      sjis erb :ita_top
    end

    get '/test/read.cgi/:ita/:sure/:cmd' do |ita, sure, cmd|

      @board = Board.new(File.join('public', ita))
      @thread = @board.threads.find { |th| th.id == sure }
      halt 404, "そんなスレないです。(#{sure})" unless @thread
      @title = @thread.subject

      all_posts = NumberedElement.to_numbered_elements @thread.posts

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

      # FIXME
      if require_first_post && @posts.first.number != 1
        # 1レス目が含まれていなかったら、先頭に追加する。
        @posts.unshift(all_posts.first)
      end

      content_type HTML_SJIS
      sjis erb :timeline
    end

    get '/test/read.cgi/:ita/:sure' do |ita, sure|
      @board = Board.new(File.join('public', ita))
      @thread = @board.threads.find { |th| th.id == sure }
      halt 404, "そんなスレないです。(#{sure})" unless @thread
      @posts = NumberedElement.to_numbered_elements @thread.posts
      @title = @thread.subject

      content_type HTML_SJIS
      sjis erb :timeline
    end

    get '/:ita/subject.txt' do |ita|
      board = Board.new(File.join('public', ita))

      body = board.threads.sort_by(&:mtime).reverse.map { |t| "#{t.id}.dat<>#{t.subject} (#{t.posts.size})\n" }.join

      content_type PLAIN_SJIS
      sjis body.to_sjis
    end

    # get '/:ita/SETTING.TXT' do |ita|
    #   halt 404, "そんな板ないです。(#{ita})" unless File.directory? board_path(ita)

    #   content_type PLAIN_SJIS
    #   sjis "BBS_TITLE=集落板\n"
    # end

    # get '/admin/*' do
    #   authenticate!
    #   'admin'
    # end

    get '/admin/:ita/threads' do |ita|
      @board = Board.new File.join('public', ita)
      @threads = @board.threads
      
      content_type HTML_SJIS
      sjis erb :admin_board_threads
    end

    # スレの編集。削除するレスの選択。
    get '/admin/:ita/:sure' do |ita, sure|
      @board = Board.new File.join('public', ita)
      @thread = ThreadFile.new File.join('public', ita, 'dat', "#{sure}.dat")
      @posts = NumberedElement.to_numbered_elements @thread.posts

      content_type HTML_SJIS
      sjis erb :admin_timeline
    end

    # レスの削除。
    post '/admin/:ita/:sure/delete-posts' do |ita, sure|
      @board = Board.new(File.join('public', ita))
      @thread = @board.threads.find { |t| t.id == sure }
      raise 'no such thread' unless @thread

      nposts = @thread.posts.size

      params['post_numbers'].map(&:to_i).each do |res_no|
        raise 'range error' unless res_no.between?(1, nposts)

        @thread.posts[res_no - 1] = @board.grave_stone
      end
      @thread.save

      redirect back
    end

    # スレの削除。
    delete '/admin/:ita/:sure' do |ita, sure|
      @board = Board.new(board_path(ita))

      begin
        @board.delete_thread(sure.to_i)
      rescue Errno::ENOENT
        halt 404, 'no such thread'
      rescue => e
        halt 500, e.message 
      end

      redirect to("/admin/#{ita}/threads")
    end

    get '/admin/:ita/' do |ita|
      redirect to("/admin/#{ita}")
    end

    # 板の設定。
    get '/admin/:ita' do |ita|
      @board = Board.new(board_path(ita))

      @title = "“#{ @board.id }”の設定"

      content_type HTML_SJIS
      sjis erb :admin_board_settings
    end

    patch '/admin/:ita' do |ita|
      convert_params_to_utf8!

      @board = Board.new(board_path(ita))

      params.select do |key, value|
        key =~ /^settings_/
      end.each do |key, value|
        @board.settings[key.sub(/^settings_/, '')] = value
      end

      @board.local_rules = params['local_rules']
      @board.thread_stop_message = params['thread_stop_message']
      @board.id_policy = params['id_policy'].to_sym

      @board.settings.save

      @title = "“#{ @board.id }”の設定"

      content_type HTML_SJIS
      sjis erb :admin_board_settings
    end

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
      convert_params_to_utf8!
      check_non_blank!('bbs', 'key', 'MESSAGE')

      board = Board.new(File.join('public', params['bbs']))
      thread = ThreadFile.new(dat_path(params['bbs'], params['key']))
      if thread.posts.size >= 1000
        @title = "ＥＲＲＯＲ！"
        @reason = "ＥＲＲＯＲ：スレッドストップです。"
        content_type HTML_SJIS
        return sjis erb :post_error
      end

      name, mail, body = params.values_at('FROM', 'mail', 'MESSAGE')

      builder = PostBuilder.new(board, thread, @client)
      post = builder.create_post(name, mail, body)

      thread.posts << post
      thread.save

      @head = "<meta http-equiv=\"refresh\" content=\"1; url=#{h back}\">"
      @title = '書きこみました'

      content_type HTML_SJIS
      sjis erb :posted
    end

    def convert_params_to_utf8!
      new_params = params.to_a.map do |key, value|
        [
          key.as_sjis.to_utf8,
          value.is_a?(Array) ? value.map(&:as_sjis).map(&:to_utf8) : value.as_sjis.to_utf8
        ]
      end.to_h
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

      board = Board.new(File.join('public', params['bbs']))
      name, mail, body = params.values_at('FROM', 'mail', 'MESSAGE')

      begin
        thread = board.create_thread
      rescue Board::ThreadCreateError => e
        # FIXME: ＥＲＲＯＲ！をタイトルとしたHTMLに変更する。
        halt 500, e.message
      end

      builder = PostBuilder.new(board, thread, @client)
      post = builder.create_post(name, mail, body, params['subject'])

      thread.posts << post
      thread.save

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

    set :show_exceptions, :after_handler
    error Board::NotFoundError do |e|
      halt 404, "そんな板ないです。(#{e.message})"
    end
  end
end