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
to_upload = to_upload.reject{|t,_,d| titles.include? t }

$stderr.puts to_upload.length

puts 'no mode given' if !ARGV[0]
dry_run = ARGV[0] != '--upload'

wdtoken = wd.API('action=tokens&type=edit')['tokens']['edittoken'] unless dry_run

Parallel.each_with_index(to_upload, in_threads: 10) do |(title, _, desc), i|
	begin
		if i % 100 == 0
			$stderr.puts i 
			Thread.exclusive{ $stdout.flush }
		end
		if dry_run
			res = wd.API(
				action: 'wbgetentities',
				props: 'descriptions',
				languages: 'pl',
				sites: 'plwiki',
				titles: title,
			)
			ent = res['entities'].values[0]
			
			if ent['missing']
				Thread.exclusive{ puts "Would create new item for #{title}" }
			elsif ent['descriptions'] and ent['descriptions']['pl']['value'] == desc
				Thread.exclusive{ puts "Would ignore (description already present) #{title}" }
			elsif ent['descriptions']
				Thread.exclusive{ puts "Would overwrite description for #{title}" }
			else
				# not a particularly interesting case.
			end
		else
			res = wd.API(
				action: 'wbsetdescription',
				token: wdtoken,
				bot: true,
				summary: "imported description from the Polish Wikipedia",
				
				site: 'plwiki',
				title: title,
				language: 'pl',
				value: desc,
			)
			if res['error'] and res['error']['code'] == 'no-such-entity-link'
				# create full new entity
				data = {
					sitelinks: {
						plwiki: {
							site: 'plwiki',
							title: title
						}
					},
					labels: {
						pl: {
							language: 'pl',
							value: title
						}
					},
					descriptions: {
						pl: {
							language: 'pl',
							value: desc
						}
					}
				}
				res = wd.API(
					action: 'wbeditentity',
					token: wdtoken,
					bot: true,
					summary: "imported description from the Polish Wikipedia",
					
					data: data.to_json,
					new: 'item',
				)
			end
			
			if !res['success']
				Thread.exclusive do
					pp res
					puts "Error: #{title}"
				end
			end
		end
	rescue RestClient::BadGateway, Errno::ECONNRESET, RestClient::RequestTimeout, RestClient::ServerBrokeConnection
		retry
	end
end
