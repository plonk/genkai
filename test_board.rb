# frozen_string_literal: true
require_relative 'test_common'
require_relative 'board'

include Genkai

b = Board.new('public/shuuraku')

raise unless b.title.is_a?(String)
raise unless b.id.is_a?(String)
raise unless b.local_rules.is_a?(String)
raise unless [:no, :optional, :force].include?(b.id_policy)
raise unless b.default_name.is_a?(String)
raise unless b.get_all_threads.is_a? Array
