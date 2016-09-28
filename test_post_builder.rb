require_relative 'test_common'
require_relative 'post_builder'
include Genkai
raise unless PostBuilder.linkify('&gt;&gt;1スレ立て乙', 'fuga', '1234567890') == "<a href=\"/test/read.cgi/fuga/1234567890/1\">&gt;&gt;1</a>スレ立て乙"
raise unless PostBuilder.linkify('&gt;&gt;20-21お前ら結婚しろｗｗｗｗ', 'fuga', '1234567890') == "<a href=\"/test/read.cgi/fuga/1234567890/20-21\">&gt;&gt;20-21</a>お前ら結婚しろｗｗｗｗ"

puts 'all tests passed'
