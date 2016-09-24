require 'sinatra'

module Genkai
  class ThreadFile
    attr_reader :name, :id

    def initialize(path)
      @data = File.read(path).force_encoding("CP932").encode("UTF-8")

      @name = @data.each_line { |line| break line.chomp.split('<>')[4] }
      @id = path.split('/')[-1].gsub('.dat', '')
    end

    def number_posts
      @data.each_line.count
    end

    def posts(range)
      ary = []
      @data.each_line.with_index(1) do |line, res_no|
        next unless range.include?(res_no)

        name, mail, date, body, title = line.chomp.split('<>', 5)
        post = Post.new(res_no.to_s, name, mail, date, body)
        ary << post
      end
      return ary
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
    helpers do 

      def authenticate!
        auth = Rack::Auth::Basic::Request.new(request.env)
        unless auth.provided? and auth.basic? and auth.credentials == ['admin', '1234']
          response['WWW-Authenticate'] = "Basic realm=\"Admin area\""
          halt 401, 'Not Authorized'
        end
      end

      # HTML エスケープ略記。
      def h(text)
        Rack::Utils.escape_html(text)
      end

    end

    get '/' do
      @itas = Dir.glob('public/*/').map { |path| path.split('/')[1] }
      erb :index 
    end

    # 板トップ
    get '/:ita/' do |ita|
      unless File.directory? File.join('public', ita)
        halt 404, "そんな板ないです。(#{ita})"
      end
      @ita_name = ita

      @threads = Dir.glob("public/#{ita}/dat/*.dat").map { |dat| ThreadFile.new(dat) }

      erb :ita_top
    end

    get '/test/read.cgi/:ita/:sure/:cmd' do
      "#{params['ita']}, #{params['sure']}, #{params['cmd']}"
    end

    get '/test/read.cgi/:ita/:sure' do |ita, sure|
      # "%s, %s" % [ita, sure]

      ita_path = File.join('public', ita)
      sure_path = File.join('public', ita, 'dat', "#{sure}.dat")

      unless File.directory? ita_path
        halt 404, "そんな板ないです。(#{ita})"
      end
      unless File.readable? sure_path
        halt 404, "そんなスレないです。(#{sure})"
      end

      @ita_name = ita
      @thread = ThreadFile.new(sure_path)

      [200, {"Content-Type" => "text/html; charset=Shift_JIS"}, erb(:timeline).encode("CP932")]
    end

    get '/:ita/subject.txt' do |ita|
      unless File.directory? ita_path
        halt 404, "そんな板ないです。(#{ita})"
      end

      Dir.glob("public/#{ita}/dat/*.dat")
    end

    get '/admin/*' do
      authenticate!
      'admin'
    end

    require 'tempfile'

    def to_2ch_dat_line(post, thread_title = "")
      ([post.name, post.mail, post.date, post.body, thread_title].join('<>') + "\n").encode('Shift_JIS')
    end

    def format_date(time)
      time.strftime("%Y/%m/%d(%%s) %H:%M:%S") % "日月火水木金土"[time.wday]
    end

    ESCAPE_TABLE = { '<' => 'lt;', '>' => 'gt;', '&' => '&amp;' }
    def escape_field(str)
      str.gsub(/[<>&]/) { |char| ESCAPE_TABLE[char] }
    end

    def escape_body(body)
      " " + escape_field(body).each_line.map { |line| line.chomp }.join(" <br> ") + " "
    end

    def create_new_post(name, mail, message)
      date = format_date(Time.now.localtime)
      Post.new("n/a", escape_field(name), escape_field(mail), escape_field(date), escape_body(message))
    end

    def sjis(utf8)
      [200, 
       {'Content-Type' => 'text/html; charset=Shift_JIS' },
       utf8.encode("Shift_JIS")]
    end

    # bbs: 板名
    # key: スレ番号
    # FROM: 名前
    # mail: メールアドレス
    # MESSAGE: 本文
    post '/test/bbs.cgi' do
      sure_path = File.join('public', params['bbs'], 'dat', "#{params['key']}.dat")

      halt 400, 'name required'  if [nil, ""].include?(params['FROM'])
      halt 400, 'message body required' if [nil, ""].include?(params['MESSAGE'])

      t = Tempfile.new(['genkai', '.dat'], "tmp")
      t.write(File.read(sure_path))


      post = create_new_post(*params.values_at('FROM', 'mail', 'MESSAGE').map { |s| s.force_encoding('Shift_JIS').encode('UTF-8')} )
      line = [post.name, post.mail, post.date, post.body, ""].join('<>') + "\n"

      t.puts(line.encode('Shift_JIS'))

      t.close

      File.rename(t.path, sure_path)

      @head = "<meta http-equiv=\"refresh\" content=\"1; url=#{h back}\">"
      sjis(erb :posted)
    end
  end
end

require 'rack/mount'

run Genkai::Application
