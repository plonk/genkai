# frozen_string_literal: true
require_relative 'test_common'
require_relative 'numbered_element'

ary = NumberedElement.to_numbered_elements %w(a b b)
raise unless ary.is_a? Array
raise unless ary.size == 3
raise unless ary[0].number == 1
raise unless ary[0].upcase == 'A'

puts 'all tests passed'
