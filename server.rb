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

log_file = File.open('error_log', 'a+')
log = WEBrick::Log.new log_file
log_file2 = File.open('access_log', 'a+')
access_log = [
  [log_file2, WEBrick::AccessLog::COMBINED_LOG_FORMAT],
]
Process.setproctitle("genkai")
app = Genkai::Application.new
srv = WEBrick::HTTPServer.new({ :DocumentRoot => './',
                                :BindAddress => '0.0.0.0',
                                :Port => 10000,
                                :Logger => log,
                                :AccessLog => access_log})
srv.mount('/', Rack::Handler::WEBrick, app)
trap("INT"){ srv.shutdown }
srv.start
