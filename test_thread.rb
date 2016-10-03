# frozen_string_literal: true
require_relative 'thread'
require 'fileutils'
include Genkai

line = "予定地<>sage<>2016/09/26(月) 17:53:00 ID:9Sh2TWJN<> Jane Style からのスレッド作成テスト <>ほげほげ\n"
ONE_BILLION_DOT_DAT = '1000000000.dat'

File.open(ONE_BILLION_DOT_DAT, 'w', encoding: 'CP932') do |dat|
  dat.write line
end

thread = ThreadFile.new(ONE_BILLION_DOT_DAT)

raise unless thread.id == '1000000000'
raise unless thread.posts.size == 1
raise unless thread.subject == 'ほげほげ'

post = Post.new('name', 'mail', '2016/09/26(月) 17:53:00', ' body ', '')
thread.posts << post
thread.save

raise unless `wc -l #{ONE_BILLION_DOT_DAT}`.to_i == 2

# 存在しない dat で初期化。

TWO_BILLION_DOT_DAT = '2000000000.dat'
FileUtils.rm_f TWO_BILLION_DOT_DAT
thread = ThreadFile.new(TWO_BILLION_DOT_DAT)
raise unless thread.posts == []
thread.posts << post
thread.save

raise unless `wc -l #{TWO_BILLION_DOT_DAT}`.to_i == 1

FileUtils.rm_f ONE_BILLION_DOT_DAT
FileUtils.rm_f TWO_BILLION_DOT_DAT
