# coding: utf-8
require 'sunflower'
require 'parallel'
require 'roman'
# require 'unicode_utils'
require 'yaml'
YAML::ENGINE.yamler = 'syck' # stupid unidecoder
require 'unidecoder'
require 'uri'
require 'pp'

require './savepoint.rb'

s = Sunflower.new('w:pl').login
wd = Sunflower.new('www.wikidata.org').login

list = SavePoint.here! 'category' do
	[
		s.make_list('category_recursive', 'Kategoria:Biografie według daty urodzin'),
		s.make_list('category_recursive', 'Kategoria:Biografie według daty śmierci'),
	].flatten
end

list = list.reject{|a| a.start_with? 'Kategoria:' }
list.uniq!
list.sort!

# p list.length

# {
# 	title: '',
# 	defaultsort: '',
# 	pageid: 'Q',
# 	itemid: 'Q',
# }
items = SavePoint.here! 'props-list' do
	Parallel.map_with_index( list.each_slice(500), in_threads: 5 ) do |titles, i|
		# p i
		res = s.API(
			action: 'query',
			prop: 'pageprops',
			titles: titles.join('|'),
		)
		
		res['query']['pages'].values.map do |r|
			{
				title: r['title'],
				pageid: r['pageid'],
				defaultsort: (r['pageprops'] && r['pageprops']['defaultsort']),
				itemid: (r['pageprops'] && r['pageprops']['wikibase_item'] && r['pageprops']['wikibase_item'].upcase),
			}
		end
	end.flatten
end

# p items.length

# add :description
items = SavePoint.here! 'entity-list' do
	Parallel.each_with_index( items.each_slice(500), in_threads: 5 ) do |hs, i|
		p i
		map = Hash[ hs.map{|h| h[:itemid] ? [ h[:itemid], h ] : nil }.compact ]
		
		res = wd.API(
			action: 'wbgetentities',
			props: 'descriptions',
			languages: 'pl',
			ids: hs.map{|h| h[:itemid] }.compact.join('|')
		)
		
		res['entities'].map do |itemid, r|
			map[itemid.upcase][:description] = (r['descriptions']['pl']['value'] rescue nil)
		end
	end
	items
end

# add :lifetime
birthcat = /^Urodzeni w (\d+)$/
deathcat = /^Zmarli w (\d+)$/
items = SavePoint.here! 'lifetime' do
	Parallel.each_with_index( items.each_slice(500), in_threads: 5 ) do |hs, i|
		p i
		
		map = Hash[ hs.map{|h| [ h[:pageid].to_i, h ] } ]
		
		res = s.API(
			action: 'query',
			prop: 'categories',
			cllimit: 'max',
			titles: hs.map{|h| h[:title] }.join('|'),
		)
		
		res['query']['pages'].map do |pageid, r|
			cats = r['categories'].map{|c| c['title'].sub(/^Kategoria:/, '') }
			
			birthcat = cats.grep(/^Nieznana data urodzin$|^Urodzeni w /)[0]
			deathcat = cats.grep(/^Nieznana data śmierci$|^Zmarli w /)[0]
			
			dates = [birthcat, deathcat].map{|cat|
				case cat
				when /^Nieznana data/, nil
					[:none, false]
				when /w ([IVX]+) wieku( p\.n\.e\.|)$/
					[:century, "#{$1} w.#{$2}"]
				when /w (\d+)( p\.n\.e\.|)$/
					[:year, "#{$1}#{$2}"]
				else 
					raise cat
				end
			}
			
			birthinfo, deathinfo = *dates
			lifetime = case [birthinfo[0], deathinfo[0]]
				when [:none, :none]
					nil
				when [:none, :century]
					"zm. #{deathinfo[1]}"
				when [:none, :year]
					"zm. #{deathinfo[1]}"
				when [:century, :none]
					"ur. #{birthinfo[1]}"
				when [:century, :century]
					if birthinfo[1] == deathinfo[1]
						"#{birthinfo[1]}"
					else
						"#{birthinfo[1]}-#{deathinfo[1]}"
					end
				when [:century, :year]
					"#{birthinfo[1]} - #{deathinfo[1]}"
				when [:year, :none]
					"ur. #{birthinfo[1]}"
				when [:year, :century]
					"#{birthinfo[1]} - #{deathinfo[1]}"
				when [:year, :year]
					"#{birthinfo[1]}-#{deathinfo[1]}"
				end
			;
			
			map[pageid.to_i][:lifetime] = lifetime
		end
	end
	items
end

# add aliases
aliases = File.readlines('aliases.txt', encoding: 'utf-8').map{|ln|
	_, from, to = *ln.match(/^[:#*]\s*\[*([^|\]]+)(?:\|[^\]]*)?\]*\s*(?:-*[→>›])\s*\[*([^|\]]+)(?:\|[^\]]*)?\]*$/)
	{
		alias: true,
		defaultsort: from.strip,
		title: to.strip,
	}
}

items += aliases

pliterki = Hash[ 'ążśźęćńółĄŻŚŹĘĆŃÓŁ'.split('').map{|l| [l, l.to_ascii(ż: 'z~')+'~'] } ]
items.each do |h|
	h[:sortkey] = (h[:defaultsort] || h[:title]).to_ascii(pliterki).downcase
end

items.sort_by!{|h| h[:sortkey] }

############
ob = items.select{|h| %w[Ob Qu].include?((h[:defaultsort] || h[:title])[0, 2]) }

lines = []
ob.chunk{|h| (h[:defaultsort] || h[:title])[0, 3] }.each{|heading, hs|
	lines << ""
	lines << "=== #{heading[0].upcase + heading[1..-1]} ==="
	hs.each{|h|
		encoded_title = URI::encode_www_form_component h[:title]
		
		if h[:alias]
			lines << "* #{h[:defaultsort]} → [[#{h[:title]}]] &#x5B;[[(aliasy)|edytuj]]]"
		else
			lines << [
				'*',
				(h[:defaultsort] ?
					"[[#{h[:title]}|#{h[:defaultsort]}]]" :
					"[[#{h[:title]}]]"),
				(h[:lifetime] ?
					"(#{h[:lifetime]})"  :
					nil),
				'–',
				(h[:description] ?
					"#{h[:description]}"  :
					"''brak opisu w Wikidanych''"),
				(h[:itemid] ?
					"&#x5B;[[d:#{h[:itemid]}|#{h[:description] ? 'edytuj' : 'dodaj'}]]]" :
					"&#x5B;[//www.wikidata.org/wiki/Special:NewItem?site=plwiki&label=#{encoded_title}&page=#{encoded_title} utwórz element i dodaj opis]]"),
			].compact.join(' ')
		end
	}
}

puts lines
