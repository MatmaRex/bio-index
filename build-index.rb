# coding: utf-8
require 'sunflower'
require 'parallel'
require 'unidecoder'
require 'uri'
require 'nokogiri' # no kill like overkill
require 'pp'

require './roman.rb'
require './savepoint.rb'
require './intro-extractor.rb'

s = Sunflower.new('w:pl').login
wd = Sunflower.new('https://www.wikidata.org').login

list = SavePoint.here! 'category' do
	list = [
		s.make_list('category_recursive', 'Kategoria:Biografie według daty urodzin'),
		s.make_list('category_recursive', 'Kategoria:Biografie według daty śmierci'),
	].flatten
	list.reject!{|a| a.start_with? 'Kategoria:' }
	list.uniq!
	list.sort!
	list
end

# p list.length

# {
# 	title: '',
# 	defaultsort: '',
# 	pageid: '',
# 	itemid: 'Q',
# }
items = SavePoint.here! 'props-list' do
	Parallel.map_with_index( list.each_slice(50), in_threads: 5 ) do |titles, i|
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
	Parallel.each_with_index( items.each_slice(50), in_threads: 5 ) do |hs, i|
		# p i
		map = Hash[ hs.map{|h| h[:itemid] ? [ h[:itemid], h ] : nil }.compact ]
		
		res = wd.API(
			action: 'wbgetentities',
			props: 'descriptions',
			languages: 'pl',
			ids: hs.map{|h| h[:itemid] }.compact.join('|')
		)
		
		res['entities'].each do |itemid, r|
			next if !map[itemid.upcase]
			map[itemid.upcase][:description] = (r['descriptions']['pl']['value'] rescue nil)
		end
	end
	items
end

def parse_one year
	pne = year.index(/p\.?n\.?e/) ? -1 : 1
	case year
	when /\d+/;    year[/\d+/].to_i * pne
	when /[IVX]+/; year[/[IVX]+/].to_roman * pne
	else; nil
	end
end

# add :lifetime
birthcat = /^Urodzeni w (\d+)$/
deathcat = /^Zmarli w (\d+)$/
items = SavePoint.here! 'lifetime' do
	Parallel.each_with_index( items.each_slice(50), in_threads: 5 ) do |hs, i|
		# p i
		map = Hash[ hs.map{|h| [ h[:pageid].to_i, h ] } ]
		
		res = s.API(
			action: 'query',
			prop: 'categories',
			cllimit: 'max',
			titles: hs.map{|h| h[:title] }.join('|'),
		)
		
		res['query']['pages'].each do |pageid, r|
			next if !map[pageid.to_i]
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
						"#{birthinfo[1]} – #{deathinfo[1]}"
					end
				when [:century, :year]
					"#{birthinfo[1]} – #{deathinfo[1]}"
				when [:year, :none]
					"ur. #{birthinfo[1]}"
				when [:year, :century]
					"#{birthinfo[1]} – #{deathinfo[1]}"
				when [:year, :year]
					"#{birthinfo[1]}–#{deathinfo[1]}"
				end
			;
			
			birthyear_approx = birthinfo[0] != :none ? parse_one(birthinfo[1]) : nil rescue nil
			deathyear_approx = deathinfo[0] != :none ? parse_one(deathinfo[1]) : nil rescue nil
			birthyear_approx = (birthyear_approx.to_i) * 100 if RomanNumeral === birthyear_approx
			deathyear_approx = (deathyear_approx.to_i) * 100 if RomanNumeral === deathyear_approx
			
			map[pageid.to_i][:birthyear_approx] = birthyear_approx
			map[pageid.to_i][:deathyear_approx] = deathyear_approx
			map[pageid.to_i][:lifetime] = lifetime
		end
	end
	items
end

# add :descriptionSuggestion
items = SavePoint.here! 'descriptionSuggestion' do
	map = Hash[ items.map{|h| [ h[:title], h ] } ]
	
	dump_filename = '%USERPROFILE%/Downloads/plwiki-20240120-pages-meta-current.xml.bz2'
	# two reasons for not using bzip2-ruby gem: it's a pita to build on windows
	# and this magically provides parallelization of unzipping and processing
	io = IO.popen "bzip2 -dc #{dump_filename}", 'rb'
	io.gets '</siteinfo>'

	i = 0
	while true
		i += 1
		p i if i % 1000 == 0
		
		pg = io.gets('</page>')
		break if io.eof? # last read is useless
		
		noko = Nokogiri.XML pg
		title = noko.at('title').text
		next if !map[title]
		
		lifetime, intro = *parse_intro(noko.at('text').text)
		map[title][:descriptionSuggestion] = intro
	end
	
	items
end

prefix = 'Wikipedia:Indeks biografii/'

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
	return text.sub(/ .+/, '').gsub(/[^0-9a-zA-ZążśźęćńółĄŻŚŹĘĆŃÓŁ]/, '').capitalize[0, 3]
