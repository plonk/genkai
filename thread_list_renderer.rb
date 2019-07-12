# frozen_string_literal: true
require_relative 'string_helpers'

module Genkai
  class ThreadListRenderer
    include StringHelpers

    def initialize(threads)
      @threads = threads
    end

    def render
      @threads.sort_by(&:mtime).reverse # いちばん最近更新されたものが先頭。
           .map { |thread| "#{thread.id}.dat<>#{escape_field(thread.subject)} (#{thread.size})\n" }
           .join
    end
  end
end
