# frozen_string_literal: true
require 'sinatra'
require_relative 'settings'
require_relative 'board'
require_relative 'thread_file'
require_relative 'post_builder'
require_relative 'thread_list_renderer'
require_relative 'authentication_information'
require 'time' # for Time.httpdate, Time#httpdate
require_relative 'peercast'
require 'resolv'
require_relative 'string_helpers'
require_relative 'unicode/emoji_annotator'

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
          if params[key].blank?
            if params[:charset]&.upcase == "UTF-8"
              content_type "text/html; charset=UTF-8"
              halt 400, error_response("#{key} must not be blank")
            else
              content_type HTML_SJIS
              halt 400, error_response("#{key} must not be blank").to_sjis
            end
          end
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
                      elsif value.is_a?(String)
                        value.as_sjis.to_utf8
                      else
                        value # expecting value to be nil ...
                      end
          [key.as_sjis.to_utf8, new_value]
        end.to_h
        params.replace(new_params)
      end

      def valid_user_id?(str)
        !!(str =~ %r(\A[0-9A-Za-z+\/]{8}\z))
      end

      def unescape_body(str)
        StringHelpers.unescape_field(str.gsub(/<\/?a[^>]*>/, '').gsub(' <br> ', "\n").gsub(/^ | $/, ''))
      end

      def latest(path)
        fail "relative path not supported" unless path.start_with?('/')
        abpath = File.join(settings.public_folder, path)
        mtime = File.mtime(abpath)
        path + "?" + mtime.to_i.to_s
      end

      def linkify(text)
        # [&;] を許可することで、&amp; の含まれた HTML unescape されていない文字列にもマッチする。
        text = text.gsub(/h?ttps?:\/\/[A-Za-z0-9+\/~_\-.?=%&;]+/, "<a href=\"\\&\">\\&</a>")
        return text
      end
    end

    @@site_settings = SettingsFile.new('SETTING.TXT')
    @@post_lock = Monitor.new

    @@trees = nil # リレーツリーのキャッシュ。

    before do
      @site_settings = @@site_settings

      remote_addr = env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR']
      # 逆引きチェック
      begin
        remote_host = Resolv.getname(remote_addr)
      rescue Resolv::ResolvError
        halt 403, 'IPアドレスが逆引きできないため利用できません。'
      end
