require 'fileutils'
require_relative 'atomic_write_file'

# system('echo hoge > test.txt')
# AtomicWriteFile.open('test.txt', './tmp') do |w|
#   w.write('fuga')
# end
# system('cat test.txt')

FileUtils.rm_f 'test.txt'
AtomicWriteFile.open('test.txt', 'tmp') do |w|
  w.write('fuga')
end
raise unless `cat test.txt` == 'fuga'
FileUtils.rm_f 'test.txt'

puts 'all tests passed'

