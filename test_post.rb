# frozen_string_literal: true
require_relative 'post'
include Genkai

line = "予定地<>sage<>2016/09/26(月) 17:53:00 ID:9Sh2TWJN<> Jane Style からのスレッド作成テスト <>ほげほげ\n"

post = Post.from_line(line)

raise unless post.name == '予定地'
raise unless post.mail == 'sage'
raise unless post.date == '2016/09/26(月) 17:53:00 ID:9Sh2TWJN'
raise unless post.body == ' Jane Style からのスレッド作成テスト '
raise unless post.subject == 'ほげほげ'
raise unless post.date_proper == '2016/09/26(月) 17:53:00'
raise unless post.id == '9Sh2TWJN'

puts 'all tests passed'
