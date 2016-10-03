# frozen_string_literal: true
require_relative 'settings'
require_relative 'board'
require_relative 'thread'
require_relative 'post_builder'
require_relative 'numbered_element'
require_relative 'thread_list_renderer'

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
          halt 400, "#{key} must not be blank" if params[key].blank?
        end
      end
    end

    before do
      @site_settings = SettingsFile.new('SETTING.TXT')
      @client = OpenStruct.new
      @client.remote_addr = env['REMOTE_ADDR']
    end

    get '/' do
      @boards = Dir.glob('public/*/SETTING.TXT').map do |path|
        ImmutableBoard.new(File.dirname(path))
      end
      @title = @site_settings['SITE_NAME']

      content_type HTML_SJIS
      sjis erb :index
    end

    get '/:board' do |board|
      redirect to("/#{board}/")
    end

    # 板トップ
    get '/:board/' do
      @threads = @board.threads.sort_by(&:mtime).reverse
      @title = @board.title

      content_type HTML_SJIS
      sjis erb :ita_top
    end

    before '/:board/*' do |board, _rest|
      next if board == 'test' || board == 'admin'

      @board = ImmutableBoard.new(board_path(board))
    end

    before '/admin/:board/?*' do |board, _rest|
      # get メソッドの時は Immutable でいいか。
      @board = case request.request_method
               when 'GET'
                 ImmutableBoard.new(board_path(board))
               else
                 MutableBoard.new(board_path(board))
               end
    end

    before '/test/read.cgi/:board/:sure/?*' do |board, sure, _rest|
      @board = ImmutableBoard.new(board_path(board))
      @thread = @board.threads.find { |th| th.id == sure }
      halt 404, "そんなスレないです。(#{sure})" unless @thread
    end

    get '/test/read.cgi/:board/:sure/:cmd' do |_, _, cmd|
      @title = @thread.subject

      all_posts = NumberedElement.to_numbered_elements @thread.posts

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
      @posts = NumberedElement.to_numbered_elements @thread.posts
      @title = @thread.subject

      content_type HTML_SJIS
      sjis erb :timeline
    end

    get '/:board/subject.txt' do
      renderer = ThreadListRenderer.new(@board.threads)

      content_type PLAIN_SJIS
      sjis renderer.render.to_sjis
    end

    # before '/admin/*' do
    #   authenticate!
    # end

    get '/admin/:board/threads' do
      @threads = @board.threads

      content_type HTML_SJIS
      sjis erb :admin_board_threads
    end

    # スレの編集。削除するレスの選択。
    get '/admin/:board/:sure' do |board, sure|
      @thread = ThreadFile.new File.join('public', board, 'dat', "#{sure}.dat")
      @posts = NumberedElement.to_numbered_elements @thread.posts

      content_type HTML_SJIS
      sjis erb :admin_timeline
    end

    # レスの削除。
    post '/admin/:board/:sure/delete-posts' do |_board, sure|
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
    delete '/admin/:board/:sure' do |board, sure|
      begin
        @board.delete_thread(sure.to_i)
      rescue Errno::ENOENT
        halt 404, 'no such thread'
      rescue => e
        halt 500, e.message
      end

      redirect to("/admin/#{board}/threads")
    end

    get '/admin/:board/' do |board|
      redirect to("/admin/#{board}")
    end

    # 板の設定。
    get '/admin/:board' do
      @title = "“#{@board.id}”の設定"

      content_type HTML_SJIS
      sjis erb :admin_board_settings
    end

    patch '/admin/:board' do
      sleep 10
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
      @title = '書き込みました'
      content_type HTML_SJIS
      sjis erb :posted
    end

    before '/test/bbs.cgi' do
      check_non_blank!('bbs')
      @board = MutableBoard.new(board_path(params['bbs']))
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

    # 例外が起ころうが、ここのコードは実行される。
    after do
      # 板のロックを解除する。
      @board.close if @board
    end
  end
end