end
def build_sortkey text
	@pliterki_sortkey ||= Hash[ 'ążśźęćńółĄŻŚŹĘĆŃÓŁ'.split('').map{|l| [l, l.to_ascii('ż'=>'z~', 'Ż'=>'Z~')+'~'] } ]
	# convert everything to ascii, sort letters with Polish diacritics after all other ones
	text = text.to_ascii(@pliterki_sortkey).tr('@','a').tr("'`\"",'').downcase
	# strip non-letters like ","
	return text.gsub(/[^0-9a-zA-Z~ ]/, '')
end

items.each do |h|
	h[:heading] = build_heading(h[:defaultsort] || h[:title])
	h[:heading] = '0-9' if h[:heading].empty? or h[:heading] =~ /^[0-9]/
	
	h[:sortkey] = build_sortkey(h[:defaultsort] || h[:title])
end

# sort by defaultsort first, lifetime second, title as last resort for stable sort results
# lifetime is an array or nil of arrays or nils; perfectly sortable
items.sort_by!{|h| [ h[:sortkey], h[:birthyear_approx]||Float::INFINITY, h[:title] ] }

# split into pages.
# prefer one page == one letter, but only up to 1k entries per page.
# then prefer chunking by 2 letters and finally by 3 (all).
structured = items.chunk{|h| h[:heading][0, 1] }.map{|page, hs|
	if hs.length>1000
		hs.chunk{|h| h[:heading][0, 2] }.map{|page, hs|
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

previous_index_pages = s.make_list 'links_on', prefix+'Indeks'
current_index_pages = s.make_list 'pages', structured.map{|pgnm, _| prefix+pgnm }
unused_index_pages = previous_index_pages - current_index_pages

# list all index pages. mark ones with no missing descriptions with bold.
index_page = s.page(prefix+'Indeks')

index = structured.map{|page_title, contents|
	# page is done if all entries have a non-empty description
	[page_title, contents.all?{|h| h[:alias] || (h[:description] && !h[:description].empty?) }]
}.chunk{|page_title, is_done|
	# group by first letter
	page_title[0]
}.map{|first_letter, list_items|
	# generate list section for each first letter
	content = list_items.map{|page_title, is_done|
		link = "[[#{prefix+page_title}|#{page_title}]]"
		is_done ? "* '''#{link}'''" : "* #{link}"
	}.join("\n")
}.join("\n\n")

index_page.text = "<div class=hlist>\n#{index}\n</div>"

def render_line h, other_items, aliases_page_title
	encoded_title = URI::encode_www_form_component h[:title]
	
	if h[:alias]
		# use the item this one points to with additional alias information added
		old_h = h
		h = other_items.find{|h2| h2[:title] == old_h[:title] && !h2[:alias] }
		return nil if !h
		h = h.dup
		h[:aliased] = old_h[:defaultsort]
	end

	# transcribe the data into HTML for easy access
	div = Nokogiri.HTML('<div/>').at('div')
	div['class'] = 'bioindex-entry'
	div['data-title'] = h[:title].to_s if h[:title]
	div['data-defaultsort'] = h[:defaultsort].to_s if h[:defaultsort]
	div['data-lifetime'] = h[:lifetime].to_s if h[:lifetime]
	div['data-description'] = h[:description].to_s if h[:description]
	div['data-description-suggestion'] = h[:descriptionSuggestion].to_s if h[:descriptionSuggestion]
	div['data-itemid'] = h[:itemid].to_s if h[:itemid]
	div['data-aliased'] = h[:aliased].to_s if h[:aliased]
	div.content = '~~~~' # guaranteed not to appear in wikitext
	wrap_start, wrap_end = *div.to_s.split('~~~~')
	
	display = [
		(h[:aliased] ?
			[
				h[:aliased],
				"<span class='bioindex-edit mw-editsection-like'>&#x5B;[[#{aliases_page_title}|edytuj alias]]]</span>",
				'→'
			] :
			nil),
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
			"<span class='bioindex-edit mw-editsection-like'>&#x5B;[[d:Special:ItemByTitle/plwiki/#{h[:title]}|#{h[:description] ? 'edytuj' : 'dodaj'}]]]</span>" :
			"<span class='bioindex-edit mw-editsection-like'>&#x5B;[//www.wikidata.org/wiki/Special:NewItem?site=plwiki&label=#{encoded_title}&page=#{encoded_title} utwórz element i dodaj opis]]</span>"),
	].flatten.compact.join(' ')
	
	"* #{wrap_start}#{display}#{wrap_end}"
end

pages = structured.map do |page_title, contents|
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
		page.text = lines.compact.join("\n")
		page
	end
end

pages += unused_index_pages.map do |full_page_title|
	page = s.page(full_page_title)
	page.text = "{{ek|pusta strona indeksu biografii}}"
	page
end

mode = :dump # or :save
s.summary = 'aktualizacja list'

# save/dump all pages
(pages.compact + [aliases_page, index_page]).each do |p|
	begin
		p.send mode
	rescue RestClient::BadGateway, Errno::ECONNRESET, RestClient::RequestTimeout, RestClient::ServerBrokeConnection
		retry
	end
end
