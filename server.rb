require 'sinatra/base'
require 'webrick'
require_relative 'genkai'

# Reason phrase のあとに空白が入るバグをモンキーパッチする。
module WEBrick
  class HTTPResponse
    def status_line
      "HTTP/#@http_version #@status #@reason_phrase#{CRLF}"
    end
  end
end

Process.setproctitle("genkai")
app = Genkai::Application.new
srv = WEBrick::HTTPServer.new({ :DocumentRoot => './',
                                :BindAddress => '0.0.0.0',
                                :Port => 10000})
srv.mount('/', Rack::Handler::WEBrick, app)
trap("INT"){ srv.shutdown }
srv.start
