/*global jQuery, mediaWiki, console */

(function($, mw){
	if($('.bioindex-entry').length === 0) {
		// only load when relevant
		return;
	}
	
	mw.loader.load('jquery.spinner');
	mw.loader.load('mediawiki.api');
	mw.loader.load('jquery.wikibase.linkitem');
	
	function notify(text, tag) {
		mw.notify(text, {autoHide: !!tag, tag: 'bioindex'+tag});
	}
	
	function regexpEscape(str) {
		return str.replace(/([\\{}()|.?*+\-\^$\[\]])/g, '\\$1');
	}
	
	function errorHandler() {
		notify('Coś poszło nie tak. Odśwież stronę!');
		console.log(this);
		console.log(arguments);
	}
	
	var wdLoginCheck = function(api) {
		return api.post({
			action: 'query',
			meta: 'userinfo'
		}).fail(errorHandler).done(function(resp) {
			var username = resp.query.userinfo.name;
			var anon = resp.query.userinfo.anon !== undefined;
			wdLoginCheck = $.noop; // self-destruct
			notify('Edytujesz Wikidane jako ' + username + (anon ? ' (niezalogowany!)' : '') + '.');
		});
	};
	
	var goToNextActive = false;
	
	$('#mw-content-text').on('click keypress', '.bioindex-entry .mw-editsection a', function(e) {
		var that = this;
		mw.loader.using(['jquery.spinner', 'mediawiki.api', 'jquery.wikibase.linkitem'], function() {
			/*global wikibase*/
			if(e.type === 'keypress' && e.which !== 13 && e.which !== 32) {
				return; // handle enter and space
			}
			e.preventDefault();
			
			var wdApi = new wikibase.RepoApi();
			wdLoginCheck(wdApi);
			var wpApi = new mw.Api();
			
			var $entry = $(that).closest('.bioindex-entry');
			
			var $instructions = $('<div>').addClass('bioindex-help').append(
				$('<h3>').text('Instrukcja:'),
				$('<ul>').append(
					$('<li>').text('Zmiana wyświetlanego imienia i nazwiska spowoduje zmianę {{DEFAULTSORT: w artykule.'),
					$('<li>').text('Zmiana opisu spowoduje zmianę opisu artykułu na Wikidanych.'),
					$('<li>').text('Lata życia nie będą edytowalne z poziomu tego narzędzia. Aby je poprawić, zmodyfikuj kategorie urodzenia i śmierci w artykule.'),
					$('<li>').text('Ustawienie pustego aliasu jest równoznaczne z usunięciem go.')
				),
				$('<h3>').text('Porady dotyczące opisów na Wikidanych:'),
				$('<ul>').append(
					$('<li>').text('Długość nie powinna przekraczać 10-15 słów; często wystarczą 2-3.'),
					$('<li>').text('Opis nie jest zdaniem: powinien zaczynać się małą literą, nie powinien kończyć się kropką.'),
					$('<li>').text('Poprawny szyk to zwykle „polski wikipedysta”, nie „wikipedysta polski”.'),
					$('<li>').text('Utrzymuj ponadczasowy styl – nie wspominaj o „obecnych” funkcjach polityków, klubach piłkarzy itd.')
				)
			);
			
			var title = $entry.data('title') || '';
			var defaultsort = $entry.data('defaultsort') || '';
			var lifetime = $entry.data('lifetime') || '';
			var description = $entry.data('description') || '';
			var descriptionSuggestion = $entry.data('descriptionSuggestion') || '';
			var itemid = $entry.data('itemid') || '';
			var aliased = $entry.data('aliased') || '';
			
			var $editsectionLinks = $entry.find('.mw-editsection').detach();
			
			function buildAddAliasButton(text) {
				var $a = $('<a>')
					.text(text)
					.attr('href', mw.util.wikiGetlink('Wikipedia:Indeks biografii/Aliasy'));
				return $('<span class=mw-editsection>').append( '[', $a, ']' );
			}
			
			var $addAliasButton = buildAddAliasButton('dodaj alias');
			var $aliasEntry = $('<input type=text>').val(aliased);
			$addAliasButton.find('a').on('click keypress', function(e) {
				if(e.type === 'keypress' && e.which !== 13 && e.which !== 32) {
					return; // handle enter and space
				}
				e.preventDefault();
				
				$addAliasButton.remove();
				$form.prepend($aliasEntry, ' → ');
				$aliasEntry.focus();
			});
			
			// rebuild the entry with edit fields
			var $defaultsortEntry = $('<input type=text>').val(defaultsort||title);
			var $articleLink = $('<a>').text('↗')
				.attr('href', mw.util.wikiGetlink(title))
				.attr('title', 'Przejdź do artykułu: '+title);
			var $descriptionEntry = $('<input type=text>').val(description||descriptionSuggestion);
			var $saveButton = $('<button type=submit>').text('zapisz');
			var $cancelButton = $('<button type=reset>').text('anuluj');
			var $goToNextCheckbox = $('<input type=checkbox>').prop('checked', goToNextActive);
			var $goToNextCheckboxLabel = $('<label>').text(' po zapisaniu przejdź do nast. bez opisu').prepend($goToNextCheckbox);
			
			var $dummyForMeasurements = $('<span>').addClass('bioindex-dummy');
			
			var $form = $('<form>').append(
				$defaultsortEntry,
				$articleLink,
				$addAliasButton,
				mw.html.escape(lifetime ? ' ('+lifetime+')' : ''),
				' – ',
				$descriptionEntry, ' ',
				$saveButton, ' ',
				$cancelButton, ' ',
				$goToNextCheckboxLabel,
				$instructions,
				$dummyForMeasurements
			);
			if(aliased) {
				$addAliasButton.find('a').trigger('click');
			}
			$entry.empty().append( $form );
			$descriptionEntry.focus();
			
			// autosizing
			$dummyForMeasurements.css('font', $defaultsortEntry.css('font'));
			$defaultsortEntry.add($descriptionEntry).add($aliasEntry).on('keyup keydown keypress change cut paste', function(){
				$dummyForMeasurements.text( 'X' + $(this).val() + 'X' );
				$(this).css('width', Math.min(Math.max($dummyForMeasurements.width(), 100), 600) );
			}).trigger('keyup');
			
			function rebuild() {
				if(description) {
					$editsectionLinks.last().find('a').text('edytuj');
				}
				$entry.empty().append(
					aliased ? mw.html.escape(aliased) + ' ' : '',
					aliased ? $editsectionLinks.first() : '',
					aliased ? ' → ' : '',
					$articleLink.attr('title', title).text(defaultsort||title),
					mw.html.escape(lifetime ? ' ('+lifetime+')' : ''),
					' – ',
					description ? mw.html.escape(description) : $('<i>').text('brak opisu w Wikidanych'),
					' ',
					$editsectionLinks.last()
				);
				$aliasEntry.remove(); // if it was not inserted, we need to clear event jQuery handlers manually
				
				$entry.data('title', title);
				$entry.data('defaultsort', defaultsort);
				$entry.data('lifetime', lifetime);
				$entry.data('description', description);
				$entry.data('itemid', itemid);
				$entry.data('aliased', aliased);
				
				// .data doesn't update data- attributes (only reads from them), and we depend on this one for goToNextActive
				$entry.attr('data-description', description);
			}
			
			function handleAlias(){
				var promise = $.Deferred();
				
				var oldText = aliased;
				var newText = $.trim( $aliasEntry.val() );
				if(newText == aliased) {
					promise.resolve(null);
					return promise;
				}
				aliased = newText;
				
				var pagename = mw.config.get('wgPageName');
				var aliases_pagename = 'Wikipedia:Indeks biografii/Aliasy';
				wpApi.get({
					action: 'tokens',
					type: 'edit'
				}).fail(errorHandler).done(function(resp){
					var wptoken = resp.tokens.edittoken;
					
					wpApi.get({
						action: 'query',
						prop: 'revisions',
						rvprop: 'content',
						rvlimit: '1',
						titles: aliases_pagename,
						indexpageids: true
					}).fail(errorHandler).done(function(resp){
						var pagetext = resp.query.pages[ resp.query.pageids[0] ].revisions[0]['*'];
						var newalias = aliased ? ('* ' + aliased + ' → [[' + title + ']]') : '';
						
						if(oldText) {
							var oldalias = new RegExp('^[:#*]\\s*(' + regexpEscape(oldText) + ')\\s*(?:-*[→>›])\\s*\\[\\[' + regexpEscape(title) + '\\]\\]*$', 'm');
							pagetext = pagetext.replace(oldalias, newalias);
						} else {
							pagetext += "\n" + newalias;
						}
						
						wpApi.post({
							action: 'edit',
							token: wptoken,
							title: aliases_pagename,
							text: pagetext,
							summary: (oldText ? "modyfikacja" : "dodanie") + " aliasu via [["+pagename+"|noty biograficzne]]",
						}).fail(errorHandler).done(function(resp){
							if(resp.edit && resp.edit.result == 'Success') {
								var diff = "/?oldid="+resp.edit.newrevid+"&diff=prev";
								notify( $('<span>').append(
									'Zapisano zmiany w artykule ' + mw.html.escape(aliases_pagename) + '. ',
									$('<a>').text('Diff').attr('href', diff),
									'.'
								), 'aliased' );
								promise.resolve(resp);
							} else {
								promise.reject(resp);
							}
						});
					});
				});
				
				return promise;
			}
			function handleDefaultsort(){
				var promise = $.Deferred();
				
				var newText = $.trim( $defaultsortEntry.val() );
				if(newText == defaultsort) {
					promise.resolve(null);
					return promise;
				}
				defaultsort = newText;
				
				var pagename = mw.config.get('wgPageName');
				wpApi.get({
					action: 'tokens',
					type: 'edit'
				}).fail(errorHandler).done(function(resp){
					var wptoken = resp.tokens.edittoken;
					
					wpApi.get({
						action: 'query',
						prop: 'revisions',
						rvprop: 'content',
						rvlimit: '1',
						titles: title,
						indexpageids: true
					}).fail(errorHandler).done(function(resp){
						var pagetext = resp.query.pages[ resp.query.pageids[0] ].revisions[0]['*'];
						var newdefsort = '{{DEFAULTSORT:'+defaultsort+'}}';
						
						if(pagetext.indexOf('{{DEFAULTSORT:') !== -1) {
							pagetext = pagetext.replace(/{{DEFAULTSORT:.+?}}/, newdefsort);
						} else {
							pagetext = pagetext.replace(/\[\[\s*(kategoria|category)\s*:/i, newdefsort+"\n"+'$&');
						}
						
						wpApi.post({
							action: 'edit',
							token: wptoken,
							title: title,
							text: pagetext,
							summary: "poprawa DEFAULTSORT via [["+pagename+"|noty biograficzne]]",
						}).fail(errorHandler).done(function(resp){
							if(resp.edit && resp.edit.result == 'Success') {
								var diff = "/?oldid="+resp.edit.newrevid+"&diff=prev";
								notify( $('<span>').append(
									'Zapisano zmiany w artykule ' + mw.html.escape(title) + '. ',
									$('<a>').text('Diff').attr('href', diff),
									'.'
								), 'defaultsort' );
								promise.resolve(resp);
							} else {
								promise.reject(resp);
							}
						});
					});
				});
				
				return promise;
			}
			function handleDescription(){
				var promise = $.Deferred();
				
				var newText = $.trim( $descriptionEntry.val() );
				if(newText == description) {
					promise.resolve(null);
					return promise;
				}
				description = newText;
				
				var pagename = mw.config.get('wgPageName');
				wdApi.get({
					action: 'tokens',
					type: 'edit'
				}).fail(errorHandler).done(function(resp){
					var wdtoken = resp.tokens.edittoken;
					
					wdApi.post({
						action: 'wbsetdescription',
						token: wdtoken,
						summary: "edit made via [[:pl:"+pagename+"|Polish Wikipedia index of biographies]]",
						site: 'plwiki',
						title: title,
						language: 'pl',
						value: description
					}).fail(errorHandler).done(function(resp){
						if(resp.success) {
							var diff = "//www.wikidata.org/?oldid="+resp.entity.lastrevid+"&diff=prev";
							notify( $('<span>').append(
								'Zapisano zmiany we wpisie ' + mw.html.escape(title) + '. ',
								$('<a>').text('Diff').attr('href', diff),
								'.'
							), 'description' );
							promise.resolve(resp);
						} else {
							promise.reject(resp);
						}
					});
				});
				
				return promise;
			}
			
			$form.on('reset', function(e) {
				e.preventDefault();
				rebuild();
			});
			$form.on('submit', function(e) {
				e.preventDefault();
				var $spinner = $.createSpinner();
				$form.append(' ', $spinner);
				
				goToNextActive = $goToNextCheckbox.prop('checked');
				if(goToNextActive) {
					// this kinda sucks
					var entriesNoDesc = '.bioindex-entry[data-description=""], .bioindex-entry:not([data-description])';
					var $all = $('#mw-content-text').find(entriesNoDesc).add($entry);
					if($all.length > 1) {
						var idx = $all.index($entry);
						var $next = $all.eq( idx === $all.length-1 ? 0 : idx+1 );
						$next.find('.mw-editsection a').trigger('click');
					}
				}
				
				$.when(
					handleAlias().fail(errorHandler),
					handleDefaultsort().fail(errorHandler),
					handleDescription().fail(errorHandler)
				).then(function(){
					$spinner.remove();
					rebuild();
				});
			});
		});
	});
})(jQuery, mediaWiki);
