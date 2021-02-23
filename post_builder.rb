# frozen_string_literal: true
require_relative 'extensions'
require_relative 'board'
require_relative 'thread'
require_relative 'post'
require_relative 'string_helpers'

module Genkai
  # レスが投稿された時に、Postオブジェクトを作るクラス。
  class PostBuilder
    include StringHelpers

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

    attr_reader :id

    def initialize(board, thread, remote_addr)
      @board = board
      @thread = thread
      @id = Digest::MD5.base64digest(remote_addr)[0, 8]
    end

    def create_post(raw_name, raw_mail, raw_body, raw_title = '')
      raw_name = @board.default_name if raw_name.blank?

      date = PostBuilder.format_date(Time.now.localtime)
      date = "#{date} ID:#{@id}" if requires_id?(raw_mail)

      Post.new(escape_field(raw_name),
               escape_field(raw_mail),
               date,

               escape_body(raw_body),
               raw_title)
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

    def escape_body(body)
      lines = linkify(escape_field(body)).each_line.map(&:chomp)
      ' ' + lines.join(' <br> ') + ' '
    end

    # レスアンカーをリンクにする
    def linkify(escaped_body)
      PostBuilder.linkify(escaped_body, @board.id, @thread.id)
    end
  end
end
