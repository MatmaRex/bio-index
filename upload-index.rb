# coding: utf-8
require 'sunflower'
require 'parallel'
require 'json'
require 'pp'

require './savepoint.rb'

wd = Sunflower.new('www.wikidata.org').login

to_upload = JSON.parse File.binread 'items.json'
info = SavePoint.here! 'props-list' do
	raise 'props-list missing!'
end

titles = info.select{|h| %w[Ob Qu].include?((h[:defaultsort] || h[:title])[0, 2]) }.map{|h| h[:title] }
to_upload = to_upload.select{|t,_,d| titles.include? t }

p to_upload.length

to_upload.drop(5).drop(50).each do |title, _, desc|
	wdtoken = wd.API('action=tokens&type=edit')['tokens']['edittoken']
	p wd.API(
		action: 'wbsetdescription',
		token: wdtoken,
		bot: true,
		summary: "imported description from the Polish Wikipedia",
		
		site: 'plwiki',
		title: title,
		language: 'pl',
		value: desc,
	)
	
end

