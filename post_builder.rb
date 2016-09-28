require_relative 'extensions'
require_relative 'board'
require_relative 'thread'
require_relative 'post'

module Genkai
  class PostBuilder
    class << self
      def linkify(escaped_body, board_id, thread_id)
        escaped_body.gsub(/&gt;&gt;(\d+(-\d+)?)/) do |str|
          "<a href=\"/test/read.cgi/#{board_id}/#{thread_id}/#{$1}\">#{str}</a>"
        end
      end

      def format_date(time)
        time.strftime('%Y/%m/%d(%%s) %H:%M:%S') % '日月火水木金土'[time.wday]
      end
    end

    def initialize(board, thread, client)
      @board = board
      @thread = thread
      @client = client
    end

    def create_post(raw_name, raw_mail, raw_body, raw_title = '')
      if raw_name.blank?
        raw_name = @board.default_name
      end

      date = PostBuilder.format_date(Time.now.localtime)
      if requires_id?(raw_mail)
        date = "#{date} ID:#{client_id}"
      end

      Post.new(escape_field(raw_name),
               escape_field(raw_mail),
               date,
               escape_body(raw_body),
               raw_title)
    end

    def client_id
      Digest::MD5.base64digest(@client.remote_addr)[0,8]
    end

    def requires_id?(mail)
      case @board.id_policy
      when :no then false
      when :force then true
      when :optional then mail.blank?
      else raise 'panic'
      end
    end

    private

    ESCAPE_TABLE = { '<' => '&lt;', '>' => '&gt;', '&' => '&amp;' }.freeze
    def escape_field(str)
      str.gsub(/[<>&]/) { |char| ESCAPE_TABLE[char] }
    end

    def escape_body(body)
      ' ' + linkify(escape_field(body)).each_line.map(&:chomp).join(' <br> ') + ' '
    end

    # レスアンカーをリンクにする
    def linkify(escaped_body)
      PostBuilder.linkify(escaped_body, @board.id, @thread.id)
    end
  end
end