#      begin
#        unless Resolv.getaddresses(remote_host).include?(remote_addr)
#          halt 403, 'IPアドレス逆引きの結果が齟齬するため利用できません。'
#        end
#      rescue Resolv::ResolvError
#        halt 403, 'IPアドレスの逆引きの結果が正引きできないため利用できません。'
#      end
      # jpドメインチェック
      unless remote_host =~ /(\.jp|\.bbtec\.net|\.21company\.com)\Z/
        halt 403, 'ドメイン規制により利用できません。'
      end          
      if remote_host =~ /(\.au-net\.ne\.jp)\Z/
        halt 403, 'ドメイン規制により利用できません。'
      end          
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

    get '/admin/boards/:board/mute' do
      halt 400, "Invalid ID" unless validate_id(params['id'])
      ids = (@board.settings["MUTED_IDS"] || "").split
      ids = ids | [params['id']] # union
      @board.settings["MUTED_IDS"] = ids.join(' ')
      @board.settings.save
      redirect back
    end

    get '/admin/boards/:board/unmute' do
      halt 400, "Invalid ID" unless validate_id(params['id'])
      ids = (@board.settings["MUTED_IDS"] || "").split
      ids = ids - [params['id']] # difference
      @board.settings["MUTED_IDS"] = ids.join(' ')
      @board.settings.save
      redirect back
    end

    get '/admin/boards/:board/banned-ids' do
      erb :admin_board_banned_ids, locals: { ids: (@board.settings["BANNED_IDS"] || "").split }
    end

    get '/admin/boards/:board/muted-ids' do
      erb :admin_board_muted_ids, locals: { ids: (@board.settings["MUTED_IDS"] || "").split }
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

      unless params['post_numbers']
        halt 400, "post_numbers"
      end

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

      @board.emoji_only = (params['emoji_only'] == 'true')
      @board.reject_same_content = (params['reject_same_content'] == 'true')
      @board.forbid_nonviewer = (params['forbid_nonviewer'] == 'true')

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

    get '/test/community_overlay.cgi' do
      content_type 'text/html; charset=UTF-8'
      erb(:community_overlay, layout: false)
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
      begin
        convert_params_to_utf8!
      rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        # たぶん params はすでに UTF-8 だった。
        esc_nonjis = proc do |s|
          s
            .encode('CP932', fallback: proc { |s| "&##{s.ord.to_s};" })
            .encode('UTF-8')
        end
        new_params = params.each_pair.map { |key, value|
          [
            esc_nonjis.(key),
            case value
            when Array then value.map(&esc_nonjis)
            when String then esc_nonjis.(value)
            when nil
              value
            end
          ]
        }.to_h
        params.replace(new_params)
      end

      mode = params['submit']
      case mode
      when '書き込む'
        begin
          post_message
        rescue => e # halt は rescue されない。
          puts e.message
          if params[:charset]&.upcase == "UTF-8"
            content_type "text/html; charset=UTF-8"
            return error_response(e.message)
          else
            content_type HTML_SJIS
            return error_response(e.message).to_sjis!
          end
        end
      when '新規スレッド作成'
        # halt 403, 'unimplemented'
        board = params['bbs']
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
        create_thread
      else
        halt 400, 'Unknown command'
      end
    end

    def error_response(message)
      @title = 'ＥＲＲＯＲ！'
      @reason = "ＥＲＲＯＲ：#{message}"
      erb(:post_error)
    end

    # String =~ nil は nil になるようなのでこれでいいだろう。
    NG_REGEXP = eval(File.read("ng_exp.txt")) rescue nil

    def is_in_relay_tree(tree, remote_addr)
      raise TypeError, "tree must be a Hash" unless tree.is_a? Hash

      unless remote_addr =~ /\A\d+\.\d+\.\d+\.\d+\z/
        raise 'not an IPv4 address'
      end
      if tree['address'] == remote_addr
        return [tree]
      elsif tree['children']
        return tree['children'].inject([]) { |acc,subtree| acc + is_in_relay_tree(subtree, remote_addr) }
      else
        return []
      end
    end

    def find_node(top_nodes, remote_addr)
      raise TypeError, "top_nodes must be an Enumerable" unless top_nodes.is_a?(Enumerable)

      return top_nodes.inject([]) { |acc,tree| acc + is_in_relay_tree(tree, remote_addr) }
    end

    def extra_label(node)
      label = ""
      if node['isFirewalled']
        label = "ポト０"
      end

      if node['isRelayFull'] && node['localRelays'] == 0
        label += "紫"
      elsif node['isRelayFull'] && node['localRelays'] > 0
        label += "青"
      elsif node['localRelays'] >= 0
        label += "緑"
      end
      return label
    end

    def emoji?(str)
      annotate = EmojiAnnotator.new
      segments = annotate.(str)
      return segments.all? { _1[0] == :annotated }
    end

    # パラメーター
    # bbs: 板名
    # key: スレ番号
    # FROM: 名前
    # mail: メールアドレス
    # MESSAGE: 本文
    def post_message
      check_non_blank!('key', 'MESSAGE')

