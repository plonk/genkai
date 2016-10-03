require_relative 'test_common'
require_relative 'settings'

include Genkai

FileUtils.rm_f 'dict.txt'
s = SettingsFile.new('dict.txt')
raise unless s['hoge'] == nil
s['hoge'] = 'あいうえお'
raise unless s['hoge'] == 'あいうえお'
s.save

s = SettingsFile.new('dict.txt')
raise unless s['hoge'] == 'あいうえお'
FileUtils.rm_f 'dict.txt'

puts 'all tests passed'
