# frozen_string_literal: true
require_relative 'test_common'
require_relative 'string_helpers'

include StringHelpers

raise unless escape_field('abc<>') == 'abc&lt;&gt;'
raise unless escape_field('') == ''

raise unless unescape_field('&lt;&gt;&amp;') == '<>&'
raise unless unescape_field('') == ''

raise unless escape_1001("abc<>\ndef") == 'abc&lt;&gt;<br>\ndef'
raise unless escape_1001('') == ''

raise unless unescape_1001("abc&lt;&gt;<br>\ndef") == "abc<>\ndef"
raise unless unescape_1001('') == ''

puts 'all tests passed'