#puts '--post message--'
#p env
#p params

      if params['MESSAGE'].size > 300
        fail '文字数が多すぎて投稿できません。'
      end

      if @board.emoji_only?
        unless params[:FROM].blank?
          fail '名前は空欄にしてください。'
        end
      end

      if params[:mail].nil?
        params[:mail] = ""
      end
      unless params[:mail] =~ /\A[\x21-\x7e]*\z/
        fail 'メールアドレスにASCII図形文字以外は使えません。'
      end

      params['MESSAGE'].gsub!(/&#[xX]([0-9a-fA-F]+);/) { "&##{$1.to_i(16)};" }
      if @board.emoji_only?
        proc do
          require 'cgi'
          body = CGI.unescapeHTML(params['MESSAGE']).strip
          unless emoji?(body)
            bin = body.each_char.map { |c| "%X" % c.ord }.join(' ')
            fail "絵文字ではないので書き込めません。(#{bin})"
          end
        end.()
      end
      
      @@post_lock.synchronize do

        thread = ThreadFile.new(dat_path(params['bbs'], params['key']))
        if thread.size >= 1000
          fail 'スレッドストップです。'
        end

        # 存在しないスレッドに書き込もうとしている。
        if thread.size == 0
          fail 'スレッドがありません。'
        end

        remote_addr = env['HTTP_X_FORWARDED_FOR'] || env['REMOTE_ADDR']

        nodes = []
        proc do
          # TP 7148; SP 7152; Heisei 7150; Turf 7154
          for port in [8144] #[7148, 7150, 7152, 7154]
            peercast = Peercast.new('localhost', port)
            channels = peercast.getChannels
#p channels
            ch = channels.find { |i| i['status']['isBroadcasting'] }
            chid = nil
            network = nil
            if ch
              chid = ch['channelId']
              network = ch['status']['network'] || 'ipv4'
            else
              next
            end
            if chid && network == "ipv4"
              trees = peercast.getChannelRelayTree(chid)
              if (nodes += find_node(trees, remote_addr)).any?
                break
              else
                if @board.forbid_nonviewer?
                  board = params['bbs']
                  auth = Rack::Auth::Basic::Request.new(request.env)
                  unless authentic?(auth)
                    # 板ごとの認証
                    key = "PASSWORD_#{board}"
                    unless @site_settings[key] != nil &&
                           auth.provided? && auth.basic? && auth.credentials == [board, @site_settings[key]]
                      response['WWW-Authenticate'] = 'Basic realm="Admin area"'
                      if params[:charset]&.upcase == "UTF-8"
                        content_type "text/html; charset=UTF-8"
                        halt 401, error_response('視聴されていないホストからは書き込めません。')
                      else
                        content_type HTML_SJIS
                        halt 401, error_response('視聴されていないホストからは書き込めません。').to_sjis
                      end
                    end
                  end
                end
                break
              end
            end
          end
        end.()

        proc do
          id = Digest::MD5.base64digest(remote_addr)[0, 8]
          if (@board.settings["BANNED_IDS"] || "").include?(id)
            fail 'ホスト規制により書き込めませんでした。'
          end
        end.()

        post = nil
        proc do
          builder = PostBuilder.new(@board, thread, remote_addr)
          from, mail, message = params.values_at('FROM', 'mail', 'MESSAGE')
          if nodes.any?
            vers = nodes.map { |n| n["versionString"] + extra_label(n) }.compact
            if from.blank?
              from = vers.join(', ')
            else
              from = "#{from} (#{vers.join(', ')})"
            end
          end
          post = builder.create_post(from, mail, message)
        end.()

        proc do
          id = Digest::MD5.base64digest(remote_addr)[0, 8]
          if (@board.settings["MUTED_IDS"] || "").include?(id)
            post.subject = 'muted'
          end
        end.()

        # NGワードチェック
        if post.body.gsub(/[ -~]/, '') =~ NG_REGEXP
          fail 'その内容のメッセージは書き込めません。'
        end

        # ポートチェック
        # proc do
        #   result = []
        #   [ Thread.start { result << system("curl -I --connect-timeout 3 http://#{remote_addr}/") },
        #     Thread.start { result << system("curl -I --connect-timeout 3 http://#{remote_addr}:8080/") },
        #     Thread.start { result << system("curl -I --connect-timeout 3 https://#{remote_addr}/") } ].each do |t|
        #     t.join
        #   end
        #   if result.any?
        #     content_type HTML_SJIS
        #     return error_response('特定のポートが空いているホストからは書き込めません。').to_sjis!
        #   end
        # end.()

        # # 逆引きチェック
        # begin
        #   remote_host = Resolv.getname(remote_addr)
        # rescue Resolv::ResolvError
        #   fail '逆引きチェック失敗。'
        # end
        # # jpドメインチェック
        # unless remote_host =~ /(\.jp|\.bbtec\.net)\Z/
        #   fail 'ドメイン規制により書き込めません。'
        # end          
        
        if @board.reject_same_content? && thread.posts.last(25).any? { |x| x.body == post.body }
          fail '最近のレスと重複する内容は書き込めません。'
        end
        
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
                                       unescape_body(thread.posts[0].body),
                                       subject)
            next_thread.posts << post
            next_thread.save
          end

          # 1001 追加。
          body = @board.thread_stop_message + "\n次スレ: #{subject}"
          builder = PostBuilder.new(@board, thread, 'localhost')
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

      if params[:charset]&.upcase == "UTF-8"
        content_type "text/html; charset=UTF-8"
        erb(:posted)
      else
        content_type HTML_SJIS
        erb(:posted).to_sjis!
      end
    end

    # パラメーター
    # subject: スレタイトル
    # bbs: 板名
    # FROM: 名前
    # mail: メールアドレス
    # MESSAGE: 本文
    def create_thread
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

    get '/test/read.cgi/:board/?' do |board|
      redirect to("/#{board}/")
    end

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
        @posts = all_posts.last($1.to_i)
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
      erb(:timeline, locals: { speech_enabled_js: 'false' }).to_sjis!
    end

    get '/test/read.cgi/:board/:sure' do |board, sure|
      redirect to("/test/read.cgi/#{board}/#{sure}/")
    end

    get '/test/read.cgi/:board/:sure/' do |_, _|
      @posts = @thread.posts
      @title = @thread.subject
      @dat_size = @thread.bytesize

      content_type HTML_SJIS
      erb(:timeline, locals: { speech_enabled_js: 'true' }).to_sjis!
    end

    # ------- 板ディレクトリ ----------

    get '/:board' do |board|
      next unless Board.valid_id?(board)
      redirect to("/#{board}/")
    end

    require 'ostruct'
    # 板トップ
    get '/:board/' do |board|
      @board = Board.new(board_path(board))
      @title = @board.title

      make_subject_txt(board)
      text = File.read(board_path(board) / "subject.txt", encoding: "CP932").to_utf8!
      @threads = text.each_line.map { |line|
        line.chomp
        if line =~ /^(\d+).dat<>(.+?) \((\d+)\)$/
          OpenStruct.new(id: $1, subject: $2, size: $3.to_i)
        else
          halt 400, "corrupt subject.txt?"
        end
      }
      content_type HTML_SJIS
      erb(:ita_top).to_sjis!
    end

    def make_subject_txt(board)
      subject_path = board_path(board) / "subject.txt"
      threads = Board.new(board_path(board)).get_all_threads

      regen = false
      if File.exist?(subject_path)
        st = File.mtime(subject_path)
        unless threads.all? { |t| t.mtime < st } && File.mtime(board_path(board) / "dat") < st
          regen = true
        end
      else
        regen = true
      end

      if regen
        renderer = ThreadListRenderer.new(threads)
        data = renderer.render.to_sjis
        File.open(subject_path, "w") do |f|
          f.write(data)
        end
        true
      else
        false
      end
    end

    get '/:board/subject.txt' do |board|
      make_subject_txt(board)
      content_type PLAIN_SJIS
      send_file(board_path(board) / "subject.txt")
    end

    get '/:board/SETTING.TXT' do |board|
      if params[:format] == 'json'
        content_type 'application/json'
        #headers "Access-Control-Allow-Origin" => '*'

        lines = File.read(board_path(board) / "SETTING.TXT", encoding: 'CP932').encode('UTF-8').lines.map(&:chomp)
        object = lines.map { |ln| ln.split('=',2) }.to_h
        return JSON.dump(object)
      else
        headers["Content-Type"] = PLAIN_SJIS
        send_file(board_path(board) / "SETTING.TXT")
      end
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

      @board = Board.new(board_path(board))

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
              begin
                clientdate = Time.httpdate(env["HTTP_IF_MODIFIED_SINCE"])
              rescue ArgumentError
                # Unacast で初回DAT取得時に "[Object object]" という内
                # 容の If-Modifierd-Since ヘッダー値が渡される。そのよ
                # うな場合、If-Modified-Since ヘッダが渡されたという事
                # 実を無視して完全なDATを返す。
                puts "Invalid If-Modified-Since header: #{env["HTTP_IF_MODIFIED_SINCE"].inspect}"
              end
              if clientdate && filedate <= clientdate
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
                buf = erb(:ajax_timeline, layout: false, locals: { board: board, thread: thread })
              elsif format == "json"
                f.seek(0, :SET)
                start_no = f.read(lo).count("\n") + 1

                @posts = []
                buf.as_sjis!.to_utf8!.each_line.with_index(start_no) do |line, lineno|
                  @posts << Post.from_line(line, lineno)
                end
                html = erb(:ajax_timeline, layout: false, locals: { board: board, thread: thread })

                posts = []
                buf.each_line do |line|
                  posts << Post.from_line(line).to_h
                end
                buf = JSON.dump({
                                  "posts" => posts,
                                  "dat_size" => size,
                                  "thread_size" => start_no + posts.size - 1,
                                  "html" => html
                                })
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
          @posts = ThreadFile.new(dat_path(board, thread)).posts
          erb(:ajax_timeline, layout: false, locals: { board: board, thread: thread })
        elsif format == "json"
          posts = []
          thread_file = ThreadFile.new(dat_path(board, thread))
          posts = thread_file.posts.map(&:to_h)

          @posts = thread_file.posts
          html = erb(:ajax_timeline, layout: false, locals: { board: board, thread: thread })

          JSON.dump({
                      "posts" => posts,
                      "dat_size" => thread_file.bytesize,
                      "thread_size" => thread_file.size,
                      "html" => html
                    })
        else
          send_file(dat_path(board, thread))
        end
      end
    end

    get '/api/getRes/:board/:thread/:number' do |board, thread, number|
      halt 400, 'number' unless number =~ /\A[1-9][0-9]*\z/

      target_number = number.to_i

      posts = ThreadFile.new(dat_path(board, thread)).posts
      # DATファイルが無い場合、posts は空配列になる。
      post = posts.find { _1.number == target_number }

      if post
        content_type 'application/json'
        return { post: post }.to_json
      else
        halt 404, 'No such post found'
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
