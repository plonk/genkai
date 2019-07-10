# frozen_string_literal: true
require_relative 'settings'
require_relative 'board'
require_relative 'thread'
require_relative 'post_builder'
require_relative 'thread_list_renderer'
require_relative 'authentication_information'

require 'ostruct'

module Genkai
  # Genkaiアプリケーション。
  class Application < Sinatra::Base
    HTML_SJIS = 'text/html;charset=Shift_JIS'
    PLAIN_SJIS = 'text/plain;charset=Shift_JIS'

    # 静的ファイルを提供するときにcharsetを指定しない。SJISのテキスト
    # ファイルがUTF8指定になることを防ぐ。
    set :add_charset, []

    # delete や patch などのメソッドが使えるようにする
    use Rack::MethodOverride

    configure do
      enable :static
      #enable :lock
      mime_type :dat, PLAIN_SJIS
    end

    helpers do
      def authentic?(auth)
        auth.provided? &&
          auth.basic? &&
          auth.credentials == ['admin', @site_settings['MASTER_PASSWORD']]
      end

      def authenticate!
        auth = Rack::Auth::Basic::Request.new(request.env)
        unless authentic?(auth)
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
          halt 400, "#{key} must not be blank" if params[key].blank?
        end
      end

      def get_all_boards
        Dir.glob('boards/*/SETTING.TXT').map do |path|
          Board.new(File.dirname(path))
        end
      end

      def dat_path(board, thread_id)
        File.join(board_path(board), 'dat', "#{thread_id}.dat")
      end

      def board_path(board)
        File.join('boards', board)
      end

      def meta_refresh_tag(seconds, url)
        "<meta http-equiv=\"refresh\" content=\"#{seconds}; url=#{url}\">"
      end

      def convert_params_to_utf8!
        new_params = params.to_a.map do |key, value|
          new_value = if value.is_a?(Array)
                        value.map(&:as_sjis).map(&:to_utf8)
                      else
                        value.as_sjis.to_utf8
                      end
          [key.as_sjis.to_utf8, new_value]
        end.to_h
        params.replace(new_params)
      end
    end

    before do
      @site_settings = SettingsFile.new('SETTING.TXT')
      @client = OpenStruct.new
      @client.remote_addr = env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR']
    end

    # -------- 鯖トップ -------

    get '/' do
      @boards = get_all_boards
      @title = @site_settings['SITE_NAME']

      content_type HTML_SJIS
      sjis erb :index
    end

    # -------- admin ---------

    before '/admin/*' do
      unless request.path =~ %r{^/admin/boards/[A-Za-z0-9]+}
        authenticate!
      end
    end

    before '/admin/boards/:board/?*' do |board, _|
      auth = Rack::Auth::Basic::Request.new(request.env)
      unless authentic?(auth)
        # 板ごとの認証
        key = "PASSWORD_#{board}"
        unless @site_settings[key] != nil &&
               auth.provided? && auth.basic? && auth.credentials == [board, @site_settings[key]]
          response['WWW-Authenticate'] = 'Basic realm="Admin area"'
          halt 401, 'Not Authorized'
        end
      end
    end

    get '/admin/' do
      redirect to '/admin/settings'
    end

    get '/admin/boards' do
      @boards = get_all_boards
      content_type HTML_SJIS
      sjis erb :admin_boards
    end

    # 板の作成
    put '/admin/boards' do
      convert_params_to_utf8!
      check_non_blank!('id', 'password', 'title')

      halt 400, 'invalid id' unless Board.valid_id?(params['id'])
      halt 400, 'invalid password' unless AuthenticationInformation.valid_password?(params['password'])

      @board = Board.create('boards' / params['id'], params['title'])
      @site_settings["PASSWORD_#{params['id']}"] = params['password']
      @site_settings.save

      content_type HTML_SJIS
      redirect back
    end

    before '/admin/boards/:board/?*' do |board, thread|
      @board = Board.new(board_path(board))
    end

    get '/admin/boards/:board/threads' do
      @threads = @board.get_all_threads.sort_by(&:subject)

      content_type HTML_SJIS
      sjis erb :admin_board_threads
    end

    get '/admin/boards/:board/removal' do
      content_type HTML_SJIS
      sjis erb :admin_board_removal
    end

    delete '/admin/boards/:board' do |board|
      # なんかやばい。
      path = 'boards' / board
      halt 400, 'directory not found' unless File.directory?(path)
      halt 400, 'not a board directory' unless File.exist?(path / 'SETTING.TXT') && File.directory?(path / 'dat')
      Board.remove(path)

      @site_settings.delete("PASSWORD_#{board}")
      @site_settings.save

      content_type PLAIN_SJIS
      sjis "板#{board}を削除しました。"
    end

    # スレの編集。削除するレスの選択。
    get '/admin/boards/:board/:sure' do |board, sure|
      @thread = ThreadFile.new File.join(board_path(board), 'dat', "#{sure}.dat")
      @posts = @thread.posts

      content_type HTML_SJIS
      sjis erb :admin_timeline
    end

    # レスの削除。
    post '/admin/boards/:board/:sure/delete-posts' do |_board, sure|
      @thread = @board.find_thread(sure)
      raise "no such thread (#{sure})" unless @thread

      nposts = @thread.posts.size

      params['post_numbers'].map(&:to_i).each do |res_no|
        raise 'range error' unless res_no.between?(1, nposts)

        @thread.posts[res_no - 1] = @board.grave_stone
      end
      @thread.save

      redirect back
    end

    # スレの削除。
    delete '/admin/boards/:board/:sure' do |board, sure|
      begin
        @board.delete_thread(sure.to_i)
      rescue Errno::ENOENT
        halt 404, "no such thread (#{sure})"
      rescue => e
        halt 500, e.message
      end

      redirect to("/admin/#{board}/threads")
    end

    post "/admin/boards/:board/delete-threads" do |board|
      redirect back if params['threads'].nil?

      params['threads'].each do |thread_id|
        @board.delete_thread(thread_id)
      end
      redirect back
    end

    get '/admin/boards/:board/' do |board|
      redirect to("/admin/boards/#{board}")
    end

    # 板の設定。
    get '/admin/boards/:board' do
      @title = "“#{@board.id}”の設定"

      content_type HTML_SJIS
      sjis erb :admin_board_settings
    end

    patch '/admin/boards/:board' do
      convert_params_to_utf8!

      params.select { |key, _| key =~ /^settings_/ }
            .each do |key, value|
        @board.settings[key.sub(/^settings_/, '')] = value
      end

      @board.local_rules = params['local_rules']
      @board.thread_stop_message = params['thread_stop_message']
      @board.id_policy = params['id_policy'].to_sym

      @board.settings.save

      @title = "“#{@board.id}”の設定"

      content_type HTML_SJIS
      sjis erb :admin_board_settings
    end

    get '/admin/settings' do
      content_type HTML_SJIS
      sjis erb :admin_server_settings
    end

    patch '/admin/settings' do
      convert_params_to_utf8!
      check_non_blank!('SITE_NAME')

      @site_settings['SITE_NAME'] = params['SITE_NAME']
      @site_settings.save
      redirect back
    end

    def all_authentication_information
      ary = []
      @site_settings.dictionary.keys.each do |key|
        if key =~ /^PASSWORD_([A-Za-z0-9]+)$/
          ary << AuthenticationInformation.new($1, @site_settings[key])
        end
      end
      ary.sort_by!(&:first)
      ary.unshift AuthenticationInformation.new('admin', @site_settings['MASTER_PASSWORD'])
      ary
    end

    get '/admin/passwords' do
      @auth_infos = all_authentication_information
      content_type HTML_SJIS
      sjis erb :admin_passwords
    end

    def params_to_authentication_information
      params.each_pair.flat_map do |key, value|
        if key =~ /^PASSWORD_([A-Za-z0-9]+)$/
          [AuthenticationInformation.new($1, value)]
        else
          []
        end
      end
    end

    patch '/admin/passwords' do
      convert_params_to_utf8!

      auth_infos = params_to_authentication_information

      auth_infos.each do |info|
        unless AuthenticationInformation.valid_password?(info.password)
          halt 400, "invalid password for (#{info.id})"
        end
      end

      auth_infos.each do |info|
        if info.id == 'admin'
          @site_settings['MASTER_PASSWORD'] = info.password
        else
          @site_settings["PASSWORD_#{info.id}"] = info.password
        end
      end
      @site_settings.save
      redirect back
    end

    # ------- bbs.cgi --------

    before '/test/bbs.cgi' do
      check_non_blank!('bbs')
      @board = Board.new(board_path(params['bbs']))
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

    # パラメーター
    # bbs: 板名
    # key: スレ番号
    # FROM: 名前
    # mail: メールアドレス
    # MESSAGE: 本文
    def post_message
      convert_params_to_utf8!
      check_non_blank!('key', 'MESSAGE')

      thread = ThreadFile.new(dat_path(params['bbs'], params['key']))
      if thread.posts.size >= 1000
        @title = 'ＥＲＲＯＲ！'
        @reason = 'ＥＲＲＯＲ：スレッドストップです。'
        content_type HTML_SJIS
        return sjis erb :post_error
      end

      builder = PostBuilder.new(@board, thread, @client)
      post = builder.create_post(*params.values_at('FROM', 'mail', 'MESSAGE'))

      thread.posts << post
      thread.save

      @head = "<meta http-equiv=\"refresh\" content=\"1; url=#{h back}\">"
      @title = '書きこみました'

      content_type HTML_SJIS
      sjis erb :posted
    end

    # パラメーター
    # subject: スレタイトル
    # bbs: 板名
    # FROM: 名前
    # mail: メールアドレス
    # MESSAGE: 本文
    def create_thread
      convert_params_to_utf8!
      check_non_blank!('subject', 'MESSAGE')

      begin
        thread = @board.create_thread
      rescue Board::ThreadCreateError => e
        # FIXME: ＥＲＲＯＲ！をタイトルとしたHTMLに変更する。
        halt 500, e.message
      end

      builder = PostBuilder.new(@board, thread, @client)
      post = builder.create_post(*params.values_at('FROM', 'mail', 'MESSAGE', 'subject'))

      thread.posts << post
      thread.save

      @head = meta_refresh_tag(1, "/test/read.cgi/#{@board.id}/#{thread.id}")
      @title = '書きこみました。'
      content_type HTML_SJIS
      sjis erb :posted
    end

    # ---------- read.cgi -----------

    before '/test/read.cgi/:board/:sure/?*' do |board, sure, _rest|
      @board = Board.new(board_path(board))
      @thread = @board.find_thread(sure)
      halt 404, "そんなスレないです。(#{sure})" unless @thread
    end

    get '/test/read.cgi/:board/:sure/:cmd' do |_, _, cmd|
      @title = @thread.subject

      all_posts = @thread.posts

      require_first_post = false
      case cmd
      when /^l(\d+)$/
        @posts = all_posts.reverse[0, $1.to_i].reverse
        require_first_post = true
      when /^(\d+)-(\d+)$/
        @posts = all_posts[($1.to_i - 1)..($2.to_i - 1)]
        require_first_post = true
      when /^(\d+)-$/
        @posts = all_posts[($1.to_i - 1)..-1]
        require_first_post = true
      when /^-(\d+)$/
        @posts = all_posts[0..($1.to_i - 1)]
        require_first_post = true
      when /^(\d+)$/
        @posts = [*all_posts[$1.to_i - 1]]
        halt 404, "レス#{$1}はまだありません。" if @posts.empty?
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

    get '/test/read.cgi/:board/:sure' do |_, _|
      @posts = @thread.posts
      @title = @thread.subject

      content_type HTML_SJIS
      sjis erb :timeline
    end

    # ------- 板ディレクトリ ----------

    get '/:board' do |board|
      next unless Board.valid_id?(board)
      redirect to("/#{board}/")
    end

    # 板トップ
    get '/:board/' do |board|
      @board = Board.new(board_path(board))
      @threads = @board.get_all_threads.sort_by(&:mtime).reverse
      @title = @board.title

      content_type HTML_SJIS
      sjis erb :ita_top
    end

    get '/:board/subject.txt' do |board|
      @board = Board.new(board_path(board))
      renderer = ThreadListRenderer.new(@board.get_all_threads)

      content_type PLAIN_SJIS
      sjis renderer.render.to_sjis
    end

    get '/:board/SETTING.TXT' do |board|
      headers["Content-Type"] = PLAIN_SJIS
      send_file(board_path(board) / "SETTING.TXT")
    end

    get '/:board/1000.txt' do |board|
      headers["Content-Type"] = PLAIN_SJIS
      send_file(board_path(board) / "1000.txt")
    end

    get '/:board/head.txt' do |board|
      headers["Content-Type"] = PLAIN_SJIS
      send_file(board_path(board) / "head.txt")
    end

    get '/:board/dat/:thread.dat' do |board, thread|
      error 400, 'invalid thread id' unless thread =~ /\A\d+\z/
      headers["Accept-Ranges"] = "bytes"
      long_polling = params['long_polling'] == "1"
      start = Time.now

      if env["HTTP_RANGE"] =~ /\Abytes=(\d+)-(\d+)?\z/
        lo = $1.to_i
        hi = nil
        if $2
          hi = $2.to_i + 1
        end

        path = dat_path(board, thread)
        begin
          # ranged request
          File.open(path, "r", encoding: "ASCII-8BIT") do |f|
            # dat ファイルのサイズを得る。
            f.seek(0, :END)
            size = f.pos

            if lo < size
              hi ||= size
              unless lo < hi
                error 400, "bad range"
              end
              f.seek(lo, :SET)
              buf = f.read(hi - lo)
              if buf.nil? || buf.size != hi - lo
                fail "read error"
              end
              return [206, # Partial Content
                      { "Content-Range" => "bytes #{lo}-#{hi-1}/#{size}",
                        "Content-Length" => buf.size.to_s },
                      buf]
            elsif lo == size
              if long_polling && Time.now - start < 130
                raise WaitFileChange
              else
                return [416, {}, ""]
              end
            else
              # Requested Range Not Satisfiable
              return [416, {}, ""]
            end
          end
        rescue WaitFileChange
          system("inotifywait -q -e DELETE_SELF -t 1 #{path}")
          retry
        end
      else
        send_file(dat_path(board, thread))
      end
    end

    # ------ エラー処理 -------

    set :show_exceptions, :after_handler
    error Board::NotFoundError do |e|
      halt 404, "そんな板ないです。(#{e.message})"
    end
  end

  class WaitFileChange < Exception
  end

end
