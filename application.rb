# frozen_string_literal: true
require 'sinatra'
require_relative 'settings'
require_relative 'board'
require_relative 'thread'
require_relative 'post_builder'
require_relative 'thread_list_renderer'
require_relative 'authentication_information'
require 'time' # for Time.httpdate, Time#httpdate

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

      # "Sinatra doesn't now this ditty." ページなどで UTF-8 指定が付くようにする。
      add_charset << "text/html"
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

      def refresh_meta_tag(seconds, url)
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

    @@site_settings = SettingsFile.new('SETTING.TXT')
    @@post_lock = Monitor.new

    before do
      @site_settings = @@site_settings
    end

    # -------- 鯖トップ -------

    get '/' do
      @boards = get_all_boards
      @title = @site_settings['SITE_NAME']

      content_type HTML_SJIS
      erb(:index).to_sjis!
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
      erb(:admin_boards).to_sjis!
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
      erb(:admin_board_threads).to_sjis!
    end

    get '/admin/boards/:board/removal' do
      content_type HTML_SJIS
      erb(:admin_board_removal).to_sjis!
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

    get '/admin/boards/:board/ban' do
      halt 400, "Invalid ID" unless validate_id(params['id'])
      ids = (@board.settings["BANNED_IDS"] || "").split
      ids = ids | [params['id']] # union
      @board.settings["BANNED_IDS"] = ids.join(' ')
      @board.settings.save
      redirect back
    end

    get '/admin/boards/:board/unban' do
      halt 400, "Invalid ID" unless validate_id(params['id'])
      ids = (@board.settings["BANNED_IDS"] || "").split
      ids = ids - [params['id']] # difference
      @board.settings["BANNED_IDS"] = ids.join(' ')
      @board.settings.save
      redirect back
    end

    get '/admin/boards/:board/banned-ids' do
      erb :admin_board_banned_ids, locals: { ids: (@board.settings["BANNED_IDS"] || "").split }
    end

    # スレの編集。削除するレスの選択。
    get '/admin/boards/:board/:sure' do |board, sure|
      @thread = @board.find_thread(sure)
      halt(404, "no such thread (#{sure})") unless @thread

      @posts = @thread.posts

      content_type HTML_SJIS
      erb(:admin_timeline).to_sjis!
    end

    # レスの削除。
    post '/admin/boards/:board/:sure/delete-posts' do |_board, sure|
      @thread = @board.find_thread(sure)
      halt(400, "no such thread (#{sure})") unless @thread

      nposts = @thread.posts.size

      params['post_numbers'].map(&:to_i).each do |res_no|
        halt(400, 'range error') unless res_no.between?(1, nposts)

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
      erb(:admin_board_settings).to_sjis!
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
      erb(:admin_board_settings).to_sjis!
    end

    get '/admin/settings' do
      content_type HTML_SJIS
      erb(:admin_server_settings).to_sjis!
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
      erb(:admin_passwords).to_sjis!
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

    def validate_id(str)
      !!(str =~ %r(\A[A-Za-z0-9+/]{8}\z))
    end

    # ------- nitecast.cgi --------

    get '/test/nitecast.cgi/:board/:sure/' do |board, sure|
      @board = Board.new(board_path(board))
      @thread = @board.find_thread(sure)
      halt 404, "そんなスレないです。(#{sure})" unless @thread
      content_type HTML_SJIS
      erb(:nitecast, layout: false).to_sjis!
    end

    get '/test/nitecast.cgi/:board/' do |board|
      @board = Board.new(board_path(board))
      threads = @board.get_all_threads
      active_thread = threads.sort_by(&:mtime).reverse.find { |t| t.size < 1000 }
      if active_thread
        redirect to("/test/nitecast.cgi/#{@board.id}/#{active_thread.id}/?#{request.query_string}")
      else
        halt 404, "空いてるスレッドないです。"
      end
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

      @@post_lock.synchronize do

        thread = ThreadFile.new(dat_path(params['bbs'], params['key']))
        if thread.size >= 1000
          @title = 'ＥＲＲＯＲ！'
          @reason = 'ＥＲＲＯＲ：スレッドストップです。'
          content_type HTML_SJIS
          return erb(:post_error).to_sjis!
        end

        remote_addr = env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR']
        builder = PostBuilder.new(@board, thread, remote_addr)
        if @board.settings["BANNED_IDS"].include?(builder.id)
          @title = 'ＥＲＲＯＲ！'
          @reason = 'ＥＲＲＯＲ：ホスト規制により書き込めませんでした。'
          content_type HTML_SJIS
          return erb(:post_error).to_sjis!
        end
        post = builder.create_post(*params.values_at('FROM', 'mail', 'MESSAGE'))

        thread.posts << post

        if thread.posts.size == 1000
          # 次スレッド建てるん？？？？
          begin
            next_thread = @board.create_thread
          rescue
          end
          subject = Genkai.increment_subject(thread.subject)
          if @board.get_all_threads.none? { |t| t.subject == subject }
            builder = PostBuilder.new(@board, next_thread, 'localhost')
            post = builder.create_post('システム',
                                       'age', # 次スレはageる。
                                       thread.posts[0].body,
                                       subject)
            next_thread.posts << post
            next_thread.save
          end

          # 1001 追加。
          body = @board.thread_stop_message + "\n次スレ: #{subject}"
          PostBuilder.new(@board, thread, 'localhost')
          post = builder.create_post('システム',
                                     'sage', 
                                     body)
          post.date = '1000 Over Thread'
          thread.posts << post
        end

        thread.save

      end # synchronize

      @head = "<meta http-equiv=\"refresh\" content=\"1; url=#{h back}\">"
      @title = '書きこみました'

      content_type HTML_SJIS
      erb(:posted).to_sjis!
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

      remote_addr = env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR']
      builder = PostBuilder.new(@board, thread, remote_addr)
      post = builder.create_post(*params.values_at('FROM', 'mail', 'MESSAGE', 'subject'))

      thread.posts << post
      thread.save

      @head = refresh_meta_tag(1, "/test/read.cgi/#{@board.id}/#{thread.id}")
      @title = '書きこみました。'
      content_type HTML_SJIS
      erb(:posted).to_sjis!
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
        @posts = all_posts.last(3)
        require_first_post = true
      when /^(\d+)-(\d+)$/
        @posts = all_posts[($1.to_i - 1)..($2.to_i - 1)]
        require_first_post = true
      when /^(\d+)-$/
        @posts = all_posts[($1.to_i - 1)..-1]
        require_first_post = true
      when /^-(\d+)$/
        @posts = all_posts.first($1.to_i)
        require_first_post = true
      when /^(\d+)$/
        @posts = [*all_posts[$1.to_i - 1]]
        halt 404, "レス#{$1}はまだありません。" if @posts.empty?
      else
        halt 400, 'わかりません。'
      end

      if require_first_post && @posts.first.number != 1
        # 1レス目が含まれていなかったら、先頭に追加する。
        @posts.unshift(all_posts.first)
      end

      @dat_size = @thread.bytesize

      content_type HTML_SJIS
      erb(:timeline).to_sjis!
    end

    get '/test/read.cgi/:board/:sure' do |board, sure|
      redirect to("/test/read.cgi/#{board}/#{sure}/")
    end

    get '/test/read.cgi/:board/:sure/' do |_, _|
      @posts = @thread.posts
      @title = @thread.subject
      @dat_size = @thread.bytesize

      content_type HTML_SJIS
      erb(:timeline).to_sjis!
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
      erb(:ita_top).to_sjis!
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
      format = params['format'] || "raw"
      start = Time.now

      halt 400, "format" unless %w[html json raw].include?(format)

      if format == "html"
        headers["Content-Type"] = 'text/html;charset=UTF-8'
      elsif format == "json"
        headers["Content-Type"] = 'application/json;charset=UTF-8'
      else
        headers["Content-Type"] = PLAIN_SJIS
      end

      if env["HTTP_RANGE"] =~ /\Abytes=(\d+)-(\d+)?\z/
        lo = $1.to_i
        hi = nil
        if $2
          hi = $2.to_i + 1
        end

        path = dat_path(board, thread)
        begin
          # ranged request
          File.open(path, "r") do |f|
            if env["HTTP_IF_MODIFIED_SINCE"]
              # 秒未満を切り捨てる。
              filedate = Time.httpdate(f.stat.mtime.httpdate)
              if filedate <= Time.httpdate(env["HTTP_IF_MODIFIED_SINCE"])
                return [304,
                        {
                          "Last-Modified" => f.stat.mtime.httpdate,
                        }]
              end
            end

            # dat ファイルのサイズを得る。
            f.seek(0, :END)
            size = f.pos

            if lo < size
              hi ||= size
              unless lo < hi
                error 400, "bad range"
              end
              f.seek(lo, :SET)
              buf = f.read(hi - lo) # エンコーディングは ASCII-8BIT。
              if buf.nil? || buf.bytesize != hi - lo
                fail "read error"
              end

              if format == "html"
                f.seek(0, :SET)
                start_no = f.read(lo).count("\n") + 1

                @posts = []
                buf.as_sjis!.to_utf8!.each_line.with_index(start_no) do |line, lineno|
                  @posts << Post.from_line(line, lineno)
                end
                buf = erb(:ajax_timeline, layout: false)
              elsif format == "json"
                messages = []
                buf.as_sjis!.to_utf8!.each_line do |line|
                  messages << Post.from_line(line).body
                end
                buf = JSON.dump({ "messages" => messages, "dat_size" => size })
              end
              return [206, # Partial Content
                      {
                        "Content-Range" => "bytes #{lo}-#{hi-1}/#{size}",
                        "Content-Length" => buf.bytesize.to_s,
                        "Last-Modified" => f.stat.mtime.httpdate
                      },
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
        rescue Errno::ENOENT
          halt 404, "File not found"
        end
      else
        if format == "html"
          @posts = ThreadFile.new(board, thread).posts
          erb(:ajax_timeline, layout: false)
        elsif format == "json"
          messages = []
          thread = ThreadFile.new(board, thread)
          thread.posts.each do |post|
            messages << post.body
          end
          JSON.dump({ "messages" => messages, "dat_size" => thread.bytesize })
        else
          send_file(dat_path(board, thread))
        end
      end
    end

    after do
      # メモリを節約。
      GC.start
    end

    # ------ エラー処理 -------

    set :show_exceptions, :after_handler
    error Board::NotFoundError do |e|
      halt 404, "そんな板ないです。(#{e.message})"
    end
  end

  class WaitFileChange < Exception
  end

  module_function

  def increment_subject(subject)
    digit_spans = subject.scan(/\d+/)
    if digit_spans.empty?
      return subject + "2"
    else
      i = 0
      return subject.gsub(/\d+/) do |digits|
        i += 1
        if i == digit_spans.size
          (digits.to_i + 1).to_s
        else
          digits
        end
      end
    end
  end
end
