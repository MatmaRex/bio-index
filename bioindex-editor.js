/*global jQuery, mediaWiki, console */

/**
 * Użycie: dodaj do [[Special:Mypage/common.js]] poniższe dwa wpisy:
 * 
 *   importScript('Wikipedysta:Matma Rex/bioindex-editor.js');
 *   importStylesheet('Wikipedysta:Matma Rex/bioindex-editor.css');
 * 
 * Wersja bardzo alfa.
 */

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
					$('<li>').text('Lata życia nie są na razie edytowalne z poziomu tego narzędzia. Aby je poprawić, zmodyfikuj kategorie urodzenia i śmierci w artykule.')
				),
				$('<h3>').text('Porady dotyczące opisów na Wikidanych:'),
				$('<ul>').append(
					$('<li>').text('Długość nie powinna przekraczać 10-15 słów; często wystarczą 2-3.'),
					$('<li>').text('Opis nie jest zdaniem: powinien zaczynać się małą literą, nie powinien kończyć się kropką.'),
					$('<li>').text('Poprawny szyk to zwykle „polski wikipedysta”, nie „wikipedysta polski”.'),
					$('<li>').text('Nie wspominaj o „obecnych” rzeczach – funkcjach polityków, klubach piłkarzy itd.')
				)
			);
			
			var title = $entry.data('title');
			var defaultsort = $entry.data('defaultsort');
			var lifetime = $entry.data('lifetime');
			var description = $entry.data('description');
			var descriptionSuggestion = $entry.data('descriptionSuggestion');
			var itemid = $entry.data('itemid');
			
			var $editsectionLink = $entry.find('.mw-editsection').detach();
			
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
				mw.html.escape(lifetime ? ' ('+lifetime+')' : ''),
				' – ',
				$descriptionEntry, ' ',
				$saveButton, ' ',
				$cancelButton, ' ',
				$goToNextCheckboxLabel,
				$instructions,
				$dummyForMeasurements
			);
			$entry.empty().addClass('bioindex-entry-active').append( $form );
			$descriptionEntry.focus();
			
			// autosizing
			$dummyForMeasurements.css('font', $defaultsortEntry.css('font'));
			$defaultsortEntry.add($descriptionEntry).on('keyup keydown keypress change cut paste', function(){
				$dummyForMeasurements.text( 'X' + $(this).val() + 'X' );
				$(this).css('width', Math.min(Math.max($dummyForMeasurements.width(), 100), 600) );
			}).trigger('keyup');
			
			function rebuild() {
				if(description) {
					$editsectionLink.find('a').text('edytuj');
				}
				$entry.empty().append(
					$articleLink.attr('title', title).text(defaultsort||title),
					mw.html.escape(lifetime ? ' ('+lifetime+')' : ''),
					' – ',
					description ? mw.html.escape(description) : $('<em>').text('brak opisu w Wikidanych'),
					' ',
					$editsectionLink
				);
				
				$entry.data('title', title);
				$entry.data('defaultsort', defaultsort);
				$entry.data('lifetime', lifetime);
				$entry.data('description', description);
				$entry.data('itemid', itemid);
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
						
						if(pagetext.indexOf('{{DEFAULTSORT:')) {
							pagetext = pagetext.replace(/{{DEFAULTSORT:.+?}}/, newdefsort);
						} else {
							pagetext = pagetext.replace(/\[\[\s*(kategoria|category)\s*:/i, newdefsort+"\n"+'$&');
						}
						
						wpApi.post({
							action: 'edit',
							token: wptoken,
							title: title,
							text: pagetext,
							summary: "poprawa DEFAULTSORT via [[:pl:"+pagename+"|noty biograficzne]]",
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
					var $all = $('#mw-content-text').find('.bioindex-entry[data-description=""]').add($entry);
					if($all.length > 1) {
						var idx = $all.index($entry);
						var $next = $all.eq( idx === $all.length-1 ? 0 : idx+1 );
						$next.find('.mw-editsection a').trigger('click');
					}
				}
				
				$.when(
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
