# coding: utf-8
require 'sunflower'
require 'json'
require 'pp'

require './savepoint.rb'

lines = SavePoint.here! 'existing-lines' do
	s = Sunflower.new('w:pl').login
	wd = Sunflower.new('https://www.wikidata.org').login
	
	list = s.make_list 'category', 'Kategoria:Noty biograficzne'
	list.delete 'Noty biograficzne'
	text = list.pages_preloaded.map(&:text).inject(:+)
	text.split(/\n/)
end

junk = lines.grep(/===|\{\{Noty bio|<\/?center|\[\[kategoria:|^[:*]?\s*$|^\[\[#|__NOTOC__/i)
lines -= junk

items = lines.grep(/[-–—−,]/)
aliases = lines.grep(/[→>›]/)
items = lines - aliases

err = []

items = items.map{|e|
	_, title, years, desc = *e.match(/^[:#*]\s*\[\[([^|\]]+)(?:\|[^\]]*)?\]\]\s*(?:(?:[(){}]|(?=ur|\d))(.+?)[(){}]\s*)?[-–—−,]\s*(.+)$/)
	if !_ 
		err << e
		nil
	else
		[title.strip, years&&years.strip, desc.strip]
	end
}.compact

aliases = aliases.map{|e|
	_, from, to, other = *e.match(/^[:#*]\s*\[*([^|\]]+)(?:\|[^\]]*)?\]*\s*(?:[-–—−]*[→>›])\s*\[\[([^|\]]+)(?:\|([^\]]*))?\]\]/)
	if !_ || !from || !to
		err << e
		nil
	else
		from.strip!
		to.strip!
		other && other.strip!
		if other
			if from == to
				[other, to]
			elsif other.split(', ').reverse.join(' ').downcase.sub('- ', '-') == to.downcase
				[from, to]
			else
				err << e
				nil
			end
		else
			[from, to]
		end
	end
}.compact

File.binwrite 'aliases.txt', aliases.map{|from, to|
	"* #{from} → [[#{to}]]"
}.join("\n")
File.binwrite 'items.json', items.to_json
File.binwrite 'unparsed.txt', err.join("\n")
