# coding: utf-8
require 'sunflower'
require 'parallel'
require 'unicode_utils'
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
# 	pageid: '',
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
		
		res['entities'].each do |itemid, r|
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
		
		res['query']['pages'].each do |pageid, r|
			next if !r['categories'] # probably redirect or page otherwise gone
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
						"#{birthinfo[1]} - #{deathinfo[1]}"
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

prefix = 'Wikipedysta:Matma Rex/Noty_biograficzne/'

# add aliases
aliases_page = s.page(prefix+'Aliasy')
if aliases_page.text.empty?
	aliases_page.text = File.read('aliases.txt', encoding: 'utf-8')
end

# parse the page and mark errors
aliases = []
invalid_aliases = []
aliases_page.text.split(/\n/).each{|ln|
	next unless ln =~ /^[:#*]/
	_, from, to = *ln.match(/^[:#*]\s*(.+?)\s*(?:-*[→>›])\s*\[\[([^|\]]+)\]\]*$/)
	if _ and from and to
		aliases << {
			alias: true,
			defaultsort: from.strip,
			title: to.strip,
		}
	else
		invalid_aliases << ln
	end
}
unless invalid_aliases.empty?
	invalid_aliases.each do |ln|
		aliases_page.text.sub!(/\s*#{Regexp.escape ln}\s*/, "\n")
	end
	aliases_page.text += "\n\n== Nierozpoznane wpisy ==\n#{invalid_aliases.join "\n"}"
end

items += aliases

def build_heading text
	@pliterki_heading ||= Hash[ 'ążśźęćńółĄŻŚŹĘĆŃÓŁ'.split('').map{|l| [l, l] } ]
	# to ascii except for letters with Polish diacritics
	text = text.to_ascii(@pliterki_heading).tr('@','a').tr("'`\"",'')
	# strip non-letters like ",", ignore all after first space; uppercase first letter only
	return (UnicodeUtils.titlecase text.sub(/ .+/, '').gsub(/[^a-zA-ZążśźęćńółĄŻŚŹĘĆŃÓŁ]/, '')).first(3)
end
def build_sortkey text
	@pliterki_sortkey ||= Hash[ 'ążśźęćńółĄŻŚŹĘĆŃÓŁ'.split('').map{|l| [l, l.to_ascii('ż'=>'z~', 'Ż'=>'Z~')+'~'] } ]
	# convert everything to ascii, sort letters with Polish diacritics after all other ones
	text = text.to_ascii(@pliterki_sortkey).tr('@','a').tr("'`\"",'').downcase
	# strip non-letters like ","
	return text.gsub(/[^a-zA-Z~ ]/, '')
end

items.each do |h|
	h[:heading] = build_heading(h[:defaultsort] || h[:title])
	h[:sortkey] = build_sortkey(h[:defaultsort] || h[:title])
	h[:heading] = '0-9' if h[:heading].empty?
end

items.sort_by!{|h| h[:sortkey] }

# split into pages.
# prefer one page == one letter, but only up to 1k entries per page.
# then prefer chunking by 2 letters and finally by 3 (all).
structured = items.chunk{|h| h[:heading].first(1) }.map{|page, hs|
	if hs.length>1000
		hs.chunk{|h| h[:heading].first(2) }.map{|page, hs|
			if hs.length>1000
				hs.chunk{|h| h[:heading] }.to_a
			else
				[[page, hs]]
			end
		}.inject(:+)
	else
		[[page, hs]]
	end
}.inject(:+)

index_page = s.page(prefix+'Indeks')
index = structured.map(&:first).chunk{|a| a[0] }.map{|_, pagenames|
	pagenames.map{|pgnm| "[[#{prefix+pgnm}|#{pgnm}]]" }.join(" &bull; ")
}.join("<br>")
index_page.text = index

allowed_pages = %w[Ob Q]

def render_line h, other_items, aliases_page_title, star=true
	encoded_title = URI::encode_www_form_component h[:title]

	if h[:alias]
		[
			(star ? '*' : nil),
			"#{h[:defaultsort]}",
			"→",
			render_line(other_items.find{|h2| h2[:title] == h[:title] && !h2[:alias] }, other_items, aliases_page_title, false),
			"&#x5B;[[#{aliases_page_title}|edytuj alias]]]",
		].compact.join(' ')
	else
		[
			(star ? '*' : nil),
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
end

pages = structured.map do |page_title, contents|
	next unless allowed_pages.include? page_title
	
	lines = []
	contents.chunk{|h| h[:heading] }.each do |heading, hs|
		lines << ""
		lines << "=== #{heading} ==="
		hs.each{|h|
			lines << render_line(h, items, aliases_page.title)
		}
	end
	
	puts page_title
	
	if contents.empty?
		nil
	else
		page = s.page(prefix+page_title)
		page.text = lines.join("\n")
		page
	end
end

mode = :save # or :dump
s.summary = 'aktualizacja list'
pages.compact.each(&mode)
aliases_page.send(mode)
index_page.send(mode)
